import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'vault_service.dart';

/// Production [VaultBackend] backed by `local_auth` (biometric prompt) and
/// `flutter_secure_storage` (platform keychain / keystore).
///
/// Lives in its own file so the plugin imports stay out of [VaultService]'s
/// import graph — unit tests exercise [VaultService] with a fake backend and
/// never touch this device-only code.
class LocalAuthVaultBackend implements VaultBackend {
  LocalAuthVaultBackend({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  })  : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _keyId = 'picshell.master_key';

  @override
  Future<bool> get canCheckBiometrics async {
    // Require both device-level security and an enrolled biometric; without an
    // enrolled print there is nothing to prompt with.
    final supported = await _auth.isDeviceSupported();
    final biometrics = await _auth.canCheckBiometrics;
    return supported && biometrics;
  }

  @override
  Future<bool> authenticate({String reason = ''}) {
    return _auth.authenticate(
      localizedReason: reason.isEmpty ? 'Unlock Picshell credentials' : reason,
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
      ),
    );
  }

  @override
  Future<String?> readKey() => _storage.read(key: _keyId);

  @override
  Future<void> writeKey(String key) => _storage.write(key: _keyId, value: key);

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyId);
}
