import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/forward_rule.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('forward_rule_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ForwardTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(ForwardRuleAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('ForwardRule Hive round-trip', () {
    test('persists a local forward and reads it back', () async {
      final box = await Hive.openBox<ForwardRule>('local_fwd');
      final rule = ForwardRule(
        id: 'r1',
        type: ForwardType.local,
        localHost: '127.0.0.1',
        localPort: 8080,
        remoteHost: 'db.internal',
        remotePort: 5432,
        autoStart: true,
      );
      await box.put('r1', rule);
      final read = box.get('r1')!;

      expect(read.id, 'r1');
      expect(read.type, ForwardType.local);
      expect(read.localHost, '127.0.0.1');
      expect(read.localPort, 8080);
      expect(read.remoteHost, 'db.internal');
      expect(read.remotePort, 5432);
      expect(read.autoStart, true);
      await box.deleteFromDisk();
    });

    test('persists nullable remote fields for a SOCKS rule', () async {
      final box = await Hive.openBox<ForwardRule>('socks_fwd');
      final rule = ForwardRule(
        id: 'r2',
        type: ForwardType.socks,
        localPort: 1080,
      );
      await box.put('r2', rule);
      final read = box.get('r2')!;

      expect(read.type, ForwardType.socks);
      expect(read.localPort, 1080);
      expect(read.remoteHost, isNull);
      expect(read.remotePort, isNull);
      await box.deleteFromDisk();
    });
  });

  group('ForwardType adapter', () {
    test('every type value round-trips', () async {
      for (final t in ForwardType.values) {
        final box = await Hive.openBox<ForwardRule>('ftype_${t.name}');
        await box.put('k', ForwardRule(id: 'x', type: t, localPort: 1));
        expect(box.get('k')!.type, t);
        await box.deleteFromDisk();
      }
    });
  });

  group('ForwardRule.summary', () {
    test('formats each type like ssh syntax', () {
      expect(
        ForwardRule(
          id: 'a',
          type: ForwardType.local,
          localPort: 8080,
          remoteHost: 'db',
          remotePort: 5432,
        ).summary,
        '-L 8080:db:5432',
      );
      expect(
        ForwardRule(
          id: 'b',
          type: ForwardType.remote,
          localPort: 9000,
          remoteHost: 'localhost',
          remotePort: 22,
        ).summary,
        '-R 9000:localhost:22',
      );
      expect(
        ForwardRule(id: 'c', type: ForwardType.socks, localPort: 1080).summary,
        '-D 1080',
      );
    });
  });
}
