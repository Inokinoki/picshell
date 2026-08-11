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
///   256-bit AES key. The salt is derived from device properties so the same
///   passphrase yields different keys across machines — this raises the bar
///   for offline attacks but is **not** equivalent to a platform Keychain.
/// - Encryption is AES-CBC with PKCS7 padding and a fresh random IV per
///   message. Output is `base64(IV || ciphertext)`.
/// - A determined attacker with disk access can still recover the plaintext
///   if they also obtain the passphrase. For real secret storage, migrate to
///   `flutter_secure_storage` (iOS Keychain / Android Keystore). This layer
///   exists to avoid storing secrets in cleartext, which is strictly better
///   than the previous behaviour.
class SecretCipher {
  static final _random = Random.secure();

  final Uint8List _salt;
  final String _passphrase;
  final int _iterations;

  /// Cached derived key (AES-256 = 32 bytes). Lazily computed once.
  Uint8List? _key;

  SecretCipher({
    required String passphrase,
    Uint8List? salt,
    int iterations = 10000,
  })  : _passphrase = passphrase,
        _salt = salt ?? _deviceSalt(),
        _iterations = iterations;

  /// A salt derived from stable platform attributes. Not secret — its purpose
  /// is only to bind the derived key to this device/installation.
  static Uint8List _deviceSalt() {
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

  /// Encrypts [plain] into a self-describing `base64(IV||ciphertext)`.
  /// An empty passphrase short-circuits and returns [plain] unchanged so the
  /// "no master passphrase" fallback path stays usable.
  String encrypt(String plain) {
    if (_passphrase.isEmpty) return plain;
    final iv = _generateIv();
    final cipher = pc.PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        pc.PaddedBlockCipherParameters(
          pc.ParametersWithIV(pc.KeyParameter(_deriveKey()), iv),
          null,
        ),
      );
    final input = Uint8List.fromList(utf8.encode(plain));
    final output = cipher.process(input);
    // Prepend IV so decrypt() is self-contained.
    final combined = Uint8List(iv.length + output.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, output);
    return base64.encode(combined);
  }

  /// Decrypts a value produced by [encrypt]. Returns null on any failure
  /// (wrong passphrase, corrupted data) so callers can fall back to the raw
  /// stored value rather than crashing.
  String? decrypt(String encoded) {
    if (_passphrase.isEmpty) return encoded;
    try {
      final combined = base64.decode(encoded);
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

  Uint8List _generateIv() {
    final iv = Uint8List(16);
    for (var i = 0; i < iv.length; i++) {
      iv[i] = _random.nextInt(256);
    }
    return iv;
  }
}
