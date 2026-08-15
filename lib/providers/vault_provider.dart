import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/host_store.dart';
import '../services/vault_service.dart';
import 'host_provider.dart';

/// The credential vault. Overridden in `main()` with a [VaultService] backed
/// by [LocalAuthVaultBackend] (or a fake in tests).
final vaultServiceProvider = Provider<VaultService>((ref) {
  throw UnimplementedError('vaultServiceProvider must be overridden in main()');
});

/// Non-null when the launch biometric gate could not be enforced (biometrics
/// required but unavailable, and even the device-passcode fallback failed) and
/// the master key was released without verification to preserve data
/// availability. Overridden in `main()` with the warning message; the app
/// shell shows it as a visible banner (see `LaunchGateBypassedBanner`).
final launchSecurityWarningProvider = Provider<String?>((ref) => null);

/// Whether the app is currently locked behind the biometric gate. True means
/// the LockScreen is shown and credentials have not yet been released to the
/// [HostStore]. The initial value is computed in `main()` based on the
/// `requireBiometric` setting and device capability, then supplied via an
/// override.
final appLockProvider =
    StateNotifierProvider<AppLockNotifier, bool>((ref) {
  return AppLockNotifier(
    ref.watch(vaultServiceProvider),
    ref.watch(hostStoreProvider),
  );
});

/// Drives the locked/unlocked state of the app. [unlock] runs the biometric
/// prompt and, on success, releases the device-bound master key to the
/// [HostStore] (enabling at-rest decryption of saved credentials).
class AppLockNotifier extends StateNotifier<bool> {
  final VaultService _vault;
  final HostStore _hostStore;

  AppLockNotifier(
    this._vault,
    this._hostStore, {
    bool initiallyLocked = false,
  }) : super(initiallyLocked);

  /// True while the gate is showing.
  bool get isLocked => state;

  /// Prompts biometrics; on success releases the master key and unlocks.
  /// Returns false (and stays locked) if the user cancels or fails.
  Future<bool> unlock() async {
    final ok = await _vault.authenticate();
    if (!ok) return false;
    final key = await _vault.getMasterKey();
    _hostStore.setPassphrase(key);
    state = false;
    return true;
  }

  /// Re-shows the lock screen. Note: the in-memory master key is not cleared
  /// in v1, so this is a UI gate rather than a full re-encryption.
  void lock() => state = true;
}
