import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/local_auth_vault_backend.dart';
import 'package:picshell/services/vault_service.dart';
import 'package:picshell/widgets/floating_image_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HostAdapter());
  Hive.registerAdapter(AuthTypeAdapter());
  Hive.registerAdapter(SshKeyAdapter());
  Hive.registerAdapter(SessionAdapter());
  Hive.registerAdapter(KnownHostAdapter());

  // Initialise global modifier-key tracking (Option/Alt + scroll → zoom;
  // Cmd+scroll is swallowed by macOS for Mission Control / Spaces).
  ModifierTracker.enableDebugLogging = kDebugMode;
  ModifierTracker.instance.init();

  final hostStore = HostStore();
  await hostStore.init();

  final knownHostsStore = KnownHostsStore();
  await knownHostsStore.init();

  // Credential vault: device-bound master key gated by biometrics.
  final vault = VaultService(LocalAuthVaultBackend());
  final startLocked = await _initialUnlock(hostStore, vault);

  runApp(
    ProviderScope(
      overrides: [
        hostStoreProvider.overrideWithValue(hostStore),
        knownHostsStoreProvider.overrideWithValue(knownHostsStore),
        vaultServiceProvider.overrideWithValue(vault),
        appLockProvider.overrideWith(
          (ref) => AppLockNotifier(vault, hostStore, initiallyLocked: startLocked),
        ),
      ],
      child: const PicshellApp(),
    ),
  );
}

/// Performs the launch-time biometric gate. Returns true if the app should
/// start locked (i.e. the LockScreen must show because biometric auth did not
/// succeed). When biometrics succeed the master key is released to the
/// [HostStore], enabling at-rest decryption.
///
/// When biometrics are not required, the app starts unlocked and credentials
/// remain stored as before (backward compatible).
///
/// If biometrics are required but the device can no longer prompt (e.g. the
/// user deleted all enrolled prints after enabling), we cannot biometrically
/// gate — but we MUST still release the existing master key to [HostStore] so
/// saved credentials decrypt correctly. Otherwise the empty-passphrase cipher
/// would surface their ciphertext as plaintext passwords, and any later
/// "disable" would overwrite the real secrets with that garbage (silent
/// permanent data loss). Reading the key without a prompt is consistent with
/// the threat model (the gate is app-enforced, not OS-enforced; see
/// VaultService) and only happens when there is no biometric to prompt with.
Future<bool> _initialUnlock(HostStore hostStore, VaultService vault) async {
  final settingsBox = await Hive.openBox('settings');
  final requireBiometric =
      settingsBox.get(SettingsNotifier.biometricKey, defaultValue: false) as bool;
  if (!requireBiometric) return false;

  if (await vault.canAuthenticate) {
    if (await vault.authenticate()) {
      hostStore.setPassphrase(await vault.getMasterKey());
      return false; // unlocked
    }
    // User cancelled or biometrics failed — show the lock screen for retry.
    return true;
  }

  // Required but biometrics unavailable now. Best-effort recover the existing
  // key so credentials still decrypt (prevents data loss). If no key was ever
  // enrolled (shouldn't happen with require=true) there is nothing encrypted
  // to misread, so proceeding unlocked is safe.
  final existing = await vault.existingMasterKey;
  if (existing != null) hostStore.setPassphrase(existing);
  return false;
}
