import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/forward_rule.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/vault_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/launch_unlock.dart';
import 'package:picshell/services/local_auth_vault_backend.dart';
import 'package:picshell/services/vault_service.dart';
import 'package:picshell/widgets/floating_image_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HostAdapter());
  Hive.registerAdapter(AuthTypeAdapter());
  Hive.registerAdapter(ForwardTypeAdapter());
  Hive.registerAdapter(ForwardRuleAdapter());
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
  final unlock = await performLaunchUnlock(
    settingsBox: await Hive.openBox('settings'),
    hostStore: hostStore,
    vault: vault,
  );

  runApp(
    ProviderScope(
      overrides: [
        hostStoreProvider.overrideWithValue(hostStore),
        knownHostsStoreProvider.overrideWithValue(knownHostsStore),
        vaultServiceProvider.overrideWithValue(vault),
        appLockProvider.overrideWith(
          (ref) => AppLockNotifier(vault, hostStore,
              initiallyLocked: unlock.startLocked),
        ),
        launchSecurityWarningProvider.overrideWithValue(
            unlock.gateBypassed || unlock.reEncryptionFailed
                ? LaunchGateStatus(
                    gateBypassed: unlock.gateBypassed,
                    reEncryptionFailed: unlock.reEncryptionFailed,
                  )
                : null),
      ],
      child: const PicshellApp(),
    ),
  );
}
