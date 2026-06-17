import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/widgets/floating_image_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HostAdapter());
  Hive.registerAdapter(AuthTypeAdapter());
  Hive.registerAdapter(SshKeyAdapter());
  Hive.registerAdapter(SessionAdapter());

  // Initialise global modifier-key tracking (Cmd/Ctrl + scroll → zoom).
  ModifierTracker.instance.init();

  final hostStore = HostStore();
  await hostStore.init();

  runApp(
    ProviderScope(
      overrides: [hostStoreProvider.overrideWithValue(hostStore)],
      child: const PicshellApp(),
    ),
  );
}
