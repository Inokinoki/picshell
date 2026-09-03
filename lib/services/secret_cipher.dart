import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// Encrypts short secrets (SSH passwords, private-key PEMs) for at-rest
/// storage in Hive.
///
/// Design (and honest limitations):
/// - A passphrase is stretched via PBKDF2-HMAC-SHA256 (10k iterations) into a
///   256-bit AES key. The salt SHOULD be supplied by the caller as a random
///   16-byte value generated once and persisted next to the data (see
///   [HostStore], which keeps it in the `vault_meta` Hive box). When no salt
///   is supplied a random one is generated — never derive a salt from device
///   properties: they change (hostname, core count) and would permanently
///   destroy every stored secret. [legacyDeviceSalt] exists ONLY so existing
///   installs can migrate their old property-derived salt to stable storage.
/// - Encryption is AES-GCM (format `enc.v2.<base64(nonce||ciphertext||tag)>`,
///   12-byte nonce). Values written by older versions used AES-CBC/PKCS7 with
///   a 16-byte IV and no marker prefix (`base64(IV||ciphertext)`, later
///   `enc.v1.`-prefixed); [decrypt] still reads both, selected by the
///   marker/version, so existing ciphertexts remain readable.
/// - A determined attacker with disk access can still recover the plaintext
///   if they also obtain the passphrase. For real secret storage, migrate to
///   `flutter_secure_storage` (iOS Keychain / Android Keystore). This layer
///   exists to avoid storing secrets in cleartext, which is strictly better
///   than the previous behaviour.
class SecretCipher {
  static final _random = Random.secure();

  /// Marker prefix for version-1 records (AES-CBC/PKCS7, 16-byte IV).
  static const v1Marker = 'enc.v1.';

  /// Marker prefix for version-2 records (AES-GCM, 12-byte nonce + tag).
  static const v2Marker = 'enc.v2.';

  final Uint8List _salt;
  late final String _passphrase;
  late final int _iterations;

  /// Cached derived key (AES-256 = 32 bytes). Lazily computed once.
  Uint8List? _key;

  SecretCipher({
    required String passphrase,
    Uint8List? salt,
    int iterations = 10000,
  })  : _salt = (salt != null && salt.isNotEmpty)
            ? salt
            : _randomSalt(16) {
    _passphrase = passphrase;
    _iterations = iterations;
  }

  /// The salt this cipher derives its key from.
  Uint8List get salt => _salt;

  /// Whether [value] was written by [encrypt] (i.e. it is definitely
  /// ciphertext, not a plaintext that failed to decrypt). Values without a
  /// marker are either plaintext or ciphertext from a pre-marker version —
  /// callers must treat them as "unknown".
  static bool isEncryptedValue(String value) =>
      value.startsWith(v1Marker) || value.startsWith(v2Marker);

  /// Generates a random [length]-byte salt.
  static Uint8List randomSalt([int length = 16]) => _randomSalt(length);

  static Uint8List _randomSalt(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// The property-derived salt used by versions before the salt was persisted.
  /// Kept ONLY for one-time migration: [HostStore] calls this when the
  /// `vault_meta` box has no stored salt, and immediately persists the result
  /// so the key stops depending on mutable device properties (hostname,
  /// processor count). Not secret — its purpose is only to bind the derived
  /// key to this device/installation.
  static Uint8List legacyDeviceSalt() {
    String ident;
    try {
      ident = '${Platform.operatingSystem}:${Platform.localHostname}:'
          '${Platform.numberOfProcessors}';
    } catch (_) {
      // Some platforms (web) throw on Platform access; fall back to a constant
      // so the cipher still functions, just without device binding.
      ident = 'picshell:fallback';
    }
    final bytes = utf8.encode(ident);
    final out = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      out[i % out.length] ^= bytes[i];
    }
    return out;
  }

  Uint8List _deriveKey() {
    var k = _key;
    if (k != null) return k;
    final derivator = pc.PBKDF2KeyDerivator(
      pc.HMac(pc.SHA256Digest(), 64),
    )
      ..init(pc.Pbkdf2Parameters(
        _salt,
        _iterations,
        32, // 256-bit key
      ));
    k = derivator.process(Uint8List.fromList(utf8.encode(_passphrase)));
    _key = k;
    return k;
  }

  /// Encrypts [plain] into a self-describing `$v2Marker + base64(nonce||
  /// ciphertext||tag)`. An empty passphrase short-circuits and returns [plain]
  /// unchanged so the "no master passphrase" fallback path stays usable.
  String encrypt(String plain) {
    if (_passphrase.isEmpty) return plain;
    final nonce = _randomBytes(12);
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(_deriveKey()), nonce));
    final input = Uint8List.fromList(utf8.encode(plain));
    final output = cipher.process(input); // ciphertext || 16-byte tag
    final combined = Uint8List(nonce.length + output.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, combined.length, output);
    return v2Marker + base64.encode(combined);
  }

  /// Decrypts a value produced by [encrypt] (or an older version). Returns
  /// null on any failure (wrong passphrase, corrupted data, unknown marker
  /// version) so callers can decide how to treat the stored value.
  ///
  /// Empty passphrase: returns [encoded] unchanged when it carries no
  /// encryption marker (it was stored as plaintext); returns null when it is
  /// marker-prefixed ciphertext (it cannot be read without the key).
  String? decrypt(String encoded) {
    if (_passphrase.isEmpty) {
      return isEncryptedValue(encoded) ? null : encoded;
    }
    if (encoded.startsWith(v2Marker)) {
      return _decryptGcm(encoded.substring(v2Marker.length));
    }
    if (encoded.startsWith(v1Marker)) {
      return _decryptCbc(encoded.substring(v1Marker.length));
    }
    // Pre-marker legacy ciphertext: raw base64(IV||ciphertext), AES-CBC.
    // Distinguished from "never encrypted" only by decrypting successfully —
    // callers fall back to the raw value when this returns null.
    return _decryptCbc(encoded);
  }

  String? _decryptGcm(String payload) {
    try {
      final combined = base64.decode(payload);
      const nonceLen = 12;
      if (combined.length < nonceLen + 16) return null;
      final nonce = Uint8List.fromList(combined.sublist(0, nonceLen));
      final ct = Uint8List.fromList(combined.sublist(nonceLen));
      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(
            false, pc.ParametersWithIV(pc.KeyParameter(_deriveKey()), nonce));
      final plain = cipher.process(ct); // verifies the tag, throws on mismatch
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  String? _decryptCbc(String payload) {
    try {
      final combined = base64.decode(payload);
      const ivLen = 16;
      if (combined.length < ivLen) return null;
      final iv = Uint8List.fromList(combined.sublist(0, ivLen));
      final ct = Uint8List.fromList(combined.sublist(ivLen));
      final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7')
        ..init(
          false,
          pc.PaddedBlockCipherParameters(
            pc.ParametersWithIV(pc.KeyParameter(_deriveKey()), iv),
            null,
          ),
        );
      final plain = cipher.process(ct);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < out.length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
