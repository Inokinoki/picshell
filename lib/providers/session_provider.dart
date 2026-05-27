import 'dart:typed_data';
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
  final DateTime createdAt;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    Terminal? terminal,
    this.connected = false,
    DateTime? createdAt,
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
          final image = FloatingImage(
            id: _uuid.v4(),
            rawBytes: bytes,
            name: imgName,
            requestedWidth: w,
            requestedHeight: h,
          );
          _ref.read(floatingImagesProvider.notifier).addImage(image);
        };

    final session = SessionState(
      id: sessionId,
      host: host,
      sshService: service,
      terminal: terminal,
      createdAt: createdAt,
    );
    state = [...state, session];

    service.output.listen((data) {
      terminal.write(data);
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
    session.sshService.dispose();
    state = state.where((s) => s.id != id).toList();
  }
}
