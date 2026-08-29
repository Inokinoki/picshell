import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/providers/host_provider.dart';
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
  await _enableSecretEncryption(hostStore);

  final knownHostsStore = KnownHostsStore();
  await knownHostsStore.init();

  runApp(
    ProviderScope(
      overrides: [
        hostStoreProvider.overrideWithValue(hostStore),
        knownHostsStoreProvider.overrideWithValue(knownHostsStore),
      ],
      child: const PicshellApp(),
    ),
  );
}

/// Gives the store a master passphrase so secrets are actually encrypted at
/// rest. The passphrase is a random 256-bit key generated on first launch and
/// kept in the platform secure store (Windows DPAPI / Keychain / Keystore) —
/// without this the SecretCipher layer passes everything through in
/// cleartext.
Future<void> _enableSecretEncryption(HostStore hostStore) async {
  const storage = FlutterSecureStorage();
  const keyName = 'picshell.master_key';
  try {
    var key = await storage.read(key: keyName);
    if (key == null || key.isEmpty) {
      final bytes = Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      key = base64.encode(bytes);
      await storage.write(key: keyName, value: key);
    }
    hostStore.setPassphrase(key);
  } catch (e) {
    // No secure storage (or it failed): fall back to cleartext rather than
    // losing access to saved credentials entirely.
    debugPrint('secure storage unavailable, secrets stay unencrypted: $e');
  }
}
