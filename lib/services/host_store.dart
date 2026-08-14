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

  /// Swaps in a new cipher derived from [passphrase]. Call once at startup
  /// (after [init]) if the user has configured a master passphrase.
  void setPassphrase(String passphrase) {
    _currentPassphrase = passphrase;
    _cipher = SecretCipher(passphrase: passphrase);
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
    final hosts = getHosts(); // decrypted under the current cipher
    final keys = getKeys();

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
      if (legacyExists || !g1Exists) {
        await _migrateLegacyBoxes();
      }
    } else {
      _gen = storedGen;
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
    // copyWith always allocates a fresh instance: HiveObject instances cannot
    // live in two boxes at once (relevant during generational staging), and
    // it preserves fields this class doesn't know about (proxyHostId,
    // forwards).
    if (host.password == null || host.password!.isEmpty) {
      return host.copyWith();
    }
    return host.copyWith(password: _cipher.encrypt(host.password!));
  }

  Host _copyHost(Host host) => host.copyWith();

  Host _decryptHost(Host host) {
    if (host.password == null || host.password!.isEmpty) return host;
    final plain = _cipher.decrypt(host.password!);
    // If decryption fails (e.g. passphrase mismatch, or the value was never
    // encrypted), fall back to the stored value rather than losing the host.
    return host.copyWith(password: plain ?? host.password);
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

  SshKey _decryptKey(SshKey key) {
    final plain = _cipher.decrypt(key.privateKeyPem);
    return SshKey(
      id: key.id,
      name: key.name,
      privateKeyPem: plain ?? key.privateKeyPem,
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
