import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/forward_rule.dart';
import 'package:picshell/services/forward_listener.dart';

/// Integration test for the hand-rolled SOCKS5 dynamic forward.
///
/// Requires a reachable sshd at 127.0.0.1:2222 accepting root/testpass
/// (the `picshell-sshd:local` docker image, same as sshd_smoke_test). Tests
/// are REGISTERED with a real `skip:` when no sshd is listening, so CI
/// reports them as skipped rather than vacuously passing.
///
/// The SOCKS CONNECT target is the sshd's own port (127.0.0.1:22 from inside
/// the container). The container cannot reach the host's loopback, so we tunnel
/// to a target the server can actually see and read back its SSH banner.
void main() async {
  // Probe sshd BEFORE registering tests, so the skip flag is known at
  // declaration time.
  final sshdUp = await _probeSshd();
  final skip = sshdUp ? false : 'no sshd at 127.0.0.1:2222';

  SSHClient? client;
  ActiveForward? forward;

  setUp(() async {
    final socket = await SSHSocket.connect('127.0.0.1', 2222,
        timeout: const Duration(seconds: 10));
    client = SSHClient(
      socket,
      username: 'root',
      onPasswordRequest: () => 'testpass',
      onVerifyHostKey: (type, fp) async => true,
    );
    await client!.authenticated.timeout(const Duration(seconds: 10));

    final rule = ForwardRule(
      id: 'socks-test',
      type: ForwardType.socks,
      localPort: 0,
    );
    forward = await ActiveForward.bind(client!, rule);
  });

  tearDown(() async {
    try {
      await forward?.stop();
    } catch (_) {}
    try {
      client?.close();
    } catch (_) {}
  });

  /// Buffered reader over a socket, for parsing SOCKS5 replies. Polls the real
  /// event loop (real-async integration test, not a widget test).
  Future<Uint8List> readExact(Socket s, _Buf acc, int n) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (acc.data.length < n) {
      if (acc.done) {
        throw StateError('socket closed; got ${acc.data.length} of $n bytes');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('timed out reading $n SOCKS bytes');
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
    final out = Uint8List.fromList(acc.data.sublist(0, n));
    acc.data.removeRange(0, n);
    return out;
  }

  /// Performs SOCKS5 method selection (NO-AUTH) then a CONNECT request, and
  /// returns the 10-byte command reply. The caller chooses [atyp] + [addr].
  Future<Uint8List> socksConnect(
    Socket s,
    _Buf acc, {
    required int atyp,
    required List<int> addr,
    int port = 22,
  }) async {
    s.add(Uint8List.fromList([0x05, 0x01, 0x00]));
    final method = await readExact(s, acc, 2);
    expect(method, [0x05, 0x00],
        reason: 'method selection should pick NO-AUTH');
    s.add(Uint8List.fromList([
      0x05, 0x01, 0x00, atyp, // VER CMD RSV ATYP
      ...addr,
      (port >> 8) & 0xff, port & 0xff,
    ]));
    return readExact(s, acc, 10);
  }

  group('SOCKS5 dynamic forward', () {
    test('a client offering no acceptable method is rejected', () async {
      final s = await Socket.connect('127.0.0.1', forward!.boundPort);
      final acc = _Buf();
      s.listen((d) => acc.data.addAll(d), onDone: () => acc.done = true);
      // Offer only USERNAME/PASSWORD (0x02), which picshell does not support.
      s.add(Uint8List.fromList([0x05, 0x01, 0x02]));
      final reply = await readExact(s, acc, 2);
      expect(reply[0], 0x05);
      expect(reply[1], 0xFF); // no acceptable methods
      await s.close();
    }, skip: skip, timeout: const Timeout(Duration(seconds: 15)));

    test('IPv4 CONNECT opens a tunnel (sshd banner round-trips)', () async {
      final s = await Socket.connect('127.0.0.1', forward!.boundPort);
      final acc = _Buf();
      s.listen((d) => acc.data.addAll(d), onDone: () => acc.done = true);

      final rep =
          await socksConnect(s, acc, atyp: 0x01, addr: [127, 0, 0, 1]);
      expect(rep[0], 0x05);
      expect(rep[1], 0x00, reason: 'CONNECT should succeed');

      // The tunnelled sshd greets us with its version banner.
      final banner = await readExact(s, acc, 4);
      expect(utf8.decode(banner), 'SSH-');
      await s.close();
    }, skip: skip, timeout: const Timeout(Duration(seconds: 15)));

    test('domain ATYP CONNECT also succeeds', () async {
      final s = await Socket.connect('127.0.0.1', forward!.boundPort);
      final acc = _Buf();
      s.listen((d) => acc.data.addAll(d), onDone: () => acc.done = true);

      const domain = 'localhost';
      final rep = await socksConnect(s, acc,
          atyp: 0x03, addr: [domain.length, ...domain.codeUnits]);
      expect(rep[0], 0x05);
      expect(rep[1], 0x00, reason: 'domain CONNECT should succeed');
      final banner = await readExact(s, acc, 4);
      expect(utf8.decode(banner), 'SSH-');
      await s.close();
    }, skip: skip, timeout: const Timeout(Duration(seconds: 15)));
  });
}

/// True when the sshd container is listening on 127.0.0.1:2222.
Future<bool> _probeSshd() async {
  try {
    final s = await Socket.connect('127.0.0.1', 2222,
        timeout: const Duration(seconds: 2));
    await s.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Mutable accumulator fed by a socket subscription.
class _Buf {
  final List<int> data = [];
  bool done = false;
}
