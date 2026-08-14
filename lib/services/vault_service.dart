import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Platform backend for the credential vault: a biometric prompt plus a
/// secret store backed by the platform keychain/keystore.
///
/// Abstracted as an interface so [VaultService]'s key-management logic can be
/// unit-tested with a fake backend, independent of the device-only
/// `local_auth` / `flutter_secure_storage` plugins (see [LocalAuthVaultBackend]
/// for the production implementation).
abstract class VaultBackend {
  /// Whether this device can prompt the user biometrically.
  Future<bool> get canCheckBiometrics;

  /// Shows the system biometric prompt. Resolves true on success, false if the
  /// user cancels or biometrics don't match.
  Future<bool> authenticate({String reason});

  /// Reads the persisted master key, or null if never written.
  Future<String?> readKey();

  /// Persists [key] to the platform secret store.
  Future<void> writeKey(String key);

  /// Removes the persisted master key (used when the user disables vault).
  Future<void> deleteKey();
}

/// Manages the device-bound master passphrase that encrypts saved credentials
/// at rest (via [HostStore.setPassphrase]). The passphrase is a random 32-byte
/// value generated on first use and stored in the platform secret store.
///
/// Model: **device key + biometric, no user master password**. The user never
/// sees or types the passphrase, so it cannot be forgotten. The trade-off is
/// that wiping the app (and thus the keystore entry) makes already-encrypted
/// credentials unrecoverable — the connection metadata survives, passwords do
/// not.
///
/// **Threat-model caveat (v1):** the biometric gate is enforced in Dart
/// (the app only calls [setPassphrase] after a prompt), NOT by the OS keychain.
/// The master key itself is readable from the platform secret store without a
/// biometric (see [existingMasterKey]). The key IS OS-bound though: on Apple
/// platforms it uses kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly (no
/// backup/device migration, requires an unlocked passcode-set device) and on
/// Android EncryptedSharedPreferences (Keystore-wrapped). This defeats raw
/// disk extraction, backups, and the casual unlocked-phone snoop; an attacker
/// with disk access *and* the keystore entry (rooted/jailbroken device, or
/// forensic extraction while unlocked) can still recover credentials without
/// a biometric. True biometric-bound key release would need
/// SecAccessControl(biometryAny) / CryptoObject, which local_auth 2.x does not
/// expose from Dart — tracked as a v2 follow-up.
/// credentials unrecoverable — the connection metadata survives, passwords do
/// not.
class VaultService {
  final VaultBackend _backend;
  VaultService(this._backend);

  Future<bool> get canAuthenticate => _backend.canCheckBiometrics;

  /// Whether a master key has already been enrolled on this device.
  Future<bool> get isEnrolled async => (await _backend.readKey()) != null;

  /// Returns the enrolled master key without generating one, or null if none
  /// is stored. Used for best-effort recovery when biometrics are configured
  /// but temporarily unavailable (so credentials still decrypt instead of
  /// being surfaced as ciphertext).
  Future<String?> get existingMasterKey => _backend.readKey();

  /// Returns the master key, generating and persisting a fresh random one on
  /// first call. Idempotent: once enrolled, the same key is returned forever.
  Future<String> getMasterKey() async {
    final existing = await _backend.readKey();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generatePassphrase();
    await _backend.writeKey(generated);
    return generated;
  }

  /// Prompts the user biometrically. Returns true on success.
  Future<bool> authenticate({String reason = 'Unlock Picshell credentials'}) =>
      _backend.authenticate(reason: reason);

  /// Removes the master key from the device. Already-encrypted credentials
  /// become unreadable until a new key is enrolled.
  Future<void> unenroll() => _backend.deleteKey();

  /// Generates a 32-byte cryptographically-random passphrase, base64url-encoded.
  static String _generatePassphrase() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Url.encode(bytes);
  }
}
