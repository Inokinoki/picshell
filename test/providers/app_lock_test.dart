import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/vault_service.dart';

class _FakeBackend implements VaultBackend {
  bool authResult = true;
  String? storedKey;
  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<bool> authenticate({String reason = ''}) async => authResult;
  @override
  Future<String?> readKey() async => storedKey;
  @override
  Future<void> writeKey(String key) async => storedKey = key;
  @override
  Future<void> deleteKey() async => storedKey = null;
}

void main() {
  late Directory tempDir;
  late HostStore hostStore;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_applock_');
    Hive.init(tempDir.path);
    Hive.registerAdapter(HostAdapter());
    Hive.registerAdapter(AuthTypeAdapter());
    Hive.registerAdapter(SshKeyAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    hostStore = HostStore();
    await hostStore.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('AppLockNotifier', () {
    test('unlock releases the master key to HostStore on success', () async {
      final vault = VaultService(_FakeBackend()..authResult = true);
      final notifier =
          AppLockNotifier(vault, hostStore, initiallyLocked: true);

      expect(notifier.state, isTrue); // starts locked
      expect(hostStore.isEncrypting, isFalse);

      final ok = await notifier.unlock();

      expect(ok, isTrue);
      expect(notifier.state, isFalse); // unlocked
      expect(hostStore.isEncrypting, isTrue); // passphrase now set
    });

    test('unlock on cancel stays locked and does not touch the cipher',
        () async {
      final vault = VaultService(_FakeBackend()..authResult = false);
      final notifier =
          AppLockNotifier(vault, hostStore, initiallyLocked: true);

      final ok = await notifier.unlock();

      expect(ok, isFalse);
      expect(notifier.state, isTrue); // still locked
      expect(hostStore.isEncrypting, isFalse); // cipher untouched
    });

    test('lock() re-shows the gate', () async {
      final vault = VaultService(_FakeBackend()..authResult = true);
      final notifier =
          AppLockNotifier(vault, hostStore, initiallyLocked: false);

      expect(notifier.state, isFalse);
      notifier.lock();
      expect(notifier.state, isTrue);
    });
  });
}
