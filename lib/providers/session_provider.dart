import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import '../models/floating_image.dart';
import '../models/forward_rule.dart';
import '../models/host.dart';
import '../services/known_hosts_store.dart';
import '../services/ssh_service.dart';
import 'floating_image_provider.dart';
import 'host_provider.dart';

const _uuid = Uuid();

/// Snapshot of one running forward for UI display. The source of truth lives
/// inside [SshService.activeForwards]; this mirrors only what the UI needs.
class ActiveForwardInfo {
  final ForwardType type;
  final int boundPort;
  const ActiveForwardInfo(this.type, this.boundPort);
}

class SessionState {
  final String id;
  final Host host;
  final SshService sshService;
  final Terminal terminal;
  final bool connected;
  final bool reconnecting;
  final DateTime createdAt;
  final SshConnectionConfig? config;

  /// ruleId → info for forwards currently running on this session. Reset to
  /// empty whenever the underlying [SshService] is rebuilt (e.g. on reconnect)
  /// and repopulated from [Host.forwards] with [ForwardRule.autoStart] = true.
  final Map<String, ActiveForwardInfo> runningForwards;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    Terminal? terminal,
    this.connected = false,
    this.reconnecting = false,
    DateTime? createdAt,
    this.config,
    Map<String, ActiveForwardInfo>? runningForwards,
  }) : terminal = terminal ?? Terminal(maxLines: 10000),
       createdAt = createdAt ?? DateTime.now(),
       runningForwards = runningForwards ?? const {};

  /// Returns a copy with the given fields replaced. Immutable fields (id,
  /// host, terminal, createdAt, config) stay as-is. Used everywhere the
  /// notifier updates a session so adding a field only touches this method.
  SessionState copyWith({
    bool? connected,
    bool? reconnecting,
    SshService? sshService,
    Map<String, ActiveForwardInfo>? runningForwards,
  }) {
    return SessionState(
      id: id,
      host: host,
      sshService: sshService ?? this.sshService,
      terminal: terminal,
      connected: connected ?? this.connected,
      reconnecting: reconnecting ?? this.reconnecting,
      createdAt: createdAt,
      config: config,
      runningForwards: runningForwards ?? this.runningForwards,
    );
  }
}

final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
      return SessionListNotifier(ref);
    });

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  final Ref _ref;

  SessionListNotifier(this._ref) : super([]);

  @visibleForTesting
  void debugAddSession(SessionState session) {
    state = [...state, session];
  }

  Future<void> openSession(Host host, SshConnectionConfig config) async {
    // Inject host-key verification (TOFU). We build a derived config that
    // carries an onVerifyHostKey callback consulting the known_hosts store;
    // the original config from the UI does not have one. This derived config
    // is what gets stored on the SessionState, so reconnects are verified too.
    // Resolve an optional jump host from the host list and build a nested
    // config for it. _withTofu injects per-hop host-key verification, so the
    // jump host is TOFU-checked independently of the final target. Single hop
    // is exposed in the UI; the recursive _withTofu already supports chains.
    SshConnectionConfig? proxyConfig;
    if (host.proxyHostId != null) {
      final proxyHost = _resolveProxy(host.proxyHostId!);
      if (proxyHost == null) {
        throw StateError(
          'Jump host ${host.proxyHostId} no longer exists',
        );
      }
      proxyConfig = _withTofu(_configFromHost(proxyHost));
    }
    final verifiedConfig = _withTofu(SshConnectionConfig(
      host: config.host,
      port: config.port,
      username: config.username,
      authMethod: config.authMethod,
      password: config.password,
      privateKeyPem: config.privateKeyPem,
      passphrase: config.passphrase,
      proxyConfig: proxyConfig,
    ));

    final service = SshService();
    final terminal = Terminal(maxLines: 10000);
    final sessionId = _uuid.v4();
    final createdAt = DateTime.now();

    terminal.onOutput = (data) {
      service.writeToTerminal(data);
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      service.resizeTerminal(width, height);
    };

    terminal.onImageDecoded = (
      Uint8List bytes,
      String imgName,
      int? w,
      int? h, {
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

    service.output.listen((data) {
      terminal.write(data);
    });

    service.connectionState.listen((connected) {
      if (!connected &&
          !state.any((s) => s.id == session.id && s.reconnecting)) {
        _scheduleReconnect(session.id);
      }
    });

    try {
      await service.connect(verifiedConfig);
      final forwards = await _startAutoForwards(service, host);
      _patch(sessionId, (s) => s.copyWith(
        connected: true,
        runningForwards: forwards,
      ));
    } catch (e) {
      closeSession(session.id);
      rethrow;
    }
  }

  /// Starts [rule] on the session and records it in [SessionState.runningForwards].
  /// Returns the actually bound port. Throws if the session is not connected
  /// or the forward fails to bind.
  Future<int> startForward(String sessionId, ForwardRule rule) async {
    final session = _lookup(sessionId);
    final port = await session.sshService.startForward(rule);
    _patch(sessionId, (s) => s.copyWith(
      runningForwards: Map<String, ActiveForwardInfo>.from(s.runningForwards)
        ..[rule.id] = ActiveForwardInfo(rule.type, port),
    ));
    return port;
  }

  /// Stops a running forward by rule id. No-op if not running.
  Future<void> stopForward(String sessionId, String ruleId) async {
    final session = _lookup(sessionId);
    await session.sshService.stopForward(ruleId);
    _patch(sessionId, (s) {
      final updated = Map<String, ActiveForwardInfo>.from(s.runningForwards)
        ..remove(ruleId);
      return s.copyWith(runningForwards: updated);
    });
  }

  void closeSession(String id) {
    final session = state.firstWhere(
      (s) => s.id == id,
      orElse: () => throw StateError('Not found'),
    );
    _reconnectTimers.remove(id)?.cancel();
    session.sshService.dispose();
    state = state.where((s) => s.id != id).toList();
  }

  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, int> _reconnectAttempts = {};

  void _scheduleReconnect(String sessionId) {
    if (!mounted) return;
    final session = state.where((s) => s.id == sessionId).firstOrNull;
    if (session == null || session.config == null) return;

    _patch(sessionId, (s) => s.copyWith(
      connected: false,
      reconnecting: true,
      // Forwards died with the connection; clear them until reconnect succeeds.
      runningForwards: const {},
    ));

    final attempts = (_reconnectAttempts[sessionId] ?? 0) + 1;
    _reconnectAttempts[sessionId] = attempts;
    final delay = Duration(seconds: (attempts * 2).clamp(1, 30));

    _reconnectTimers[sessionId]?.cancel();
    _reconnectTimers[sessionId] = Timer(delay, () async {
      if (!mounted) return;
      final current = state.where((s) => s.id == sessionId).firstOrNull;
      if (current == null || current.config == null) return;

      try {
        current.sshService.dispose();
        final newService = SshService();

        newService.output.listen((data) {
          current.terminal.write(data);
        });

        newService.connectionState.listen((connected) {
          if (!connected &&
              state.any((s) => s.id == sessionId && !s.reconnecting)) {
            _scheduleReconnect(sessionId);
          }
        });

        await newService.connect(current.config!);
        final forwards = await _startAutoForwards(newService, current.host);
        _reconnectAttempts.remove(sessionId);

        _patch(sessionId, (s) => s.copyWith(
          sshService: newService,
          connected: true,
          reconnecting: false,
          runningForwards: forwards,
        ));
      } catch (_) {
        if (mounted) _scheduleReconnect(sessionId);
      }
    });
  }

  SessionState _lookup(String id) => state.firstWhere(
        (s) => s.id == id,
        orElse: () => throw StateError('Session $id not found'),
      );

  /// Returns [config] with an [SshConnectionConfig.onVerifyHostKey] callback
  /// that consults the known_hosts store (TOFU). Applied recursively to any
  /// nested [SshConnectionConfig.proxyConfig] so every hop is verified.
  SshConnectionConfig _withTofu(SshConnectionConfig config) {
    final knownHosts = _ref.read(knownHostsStoreProvider);
    return SshConnectionConfig(
      host: config.host,
      port: config.port,
      username: config.username,
      authMethod: config.authMethod,
      password: config.password,
      privateKeyPem: config.privateKeyPem,
      passphrase: config.passphrase,
      proxyConfig:
          config.proxyConfig == null ? null : _withTofu(config.proxyConfig!),
      onVerifyHostKey: (type, fingerprint) async {
        switch (await knownHosts.verify(
          config.host, config.port, type, fingerprint,
        )) {
          case HostKeyVerification.trusted:
            return true;
          case HostKeyVerification.mismatch:
            throw HostKeyMismatchException(
              config.host, config.port, type,
              _hex(fingerprint),
            );
          case HostKeyVerification.unknown:
            throw UnknownHostException(
              config.host, config.port, type,
              _hex(fingerprint),
            );
        }
      },
    );
  }

  /// Builds a connection config from a saved [Host], reading its key material
  /// (decrypted) from the store. Used to construct jump-host configs from a
  /// stored proxyHostId. Agent auth is left as-is — connect() will reject it
  /// when a proxyConfig is present.
  SshConnectionConfig _configFromHost(Host host) {
    String? privateKeyPem;
    if (host.authType == AuthType.key && host.keyId != null) {
      privateKeyPem =
          _ref.read(hostStoreProvider).getKey(host.keyId!)?.privateKeyPem;
    }
    return SshConnectionConfig(
      host: host.hostname,
      port: host.port,
      username: host.username,
      authMethod: _authMethodFor(host.authType),
      password: host.authType == AuthType.password ? host.password : null,
      privateKeyPem: privateKeyPem,
    );
  }

  Host? _resolveProxy(String id) {
    final hosts = _ref.read(hostListProvider);
    return hosts.where((h) => h.id == id).firstOrNull;
  }

  SshAuthMethod _authMethodFor(AuthType type) => switch (type) {
        AuthType.password => SshAuthMethod.password,
        AuthType.key => SshAuthMethod.key,
        AuthType.agent => SshAuthMethod.agent,
      };

  void _patch(String id, SessionState Function(SessionState) fn) {
    state = [for (final s in state) if (s.id == id) fn(s) else s];
  }

  /// Starts every [ForwardRule] on [host] whose [ForwardRule.autoStart] is
  /// true, returning a map of successfully started forwards. Individual
  /// failures are swallowed so a broken forward never fails the session.
  Future<Map<String, ActiveForwardInfo>> _startAutoForwards(
    SshService service,
    Host host,
  ) async {
    final result = <String, ActiveForwardInfo>{};
    for (final rule in host.forwards.where((f) => f.autoStart)) {
      try {
        final port = await service.startForward(rule);
        result[rule.id] = ActiveForwardInfo(rule.type, port);
      } catch (_) {
        // Best-effort: leave it unstarted; user can retry from the UI.
      }
    }
    return result;
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
