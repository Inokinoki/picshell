import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/launch_unlock.dart';
import 'package:picshell/services/vault_service.dart';

class _FakeBackend implements VaultBackend {
  bool canAuth = true;
  bool authResult = true;
  bool authThrows = false;
  int authCalls = 0;
  String? storedKey;

  @override
  Future<bool> get canCheckBiometrics async => canAuth;

  @override
  Future<bool> authenticate({String reason = ''}) async {
    authCalls++;
    if (authThrows) throw Exception('no biometric hardware');
    return authResult;
  }

  @override
  Future<String?> readKey() async => storedKey;

  @override
  Future<void> writeKey(String key) async => storedKey = key;

  @override
  Future<void> deleteKey() async => storedKey = null;
}

void main() {
  late Directory tempDir;
  late Box settingsBox;
  late HostStore hostStore;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_launch_');
    Hive.init(tempDir.path);
    Hive.registerAdapter(HostAdapter());
    Hive.registerAdapter(AuthTypeAdapter());
    Hive.registerAdapter(SshKeyAdapter());
    Hive.registerAdapter(SessionAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    settingsBox = await Hive.openBox('settings');
    hostStore = HostStore();
    await hostStore.init();
  });

  tearDown(() async {
    await settingsBox.clear();
    await Hive.deleteFromDisk();
  });

  Future<void> _requireBiometric(bool v) => settingsBox.put('requireBiometric', v);

  test('no requirement: unlocked, no prompt, no key release', () async {
    final backend = _FakeBackend()..storedKey = 'enrolled-key';
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isFalse);
    expect(backend.authCalls, 0);
    expect(hostStore.isEncrypting, isFalse);
  });

  test('required + available + success: key released, not bypassed', () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()
      ..storedKey = 'enrolled-key'
      ..authResult = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isFalse);
    expect(backend.authCalls, 1);
    expect(hostStore.isEncrypting, isTrue);
  });

  test('required + available + cancel: starts locked', () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()..authResult = false;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isTrue);
    expect(result.gateBypassed, isFalse);
    expect(hostStore.isEncrypting, isFalse);
  });

  test('required + biometrics unavailable + passcode fallback succeeds: '
      'verified, not bypassed, key released', () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = 'enrolled-key'
      ..authResult = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(backend.authCalls, 1,
        reason: 'authenticate() must still be attempted for the passcode '
            'fallback even when canAuthenticate is false');
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isFalse);
    expect(hostStore.isEncrypting, isTrue);
  });

  test('required + unavailable + fallback fails: key released, bypass flagged',
      () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = 'enrolled-key'
      ..authResult = false;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isTrue, reason: 'UI must warn the user');
    expect(hostStore.isEncrypting, isTrue,
        reason: 'data availability: the enrolled key is still released so '
            'ciphertext does not get surfaced/overwritten as plaintext');
  });

  test('required + unavailable + authenticate throws: recovery + bypass flag',
      () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = 'enrolled-key'
      ..authThrows = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isTrue);
    expect(hostStore.isEncrypting, isTrue);
  });

  test('required + unavailable + no key ever enrolled: bypass flagged, '
      'cipher untouched', () async {
    await _requireBiometric(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = null
      ..authResult = false;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isTrue);
    expect(hostStore.isEncrypting, isFalse);
  });
}
