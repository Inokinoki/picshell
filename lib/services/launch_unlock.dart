import 'package:hive/hive.dart';

import '../providers/settings_provider.dart';
import 'host_store.dart';
import 'vault_service.dart';

/// Outcome of the launch-time biometric gate (see [performLaunchUnlock]).
class LaunchUnlockResult {
  /// Whether the app must start on the LockScreen (auth required but not yet
  /// granted).
  final bool startLocked;

  /// True when biometrics are required but could not be verified at launch
  /// and the gate had to be bypassed to preserve data availability. The UI
  /// must surface a visible warning to the user in this case
  /// (see `launchSecurityWarningProvider`).
  final bool gateBypassed;

  /// True when secrets left plaintext by an interrupted "enable biometric
  /// encryption" (crash between persisting the flag and the re-encryption
  /// finishing) were detected at launch and the automatic re-completion under
  /// the verified master key FAILED. The UI must warn the user that some
  /// credentials are still stored unencrypted.
  final bool reEncryptionFailed;

  const LaunchUnlockResult({
    required this.startLocked,
    required this.gateBypassed,
    this.reEncryptionFailed = false,
  });
}

/// Performs the launch-time biometric gate. On success the master key is
/// released to the [HostStore], enabling at-rest decryption.
///
/// When biometrics are not required, the app starts unlocked and credentials
/// remain stored as before (backward compatible).
///
/// When biometrics are required but the device reports it cannot prompt (e.g.
/// the user deleted all enrolled prints after enabling), we still ATTEMPT
/// `vault.authenticate()` first: the backend uses `biometricOnly: false`, so
/// the OS passcode/pin fallback may verify the user even without a biometric.
/// Only if that also fails (or throws, which `local_auth` does on unsupported
/// devices) do we release the existing master key WITHOUT verification, so
/// saved credentials still decrypt — otherwise the empty-passphrase cipher
/// would surface their ciphertext as plaintext passwords, and any later
/// "disable" would overwrite the real secrets with that garbage (silent
/// permanent data loss). This bypass is reported via
/// [LaunchUnlockResult.gateBypassed] so the UI can warn the user. Reading the
/// key without a prompt is consistent with the threat model (the gate is
/// app-enforced, not OS-enforced; see [VaultService]) and only happens when no
/// verification was possible at all.
Future<LaunchUnlockResult> performLaunchUnlock({
  required Box settingsBox,
  required HostStore hostStore,
  required VaultService vault,
}) async {
  final requireBiometric = settingsBox
      .get(SettingsNotifier.biometricKey, defaultValue: false) as bool;
  if (!requireBiometric) {
    return const LaunchUnlockResult(startLocked: false, gateBypassed: false);
  }

  if (await vault.canAuthenticate) {
    bool verified;
    try {
      verified = await vault.authenticate();
    } catch (_) {
      // local_auth THROWS on transient failures (LockedOut, NotAvailable,
      // plugin errors). A throw must never escape into main() (the app would
      // fail to launch until the timeout expires) and must NEVER release the
      // key without verification — start locked so the user can retry.
      return const LaunchUnlockResult(startLocked: true, gateBypassed: false);
    }
    if (verified) {
      final key = await vault.getMasterKey();
      hostStore.setPassphrase(key);
      final repairFailed = await _completeInterruptedEnable(hostStore, key);
      return LaunchUnlockResult(
          startLocked: false, gateBypassed: false, reEncryptionFailed: repairFailed);
    }
    // User cancelled or biometrics failed — show the lock screen for retry.
    return const LaunchUnlockResult(startLocked: true, gateBypassed: false);
  }

  // Required but biometrics reportedly unavailable. Defense-in-depth: try
  // anyway — local_auth with biometricOnly:false can still verify via the
  // device passcode/pin.
  try {
    if (await vault.authenticate(
        reason: 'Unlock Picshell credentials (device passcode fallback)')) {
      final key = await vault.getMasterKey();
      hostStore.setPassphrase(key);
      final repairFailed = await _completeInterruptedEnable(hostStore, key);
      return LaunchUnlockResult(
          startLocked: false, gateBypassed: false, reEncryptionFailed: repairFailed);
    }
    // The prompt was shown but the user cancelled or entered a wrong
    // passcode — verification was REFUSED, not impossible. Lock the app; do
    // NOT release the key over a refusal.
    return const LaunchUnlockResult(startLocked: true, gateBypassed: false);
  } catch (_) {
    // No prompt could be shown at all — fall through to the recovery path.
  }

  // Verification impossible. Best-effort recover the existing key so
  // credentials still decrypt (prevents data loss); flag the bypass so the
  // UI warns the user. If no key was ever enrolled there is nothing encrypted
  // to misread, so proceeding unlocked is safe (still flagged, for
  // transparency, so the user learns their gate was not enforced).
  final existing = await vault.releaseKeyForLaunchRecovery();
  if (existing != null) hostStore.setPassphrase(existing);
  return const LaunchUnlockResult(startLocked: false, gateBypassed: true);
}

/// Repairs an interrupted "enable biometric encryption": a crash between
/// persisting `requireBiometric=true` and `reEncryptAll` completing (or a
/// silently-failed rollback of the flag) leaves the flag on with plaintext
/// secrets on disk while the UI claims encrypted. After a VERIFIED launch the
/// master key is available, so finish the re-encryption right here. Safe with
/// [HostStore.reEncryptAll]: already-marked ciphertext decrypts under the
/// released key, unmarked (plaintext) values pass through the cipher as-is,
/// and everything is then written back encrypted.
///
/// Returns true when a repair was needed but failed — the caller must surface
/// a persistent warning so the user knows some secrets are still plaintext.
Future<bool> _completeInterruptedEnable(
    HostStore hostStore, String masterKey) async {
  if (!hostStore.hasUnmarkedSecrets) return false;
  try {
    await hostStore.reEncryptAll(masterKey);
    return false;
  } catch (_) {
    return true;
  }
}
