import 'dart:convert';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/session.dart';
import 'secret_cipher.dart';

/// Hive-backed persistence for hosts, SSH keys and sessions, with at-rest
/// encryption of secret fields ([Host.password], [SshKey.privateKeyPem]) via
/// [SecretCipher].
///
/// **Generational boxes:** host/key records live in generation-suffixed boxes
/// (`hosts_g1`, `hosts_g2`, …) with the active generation stored as a single
/// int in the `vault_meta` box. A generation flip is one atomic Hive `put`,
/// which is what makes [reEncryptAll] crash-safe: a new generation is fully
/// staged before the flip, so a crash at any point leaves the previously
/// active generation complete and consistent. Legacy installs (boxes named
/// `hosts`/`ssh_keys` with no generation marker) are migrated lazily on
/// [init] as generation 1.
class HostStore {
  static const _legacyHostsBox = 'hosts';
  static const _legacyKeysBox = 'ssh_keys';
  static const _sessionsBox = 'sessions';
  static const _metaBox = 'vault_meta';
  static const _genKey = 'generation';
  static const _saltKey = 'salt';

  /// KDF salt for the active cipher. Random 16 bytes, generated once and
  /// persisted in the `vault_meta` box so the derived key never depends on mutable
  /// device properties (hostname, CPU count). Existing installs that predate
  /// the persisted salt are migrated in [init]: their legacy property-derived
  /// salt is computed one last time and written to storage, preserving their
  /// data while stabilising future derivations.
  Uint8List _salt = SecretCipher.randomSalt();

  late Box<Host> _hosts;
  late Box<SshKey> _keys;
  late Box<Session> _sessions;
  late Box _meta;
  int _gen = 1;

  String get _hostsBoxName => 'hosts_g$_gen';
  String get _keysBoxName => 'ssh_keys_g$_gen';

  /// Cipher used to encrypt sensitive fields ([Host.password],
  /// [SshKey.privateKeyPem]) at rest. Defaults to an empty-passphrase cipher
  /// that passes values through unchanged for backward compatibility; set a
  /// passphrase via [setPassphrase] to enable encryption.
  SecretCipher _cipher = SecretCipher(passphrase: '');

  /// The passphrase the current cipher was built from, or '' when the cipher
  /// is the pass-through default. Used to restore state on a failed
  /// re-encryption.
  String _currentPassphrase = '';

  /// Swaps in a new cipher derived from [passphrase] (and the persisted
  /// salt). Call once at startup (after [init]) if the user has configured a
  /// master passphrase.
  void setPassphrase(String passphrase) {
    _currentPassphrase = passphrase;
    _cipher = SecretCipher(passphrase: passphrase, salt: _salt);
  }

  /// Re-encrypts every stored secret under [newPassphrase], crash-safely.
  ///
  /// 1. Captures all hosts/keys decrypted under the *current* cipher.
  /// 2. Stages the re-encrypted records into the NEXT generation boxes
  ///    (`hosts_g(N+1)`, `ssh_keys_g(N+1)`) — the live boxes are untouched.
  /// 3. Flips the active-generation marker: a single atomic Hive `put`.
  /// 4. Deletes the superseded generation's boxes.
  ///
  /// Crash before step 3: the marker still points at the old generation,
  /// which is complete and consistent under the old key; the partial staging
  /// boxes are cleared at the start of the next run. Crash after step 3: the
  /// new generation was fully staged, so it is complete and consistent. An
  /// in-process exception during staging restores the old cipher before
  /// rethrowing, keeping the in-memory state coherent too.
  ///
  /// Pass '' to store everything as plaintext (used when disabling the
  /// biometric vault). Idempotent under repeated calls with the same
  /// passphrase (it just creates a redundant new generation).
  Future<void> reEncryptAll(String newPassphrase) async {
    final oldPassphrase = _currentPassphrase;
    // Capture everything decrypted under the *current* cipher. Any record
    // that is definitely ciphertext (carries the encryption marker) but fails
    // to decrypt means the passphrase does not match the active generation —
    // re-encrypting now would snapshot ciphertext as if it were plaintext and
    // permanently destroy the secret. Hard-fail instead.
    final hosts = <Host>[];
    final keys = <SshKey>[];
    final corrupt = <String>[];
    for (final raw in _hosts.values) {
      hosts.add(_decryptHost(raw, corrupt.add));
    }
    for (final raw in _keys.values) {
      keys.add(_decryptKey(raw, corrupt.add));
    }
    if (corrupt.isNotEmpty) {
      throw StateError(
        'reEncryptAll aborted: ${corrupt.length} record(s) failed to decrypt '
        'under the current passphrase: ${corrupt.join(', ')}',
      );
    }

    final nextGen = _gen + 1;
    final stagingHosts = await Hive.openBox<Host>('hosts_g$nextGen');
    final stagingKeys = await Hive.openBox<SshKey>('ssh_keys_g$nextGen');
    // Clear any partial staging left by an earlier crashed run.
    await stagingHosts.clear();
    await stagingKeys.clear();

    setPassphrase(newPassphrase);
    try {
      for (final h in hosts) {
        await stagingHosts.put(h.id, _encryptHost(h));
      }
      for (final k in keys) {
        await stagingKeys.put(k.id, _encryptKey(k));
      }
    } catch (e) {
      // Keep the in-memory state consistent with the still-active boxes.
      setPassphrase(oldPassphrase);
      await stagingHosts.deleteFromDisk();
      await stagingKeys.deleteFromDisk();
      rethrow;
    }

    // Atomic generation flip — after this put, the new boxes are live.
    await _meta.put(_genKey, nextGen);
    final oldHosts = _hosts;
    final oldKeys = _keys;
    _gen = nextGen;
    _hosts = stagingHosts;
    _keys = stagingKeys;

    // Best-effort cleanup of the superseded generation.
    try {
      await oldHosts.deleteFromDisk();
      await oldKeys.deleteFromDisk();
    } catch (_) {}
  }

  /// Whether secrets are currently being encrypted (non-empty passphrase).
  bool get isEncrypting => _cipher.encrypt('x') != 'x';

  /// Whether any stored secret field is UNMARKED (no encryption marker), i.e.
  /// definitely-not-encrypted-with-the-current-format. Used at launch to
  /// detect an interrupted enable: `requireBiometric` is on but the records
  /// are still plaintext (crash between persisting the flag and
  /// [reEncryptAll] completing). Reads the raw stored values — a decrypted
  /// view cannot distinguish formerly-encrypted from never-encrypted.
  bool get hasUnmarkedSecrets {
    for (final h in _hosts.values) {
      final p = h.password;
      if (p != null && p.isNotEmpty && !SecretCipher.isEncryptedValue(p)) {
        return true;
      }
    }
    for (final k in _keys.values) {
      if (!SecretCipher.isEncryptedValue(k.privateKeyPem)) return true;
    }
    return false;
  }

  Future<void> init() async {
    _meta = await Hive.openBox(_metaBox);
    final storedGen = _meta.get(_genKey) as int?;

    if (storedGen == null) {
      // Fresh install, or a legacy install predating generations. Adopt the
      // legacy box names as generation 1 when they hold data; otherwise start
      // clean with generation-suffixed names.
      _gen = 1;
      final legacyExists = await Hive.boxExists(_legacyHostsBox);
      final g1Exists = await Hive.boxExists('hosts_g1');
      // Fresh install = no host/key boxes of any generation exist and no salt
      // was ever persisted. Such installs get a random salt. Any install with
      // existing boxes (legacy or g1) is an existing one: it must migrate the
      // legacy property-derived salt so already-encrypted data stays readable.
      final anyBoxes = legacyExists ||
          g1Exists ||
          await Hive.boxExists(_legacyKeysBox) ||
          await Hive.boxExists('ssh_keys_g1');
      await _loadOrMigrateSalt(freshInstall: !anyBoxes);
      if (legacyExists || !g1Exists) {
        await _migrateLegacyBoxes();
      }
    } else {
      _gen = storedGen;
      await _loadOrMigrateSalt(freshInstall: false);
    }

    _hosts = await Hive.openBox<Host>(_hostsBoxName);
    _keys = await Hive.openBox<SshKey>(_keysBoxName);
    _sessions = await Hive.openBox<Session>(_sessionsBox);

    await _deleteStaleGenerations();
  }

  /// Copies the legacy `hosts`/`ssh_keys` boxes into `hosts_g1`/`ssh_keys_g1`
  /// (records as-is — the cipher is unchanged by a copy) and records the
  /// generation marker. Idempotent: a missing legacy box is simply skipped.
  Future<void> _migrateLegacyBoxes() async {
    if (await Hive.boxExists(_legacyHostsBox)) {
      final legacy = await Hive.openBox<Host>(_legacyHostsBox);
      final g1 = await Hive.openBox<Host>('hosts_g1');
      for (final id in legacy.keys) {
        final host = legacy.get(id);
        // Copy: a HiveObject instance cannot live in two boxes at once.
        if (host != null) await g1.put(id, _copyHost(host));
      }
      await g1.flush();
      await legacy.deleteFromDisk();
    }
    if (await Hive.boxExists(_legacyKeysBox)) {
      final legacy = await Hive.openBox<SshKey>(_legacyKeysBox);
      final g1 = await Hive.openBox<SshKey>('ssh_keys_g1');
      for (final id in legacy.keys) {
        final key = legacy.get(id);
        if (key != null) {
          await g1.put(
              id,
              SshKey(
                id: key.id,
                name: key.name,
                privateKeyPem: key.privateKeyPem,
                publicKey: key.publicKey,
              ));
        }
      }
      await g1.flush();
      await legacy.deleteFromDisk();
    }
    await _meta.put(_genKey, 1);
  }

  /// Loads the persisted KDF salt. For installs that predate it (an existing
  /// store of hosts/keys with no persisted salt) the legacy property-derived
  /// salt is computed once and persisted, keeping existing encrypted data
  /// readable (same key) while making future derivations immune to
  /// hostname/core-count changes. A fresh install (no stored salt and no
  /// stored records at all) gets a fresh random salt — never the device-derived
  /// one, whose only purpose is the one-time migration of existing data.
  Future<void> _loadOrMigrateSalt({required bool freshInstall}) async {
    final stored = _meta.get(_saltKey) as String?;
    if (stored != null) {
      try {
        final bytes = base64.decode(stored);
        if (bytes.length == 16) {
          _salt = bytes;
          return;
        }
      } catch (_) {
        // Corrupt entry — fall through and regenerate/migrate below.
      }
    }
    _salt =
        freshInstall ? SecretCipher.randomSalt() : SecretCipher.legacyDeviceSalt();
    await _meta.put(_saltKey, base64.encode(_salt));
  }

  /// Removes generation boxes older than the active one (left behind by a
  /// crash between the flip and cleanup).
  Future<void> _deleteStaleGenerations() async {
    for (var i = 1; i < _gen; i++) {
      for (final name in ['hosts_g$i', 'ssh_keys_g$i']) {
        try {
          if (await Hive.boxExists(name)) {
            await Hive.deleteBoxFromDisk(name);
          }
        } catch (_) {}
      }
    }
  }

  // Host CRUD
  List<Host> getHosts() => _hosts.values.map(_decryptHost).toList();

  Future<void> addHost(Host host) async {
    await _hosts.put(host.id, _encryptHost(host));
  }

  Future<void> updateHost(Host host) async {
    await _hosts.put(host.id, _encryptHost(host));
  }

  Future<void> deleteHost(String id) async {
    await _hosts.delete(id);
  }

  Host? getHost(String id) {
    final raw = _hosts.get(id);
    return raw == null ? null : _decryptHost(raw);
  }

  Host _encryptHost(Host host) {
    if (host.password == null || host.password!.isEmpty) {
      // Return a copy, never the same instance: HiveObject instances cannot
      // live in two boxes at once (relevant during generational staging).
      return _copyHost(host);
    }
    return Host(
      id: host.id,
      name: host.name,
      hostname: host.hostname,
      port: host.port,
      username: host.username,
      authType: host.authType,
      keyId: host.keyId,
      password: _cipher.encrypt(host.password!),
      groupId: host.groupId,
    );
  }

  Host _copyHost(Host host) {
    return Host(
      id: host.id,
      name: host.name,
      hostname: host.hostname,
      port: host.port,
      username: host.username,
      authType: host.authType,
      keyId: host.keyId,
      password: host.password,
      groupId: host.groupId,
    );
  }

  /// Decrypts a stored password. Semantics:
  /// - marker-prefixed ciphertext that decrypts → plaintext;
  /// - marker-prefixed ciphertext that fails → null (unreadable without the
  ///   right key; never surfaced as-if plaintext). If [onCorrupt] is given it
  ///   is called with the record id so [reEncryptAll] can hard-fail;
  /// - unmarked value (plaintext, or legacy pre-marker ciphertext): returned
  ///   as-is when it does not decrypt, matching the historical fallback.
  Host _decryptHost(Host host, [void Function(String id)? onCorrupt]) {
    if (host.password == null || host.password!.isEmpty) return host;
    final stored = host.password!;
    final plain = _cipher.decrypt(stored);
    if (plain == null && SecretCipher.isEncryptedValue(stored)) {
      onCorrupt?.call(host.id);
      return Host(
        id: host.id,
        name: host.name,
        hostname: host.hostname,
        port: host.port,
        username: host.username,
        authType: host.authType,
        keyId: host.keyId,
        password: null,
        groupId: host.groupId,
      );
    }
    return Host(
      id: host.id,
      name: host.name,
      hostname: host.hostname,
      port: host.port,
      username: host.username,
      authType: host.authType,
      keyId: host.keyId,
      password: plain ?? stored,
      groupId: host.groupId,
    );
  }

  // SSH Key CRUD
  List<SshKey> getKeys() => _keys.values.map(_decryptKey).toList();

  Future<void> addKey(SshKey key) async {
    await _keys.put(key.id, _encryptKey(key));
  }

  Future<void> deleteKey(String id) async {
    await _keys.delete(id);
  }

  SshKey? getKey(String id) {
    final raw = _keys.get(id);
    return raw == null ? null : _decryptKey(raw);
  }

  SshKey _encryptKey(SshKey key) {
    // Always a fresh instance (HiveObject single-box constraint).
    return SshKey(
      id: key.id,
      name: key.name,
      privateKeyPem: _cipher.encrypt(key.privateKeyPem),
      publicKey: key.publicKey,
    );
  }

  /// Same semantics as [_decryptHost], except the model's [SshKey.privateKeyPem]
  /// is non-nullable: on failure the stored value is kept (for display only)
  /// and the record is reported to [onCorrupt] so [reEncryptAll] hard-fails.
  SshKey _decryptKey(SshKey key, [void Function(String id)? onCorrupt]) {
    final stored = key.privateKeyPem;
    final plain = _cipher.decrypt(stored);
    if (plain == null && SecretCipher.isEncryptedValue(stored)) {
      onCorrupt?.call(key.id);
    }
    return SshKey(
      id: key.id,
      name: key.name,
      privateKeyPem: plain ?? stored,
      publicKey: key.publicKey,
    );
  }

  // Session CRUD
  List<Session> getSessions() => _sessions.values.toList();

  Future<void> saveSession(Session session) async {
    await _sessions.put(session.id, session);
  }

  Future<void> deleteSession(String id) async {
    await _sessions.delete(id);
  }
}
