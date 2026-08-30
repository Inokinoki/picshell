import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import '../models/floating_image.dart';
import '../models/host.dart';
import '../services/known_hosts_store.dart';
import '../services/ssh_service.dart';
import 'floating_image_provider.dart';

const _uuid = Uuid();

class SessionState {
  final String id;
  final Host host;
  final SshTransport sshService;
  final Terminal terminal;
  final bool connected;
  final bool reconnecting;
  final DateTime createdAt;
  final SshConnectionConfig? config;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    Terminal? terminal,
    this.connected = false,
    this.reconnecting = false,
    DateTime? createdAt,
    this.config,
  }) : terminal = terminal ?? Terminal(maxLines: 10000),
       createdAt = createdAt ?? DateTime.now();
}

final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
      return SessionListNotifier(ref);
    });

final selectedSessionSizeProvider =
    StateProvider<({int width, int height})?>((ref) => null);

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  final Ref _ref;

  /// Seam for tests: drive the session lifecycle with fake transports
  /// instead of real SSH connections.
  final SshTransport Function() _transportFactory;

  SessionListNotifier(
    this._ref, {
    @visibleForTesting SshTransport Function()? transportFactory,
  })  : _transportFactory = transportFactory ?? SshService.new,
        super([]);

  @visibleForTesting
  void debugAddSession(SessionState session) {
    state = [...state, session];
  }

  Future<void> openSession(Host host, SshConnectionConfig config) async {
    // Inject host-key verification (TOFU). We build a derived config that
    // carries an onVerifyHostKey callback consulting the known_hosts store;
    // the original config from the UI does not have one. This derived config
    // is what gets stored on the SessionState, so reconnects are verified too.
    //
    // The callback must NOT throw: newer dartssh2 swallows callback
    // exceptions and fails the connect with a generic
    // "connection closed before authentication" SSHAuthAbortError, which
    // would hide the TOFU prompt. Instead we record the rejection, return
    // false, and re-raise the typed exception after connect() fails.
    final knownHosts = _ref.read(knownHostsStoreProvider);
    HostKeyVerification? hostKeyRejection;
    String? rejectedKeyType;
    Uint8List? rejectedFingerprint;
    final verifiedConfig = SshConnectionConfig(
      host: config.host,
      port: config.port,
      username: config.username,
      authMethod: config.authMethod,
      password: config.password,
      privateKeyPem: config.privateKeyPem,
      passphrase: config.passphrase,
      onVerifyHostKey: (type, fingerprint) async {
        final result = await knownHosts.verify(
          config.host, config.port, type, fingerprint,
        );
        if (result == HostKeyVerification.trusted) return true;
        hostKeyRejection = result;
        rejectedKeyType = type;
        rejectedFingerprint = fingerprint;
        return false;
      },
    );

    final service = _transportFactory();
    final terminal = Terminal(maxLines: 10000);
    final sessionId = _uuid.v4();
    final createdAt = DateTime.now();

    // Seed the new terminal with the size of the last live terminal so the
    // very first pty resize (applied when the shell channel opens) matches
    // the window — otherwise the remote stays at the default geometry until
    // the user resizes the window.
    final lastSize = _ref.read(selectedSessionSizeProvider);
    if (lastSize != null) {
      terminal.resize(lastSize.width, lastSize.height);
    }

    _bindTerminalIo(sessionId, terminal);

    terminal.onImageDecoded = (
      Uint8List bytes,
      String imgName,
      Iterm2Dimension? w,
      Iterm2Dimension? h, {
      inline = true,
      preserveAspectRatio = true,
    }) {
      final image = FloatingImage(
        id: _uuid.v4(),
        rawBytes: bytes,
        name: imgName,
        requestedWidth: w,
        requestedHeight: h,
        inline: inline,
        preserveAspectRatio: preserveAspectRatio,
      );
      _ref.read(floatingImagesProvider.notifier).addImage(image);
    };

    final session = SessionState(
      id: sessionId,
      host: host,
      sshService: service,
      terminal: terminal,
      createdAt: createdAt,
      config: verifiedConfig,
    );
    state = [...state, session];

    final outputSubscription = service.output.listen((data) {
      terminal.write(data);
    });
    _outputSubscriptions[sessionId] = outputSubscription;

    service.connectionState.listen(
      (connected) {
        if (!connected &&
            !state.any((s) => s.id == session.id && s.reconnecting)) {
          _scheduleReconnect(session.id);
        }
      },
      // A transport that errors mid-session has effectively disconnected.
      onError: (_) {
        if (!state.any((s) => s.id == session.id && s.reconnecting)) {
          _scheduleReconnect(session.id);
        }
      },
    );

    try {
      await service.connect(verifiedConfig);
      state = [
        for (final s in state)
          if (s.id == session.id)
            SessionState(
              id: s.id,
              host: s.host,
              sshService: s.sshService,
              terminal: s.terminal,
              connected: true,
              config: s.config,
            )
          else
            s,
      ];
    } catch (e) {
      closeSession(session.id);
      // Restore the typed host-key exceptions the UI knows how to present.
      if (hostKeyRejection != null) {
        final fingerprintHex = _hex(rejectedFingerprint!);
        if (hostKeyRejection == HostKeyVerification.mismatch) {
          throw HostKeyMismatchException(
            config.host, config.port, rejectedKeyType!, fingerprintHex,
          );
        }
        throw UnknownHostException(
          config.host, config.port, rejectedKeyType!, fingerprintHex,
        );
      }
      rethrow;
    }
  }

  /// Terminal I/O must always target the session's CURRENT transport, so the
  /// closures resolve the service from the state on every call instead of
  /// capturing the first one — after a reconnect, keystrokes would otherwise
  /// keep going to the disposed transport.
  void _bindTerminalIo(String sessionId, Terminal terminal) {
    SshTransport? currentService() {
      for (final s in state) {
        if (s.id == sessionId) return s.sshService;
      }
      return null;
    }

    terminal.onOutput = (data) => currentService()?.writeToTerminal(data);
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _ref.read(selectedSessionSizeProvider.notifier).state =
          (width: width, height: height);
      currentService()?.resizeTerminal(width, height);
    };
  }

  void closeSession(String id) {
    final session = state.firstWhere(
      (s) => s.id == id,
      orElse: () => throw StateError('Not found'),
    );
    _reconnectTimers.remove(id)?.cancel();
    _reconnectAttempts.remove(id);
    _outputSubscriptions.remove(id)?.cancel();
    session.sshService.dispose();
    state = state.where((s) => s.id != id).toList();
  }

  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, StreamSubscription<String>> _outputSubscriptions = {};

  void _scheduleReconnect(String sessionId) {
    if (!mounted) return;
    final session = state.where((s) => s.id == sessionId).firstOrNull;
    if (session == null || session.config == null) return;

    state = [
      for (final s in state)
        if (s.id == sessionId)
          SessionState(
            id: s.id,
            host: s.host,
            sshService: s.sshService,
            terminal: s.terminal,
            connected: false,
            reconnecting: true,
            config: s.config,
          )
        else
          s,
    ];

    final attempts = (_reconnectAttempts[sessionId] ?? 0) + 1;
    _reconnectAttempts[sessionId] = attempts;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, then capped at 30s.
    final delay = Duration(seconds: (1 << (attempts - 1)).clamp(1, 30));

    _reconnectTimers[sessionId]?.cancel();
    _reconnectTimers[sessionId] = Timer(delay, () async {
      if (!mounted) return;
      final current = state.where((s) => s.id == sessionId).firstOrNull;
      if (current == null || current.config == null) return;

      try {
        current.sshService.dispose();
        final newService = _transportFactory();

        _outputSubscriptions[sessionId]?.cancel();
        _outputSubscriptions[sessionId] = newService.output.listen((data) {
          current.terminal.write(data);
        });

        newService.connectionState.listen(
          (connected) {
            if (!connected &&
                state.any((s) => s.id == sessionId && !s.reconnecting)) {
              _scheduleReconnect(sessionId);
            }
          },
          onError: (_) {
            if (mounted &&
                state.any((s) => s.id == sessionId && !s.reconnecting)) {
              _scheduleReconnect(sessionId);
            }
          },
        );

        await newService.connect(current.config!);
        _reconnectAttempts.remove(sessionId);

        state = [
          for (final s in state)
            if (s.id == sessionId)
              SessionState(
                id: s.id,
                host: s.host,
                sshService: newService,
                terminal: s.terminal,
                connected: true,
                reconnecting: false,
                config: s.config,
              )
            else
              s,
        ];
      } catch (_) {
        if (mounted) _scheduleReconnect(sessionId);
      }
    });
  }
}

/// Hex-encodes a byte list for display in host-key exception messages.
String _hex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
