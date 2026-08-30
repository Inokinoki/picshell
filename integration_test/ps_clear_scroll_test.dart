import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/models/known_host.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/ssh_service.dart';

/// End-to-end regression for the Win32-OpenSSH (PowerShell) flow:
/// connect with the saved host credentials, switch shells, run `clear`, and
/// verify the terminal view stays pinned to the live screen.
bool _hiveReady = false;

Future<ProviderContainer> _initApp() async {
  if (!_hiveReady) {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HostAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AuthTypeAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SshKeyAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SessionAdapter());
    _hiveReady = true;
  }
  final hostStore = HostStore();
  await hostStore.init();
  // Enable at-rest encryption exactly like main() does.
  const storage = FlutterSecureStorage();
  const keyName = 'picshell.master_key';
  var key = await storage.read(key: keyName);
  if (key == null || key.isEmpty) {
    key = base64.encode(Uint8List.fromList(
      List.generate(32, (_) => DateTime.now().millisecondsSinceEpoch & 0xFF),
    ));
    await storage.write(key: keyName, value: key);
  }
  hostStore.setPassphrase(key);

  final trustingStore = _AlwaysTrustKnownHosts();
  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(hostStore),
    knownHostsStoreProvider.overrideWithValue(trustingStore),
    settingsProvider.overrideWith((ref) => SettingsNotifier(loadFromStorage: false)),
  ]);
}

class _AlwaysTrustKnownHosts implements KnownHostsStore {
  @override
  Future<void> init() async {}

  @override
  Future<HostKeyVerification> verify(String host, int port,
      String keyType, Uint8List fingerprintBytes) async {
    return HostKeyVerification.trusted;
  }

  @override
  Future<void> trust(String host, int port, String keyType,
      Uint8List fingerprintBytes) async {}

  @override
  Future<void> forget(String host, int port) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('powershell + clear keeps the view pinned on a real sshd',
      (tester) async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(HostAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(AuthTypeAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(SshKeyAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SessionAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(KnownHostAdapter());
    if (!Hive.isBoxOpen('hosts')) {
      await Hive.openBox<Host>('hosts');
    }
    final hosts = Hive.box<Host>('hosts');
    if (hosts.isEmpty) {
      // No saved host on this machine — nothing to verify.
      return;
    }
    final host = hosts.values.first;

    final container = await _initApp();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const PicshellApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final password =
        container.read(hostStoreProvider)!.getHost(host.id)?.password;
    final config = SshConnectionConfig(
      host: host.hostname,
      port: host.port,
      username: host.username,
      authMethod: SshAuthMethod.password,
      password: password,
    );

    await container
        .read(sessionListProvider.notifier)
        .openSession(host, config);

    bool connected = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      final sessions = container.read(sessionListProvider);
      if (sessions.isNotEmpty && sessions.first.connected) {
        connected = true;
        break;
      }
    }
    expect(connected, isTrue, reason: 'ssh session should connect');

    final terminal = container.read(sessionListProvider).first.terminal;

    // Switch to PowerShell.
    terminal.textInput('powershell\r');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    // Run clear.
    terminal.textInput('clear\r');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    // After clear the live cursor must be back near the top of the screen.
    expect(terminal.buffer.cursorY, lessThan(3),
        reason: 'cursorY=${terminal.buffer.cursorY}');

    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
