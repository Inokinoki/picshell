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

  Future<void> requireBiometricFake(bool v) => settingsBox.put('requireBiometric', v);

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
    await requireBiometricFake(true);
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
    await requireBiometricFake(true);
    final backend = _FakeBackend()..authResult = false;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isTrue);
    expect(result.gateBypassed, isFalse);
    expect(hostStore.isEncrypting, isFalse);
  });

  test('required + biometrics unavailable + passcode fallback succeeds: '
      'verified, not bypassed, key released', () async {
    await requireBiometricFake(true);
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

  test('required + unavailable + user cancels passcode fallback: locked, '
      'NOT bypassed (no key release)', () async {
    await requireBiometricFake(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = 'enrolled-key'
      ..authResult = false;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isTrue,
        reason: 'a refused verification (cancel / wrong passcode) must lock, '
            'not bypass');
    expect(result.gateBypassed, isFalse);
    expect(hostStore.isEncrypting, isFalse,
        reason: 'the key must not be released over a refused verification');
  });

  test('required + available + authenticate THROWS: app launches locked, key '
      'not released, no bypass', () async {
    await requireBiometricFake(true);
    final backend = _FakeBackend()
      ..storedKey = 'enrolled-key'
      ..authThrows = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isTrue,
        reason: 'a local_auth throw (LockedOut/NotAvailable) must not crash '
            'startup and must not release the key');
    expect(result.gateBypassed, isFalse);
    expect(result.reEncryptionFailed, isFalse);
    expect(hostStore.isEncrypting, isFalse);
  });

  test('required + unavailable + authenticate throws: recovery + bypass flag',
      () async {
    await requireBiometricFake(true);
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

  test('interrupted enable: plaintext secrets detected after a VERIFIED '
      'launch are re-encrypted automatically', () async {
    await requireBiometricFake(true);
    // Simulate the crash state: flag on, key enrolled, data still plaintext.
    await hostStore.addKey(SshKey(
        id: 'k1', name: 'key', privateKeyPem: 'SECRET PEM', publicKey: 'pub'));
    await hostStore.addHost(Host(
        id: 'h1',
        name: 'h',
        hostname: 'example.com',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        password: 'plain-password'));
    expect(hostStore.hasUnmarkedSecrets, isTrue);
    final backend = _FakeBackend()
      ..storedKey = 'enrolled-key'
      ..authResult = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isFalse);
    expect(result.reEncryptionFailed, isFalse,
        reason: 'the repair runs under the verified key and must succeed');
    expect(hostStore.hasUnmarkedSecrets, isFalse,
        reason: 'interrupted re-encryption must be completed');
    expect(hostStore.isEncrypting, isTrue);
    // Data survived, decrypted under the released key.
    expect(hostStore.getHost('h1')!.password, 'plain-password');
    expect(hostStore.getKey('k1')!.privateKeyPem, 'SECRET PEM');
  });

  test('interrupted enable: repair failure is reported, not swallowed', () async {
    await requireBiometricFake(true);
    // Plaintext secret (triggers the repair) plus a corrupt marked record
    // (makes reEncryptAll hard-fail).
    await hostStore.addHost(Host(
        id: 'h1',
        name: 'h',
        hostname: 'example.com',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        password: 'plain-password'));
    await hostStore.addHost(Host(
        id: 'h-corrupt',
        name: 'c',
        hostname: 'example.com',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        password: 'enc.v2.not-valid-base64!!'));
    final backend = _FakeBackend()
      ..storedKey = 'enrolled-key'
      ..authResult = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isFalse);
    expect(result.reEncryptionFailed, isTrue,
        reason: 'UI must warn: some secrets are still plaintext on disk');
  });

  test('no interrupted enable: verified launch does not touch the boxes',
      () async {
    await requireBiometricFake(true);
    await hostStore.addHost(Host(
        id: 'h1',
        name: 'h',
        hostname: 'example.com',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        password: 'plain-password'));
    // First launch repairs the plaintext...
    final backend = _FakeBackend()
      ..storedKey = 'enrolled-key'
      ..authResult = true;
    await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    // ...second verified launch is a no-op repair.
    final result2 = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result2.reEncryptionFailed, isFalse);
    expect(hostStore.hasUnmarkedSecrets, isFalse);
  });

  test('required + unavailable + no key ever enrolled: bypass flagged, '
      'cipher untouched', () async {
    await requireBiometricFake(true);
    final backend = _FakeBackend()
      ..canAuth = false
      ..storedKey = null
      ..authThrows = true;
    final result = await performLaunchUnlock(
        settingsBox: settingsBox, hostStore: hostStore, vault: VaultService(backend));
    expect(result.startLocked, isFalse);
    expect(result.gateBypassed, isTrue);
    expect(hostStore.isEncrypting, isFalse);
  });
}
