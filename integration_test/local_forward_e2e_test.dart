import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/models/forward_rule.dart';
import 'package:picshell/providers/session_provider.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Local port forward: forwarded port round-trips to the remote sshd',
      (tester) async {
    final container = await initApp();
    await pumpApp(tester, container);
    await connectSession(tester, container);
    final sessionId = container.read(sessionListProvider).first.id;

    final notifier = container.read(sessionListProvider.notifier);
    final boundPort = await notifier.startForward(
      sessionId,
      ForwardRule(
        id: 'e2e-local',
        type: ForwardType.local,
        localPort: 0,
        remoteHost: '127.0.0.1',
        remotePort: sshPort,
      ),
    );
    expect(boundPort, greaterThan(0), reason: 'forward should bind');

    // Dial the local end and expect the remote sshd banner back.
    final socket = await Socket.connect('127.0.0.1', boundPort,
        timeout: const Duration(seconds: 10));
    final banner = await socket.first.timeout(const Duration(seconds: 10));
    expect(String.fromCharCodes(banner.take(4)), 'SSH-',
        reason: 'tunnelled data should come from the remote sshd');
    socket.destroy();

    await notifier.stopForward(sessionId, 'e2e-local');
    await teardownSessions(tester, container);
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
