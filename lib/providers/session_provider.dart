import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import '../models/floating_image.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';
import 'floating_image_provider.dart';

const _uuid = Uuid();

class SessionState {
  final String id;
  final Host host;
  final SshService sshService;
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

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  final Ref _ref;

  SessionListNotifier(this._ref) : super([]);

  @visibleForTesting
  void debugAddSession(SessionState session) {
    state = [...state, session];
  }

  Future<void> openSession(Host host, SshConnectionConfig config) async {
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

    terminal.onImageDecoded =
        (Uint8List bytes, String imgName, int? w, int? h) {
          print('[Session] onImageDecoded: name=$imgName, ${bytes.length} bytes');
          final image = FloatingImage(
            id: _uuid.v4(),
            rawBytes: bytes,
            name: imgName,
            requestedWidth: w,
            requestedHeight: h,
          );
          _ref.read(floatingImagesProvider.notifier).addImage(image);
          print('[Session] image added to provider, count=${_ref.read(floatingImagesProvider).length}');
        };

    final session = SessionState(
      id: sessionId,
      host: host,
      sshService: service,
      terminal: terminal,
      createdAt: createdAt,
      config: config,
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
      await service.connect(config);
      state = [
        for (final s in state)
          if (s.id == session.id)
            SessionState(
              id: s.id,
              host: s.host,
              sshService: s.sshService,
              terminal: s.terminal,
              connected: true,
            )
          else
            s,
      ];
    } catch (e) {
      closeSession(session.id);
      rethrow;
    }
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
    final delay = Duration(seconds: (attempts * 2).clamp(1, 30));

    _reconnectTimers[sessionId]?.cancel();
    _reconnectTimers[sessionId] = Timer(delay, () async {
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
        _scheduleReconnect(sessionId);
      }
    });
  }
}
