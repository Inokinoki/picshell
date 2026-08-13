import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/services/host_store.dart';
import 'dart:io';

void main() {
  late HostStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HostAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AuthTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(SshKeyAdapter());
    }
    store = HostStore();
    await store.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('add and retrieve host', () async {
    final host = Host(
      id: '1',
      name: 'Test',
      hostname: '192.168.1.1',
      username: 'root',
    );
    await store.addHost(host);
    expect(store.getHosts().length, 1);
    expect(store.getHost('1')?.name, 'Test');
  });

  test('delete host', () async {
    final host = Host(
      id: '1',
      name: 'Test',
      hostname: '1.2.3.4',
      username: 'u',
    );
    await store.addHost(host);
    await store.deleteHost('1');
    expect(store.getHosts().length, 0);
  });

  group('secret encryption', () {
    test('password is encrypted on disk when passphrase is set', () async {
      store.setPassphrase('master-pass');
      expect(store.isEncrypting, isTrue);

      final host = Host(
        id: '1',
        name: 'Test',
        hostname: '1.2.3.4',
        username: 'root',
        password: 'secret-password',
      );
      await store.addHost(host);

      // Read raw from the box — should NOT contain the plaintext password.
      final rawBox = Hive.box<Host>('hosts');
      final rawHost = rawBox.get('1')!;
      expect(rawHost.password, isNot(equals('secret-password')));
      expect(rawHost.password, isNot(isNull));

      // getHost decrypts back to the plaintext.
      expect(store.getHost('1')?.password, 'secret-password');
    });

    test('passwordless host is unaffected by encryption', () async {
      store.setPassphrase('master-pass');
      final host = Host(
        id: '2',
        name: 'NoPass',
        hostname: '1.2.3.4',
        username: 'root',
      );
      await store.addHost(host);
      expect(store.getHost('2')?.password, isNull);
    });

    test('private key PEM is encrypted on disk when passphrase is set',
        () async {
      store.setPassphrase('master-pass');
      final key = SshKey(
        id: 'k1',
        name: 'work',
        privateKeyPem: '-----BEGIN PRIVATE KEY-----\nPEM BODY\n-----END-----',
        publicKey: 'ssh-ed25519 AAAA',
      );
      await store.addKey(key);

      final rawBox = Hive.box<SshKey>('ssh_keys');
      final rawKey = rawBox.get('k1')!;
      expect(rawKey.privateKeyPem, isNot(contains('PEM BODY')));
      // getKeys decrypts back.
      expect(store.getKey('k1')?.privateKeyPem, contains('PEM BODY'));
    });

    test('empty passphrase keeps plaintext (backward compatible)',
        () async {
      // Default: no passphrase set.
      expect(store.isEncrypting, isFalse);
      final host = Host(
        id: '3',
        name: 'Plain',
        hostname: '1.2.3.4',
        username: 'root',
        password: 'plain-password',
      );
      await store.addHost(host);

      final rawBox = Hive.box<Host>('hosts');
      // No encryption → stored as-is.
      expect(rawBox.get('3')?.password, 'plain-password');
    });

    test('decryption falls back gracefully on wrong passphrase', () async {
      // Write encrypted under one passphrase...
      store.setPassphrase('pass1');
      await store.addHost(Host(
        id: '4',
        name: 'X',
        hostname: '1.2.3.4',
        username: 'root',
        password: 'real-secret',
      ));
      // ...then read under another. Should not throw; falls back to stored
      // ciphertext rather than returning null.
      store.setPassphrase('pass2');
      final got = store.getHost('4');
      expect(got, isNotNull);
      // Decryption failed → fallback is the (still-encrypted) stored value,
      // which is NOT the plaintext. The important guarantee: no crash, no null.
      expect(got!.password, isNot(equals('real-secret')));
    });
  });

  group('reEncryptAll', () {
    test('re-encrypts hosts and keys under a new passphrase', () async {
      store.setPassphrase('key1');
      await store.addHost(Host(
        id: 'h1',
        name: 'Host',
        hostname: '1.2.3.4',
        username: 'root',
        password: 'pw-secret',
      ));
      await store.addKey(SshKey(
        id: 'k1',
        name: 'work',
        privateKeyPem: '-----BEGIN PRIVATE KEY-----\nBODY\n-----END-----',
        publicKey: 'ssh-ed25519 AAAA',
      ));

      // Swap to a different key; everything must still decrypt cleanly.
      await store.reEncryptAll('key2');
      expect(store.getHost('h1')?.password, 'pw-secret');
      expect(store.getKey('k1')?.privateKeyPem, contains('BODY'));
    });

    test('reEncryptAll to empty passphrase stores plaintext (disable vault)',
        () async {
      store.setPassphrase('key1');
      await store.addHost(Host(
        id: 'h2',
        name: 'Host',
        hostname: '1.2.3.4',
        username: 'root',
        password: 'plain-again',
      ));

      await store.reEncryptAll('');

      // Raw box now holds the plaintext directly (no encryption).
      final rawBox = Hive.box<Host>('hosts');
      expect(rawBox.get('h2')?.password, 'plain-again');
      // And decryption (now a passthrough) still returns it.
      expect(store.getHost('h2')?.password, 'plain-again');
    });

    test('reEncryptAll leaves passwordless hosts intact', () async {
      store.setPassphrase('key1');
      await store.addHost(Host(
        id: 'h3',
        name: 'NoPw',
        hostname: '1.2.3.4',
        username: 'root',
      ));
      await store.reEncryptAll('key2');
      expect(store.getHost('h3')?.password, isNull);
    });
  });
}
