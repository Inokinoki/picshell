import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

/// Raw dartssh2 connection probe — bypasses the app to isolate whether
/// dartssh2 + a local sshd are stable across repeated connections.
///
/// Requires a reachable sshd at 127.0.0.1:2222 accepting root/testpass
/// (e.g. the `picshell-sshd:local` docker image). Skips automatically when no
/// sshd is listening so this stays green in CI environments without it.
void main() {
  test('dartssh2 connects 5 times in a row to the local sshd', () async {
    // Skip when no sshd is reachable (CI / dev machines without the container).
    Socket? probe;
    try {
      probe = await Socket.connect('127.0.0.1', 2222,
          timeout: const Duration(seconds: 2));
    } catch (_) {
      // ignore: avoid_print
      print('no sshd at 127.0.0.1:2222 — skipping');
      return; // marks test as passing (no assertions)
    }
    await probe.close();

    final results = <String>[];
    for (int i = 1; i <= 5; i++) {
      try {
        final socket = await SSHSocket.connect('127.0.0.1', 2222,
            timeout: const Duration(seconds: 10));
        final client = SSHClient(
          socket,
          username: 'root',
          onPasswordRequest: () => 'testpass',
          onVerifyHostKey: (type, fp) async => true,
        );
        await client.authenticated.timeout(const Duration(seconds: 10));
        results.add('#$i: CONNECTED');
        client.close();
      } catch (e) {
        results.add('#$i: FAILED $e');
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    // ignore: avoid_print
    results.forEach(print);
    final ok = results.where((r) => r.contains('CONNECTED')).length;
    expect(ok, 5,
        reason: 'all 5 attempts should succeed; got:\n${results.join("\n")}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
