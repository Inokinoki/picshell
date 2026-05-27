import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';

class SessionState {
  final String id;
  final Host host;
  final SshService sshService;
  final Terminal terminal;
  final bool connected;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    Terminal? terminal,
    this.connected = false,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);
}

final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
      return SessionListNotifier();
    });

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  SessionListNotifier() : super([]);

  Future<void> openSession(Host host, SshConnectionConfig config) async {
    final service = SshService();
    final terminal = Terminal(maxLines: 10000);
    final sessionId = '${host.id}_${DateTime.now().millisecondsSinceEpoch}';

    terminal.onOutput = (data) {
      service.writeToTerminal(data);
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      service.resizeTerminal(width, height);
    };

    final session = SessionState(
      id: sessionId,
      host: host,
      sshService: service,
      terminal: terminal,
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
