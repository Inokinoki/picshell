import 'package:hive/hive.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/session.dart';
import 'secret_cipher.dart';

class HostStore {
  static const _hostsBox = 'hosts';
  static const _keysBox = 'ssh_keys';
  static const _sessionsBox = 'sessions';

  late Box<Host> _hosts;
  late Box<SshKey> _keys;
  late Box<Session> _sessions;

  /// Cipher used to encrypt sensitive fields ([Host.password],
  /// [SshKey.privateKeyPem]) at rest. Defaults to an empty-passphrase cipher
  /// that passes values through unchanged for backward compatibility; set a
  /// passphrase via [setPassphrase] to enable encryption.
  SecretCipher _cipher = SecretCipher(passphrase: '');

  /// Swaps in a new cipher derived from [passphrase]. Call once at startup
  /// (after [init]) if the user has configured a master passphrase.
  void setPassphrase(String passphrase) {
    _cipher = SecretCipher(passphrase: passphrase);
  }

  /// Whether secrets are currently being encrypted (non-empty passphrase).
  bool get isEncrypting => _cipher.encrypt('x') != 'x';

  Future<void> init() async {
    _hosts = await Hive.openBox<Host>(_hostsBox);
    _keys = await Hive.openBox<SshKey>(_keysBox);
    _sessions = await Hive.openBox<Session>(_sessionsBox);
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
    if (host.password == null || host.password!.isEmpty) return host;
    return host.copyWith(password: _cipher.encrypt(host.password!));
  }

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
