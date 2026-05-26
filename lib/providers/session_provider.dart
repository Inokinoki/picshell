import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';

class SessionState {
  final String id;
  final Host host;
  final SshService sshService;
  final bool connected;

  SessionState({
    required this.id,
    required this.host,
    required this.sshService,
    this.connected = false,
  });
}

final sessionListProvider =
    StateNotifierProvider<SessionListNotifier, List<SessionState>>((ref) {
      return SessionListNotifier();
    });

class SessionListNotifier extends StateNotifier<List<SessionState>> {
  SessionListNotifier() : super([]);

  Future<void> openSession(Host host, SshConnectionConfig config) async {
    final service = SshService();
    final session = SessionState(id: host.id, host: host, sshService: service);
    state = [...state, session];

    try {
      await service.connect(config);
      state = [
        for (final s in state)
          if (s.id == session.id)
            SessionState(
              id: s.id,
              host: s.host,
              sshService: s.sshService,
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
