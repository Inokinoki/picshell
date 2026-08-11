import 'dart:io' show Directory, File;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/app/app.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/floating_image_provider.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/providers/session_provider.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/services/known_hosts_store.dart';
import 'package:picshell/services/sftp_service.dart';
import 'package:picshell/services/ssh_service.dart';
import 'package:picshell/widgets/floating_image_widget.dart';

bool _hiveReady = false;

/// Connection target for the throwaway docker sshd. Defaults to localhost for
/// local runs; CI injects 10.0.2.2 (the Android emulator's alias for the host
/// loopback) so the emulator can reach the sshd container published on the
/// runner host. Port defaults to 2222 (Dockerfile.sshd).
const _sshHost = String.fromEnvironment('TEST_SSH_HOST', defaultValue: '127.0.0.1');
const _sshPort = int.fromEnvironment('TEST_SSH_PORT', defaultValue: 2222);
const _sshUser = String.fromEnvironment('TEST_SSH_USER', defaultValue: 'root');
const _sshPass = String.fromEnvironment('TEST_SSH_PASS', defaultValue: 'testpass');

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

  // A KnownHostsStore whose verify() always trusts the presented key, so the
  // first connection to the throwaway docker sshd isn't rejected by TOFU.
  final trustingStore = _AlwaysTrustKnownHostsStore();

  // Register the global modifier-key handler (normally done in main.dart) so
  // the floating-image zoom logic can detect Alt/Option during scroll events.
  ModifierTracker.instance.init();

  return ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(hostStore),
    settingsProvider.overrideWith(
      (ref) => SettingsNotifier(loadFromStorage: false),
    ),
    knownHostsStoreProvider.overrideWithValue(trustingStore),
  ]);
}

class _AlwaysTrustKnownHostsStore implements KnownHostsStore {
  @override
  Future<HostKeyVerification> verify(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async =>
      HostKeyVerification.trusted;

  @override
  Future<void> forget(String host, int port) async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> trust(
    String host,
    int port,
    String keyType,
    Uint8List fingerprintBytes,
  ) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SSH connection', () {
    testWidgets('connects to a real sshd and renders the terminal',
        (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Drive a connection to the docker sshd reachable from the Android
      // emulator via the 10.0.2.2 host-loopback alias.
      final host = Host(
        id: 'test-sshd',
        name: 'docker-sshd',
        hostname: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authType: AuthType.password,
        password: _sshPass,
      );
      final config = SshConnectionConfig(
        host: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authMethod: SshAuthMethod.password,
        password: _sshPass,
      );

      await container
          .read(sessionListProvider.notifier)
          .openSession(host, config);

      // Poll for the session to come up; SSH handshake + auth takes a few
      // seconds on the emulator.
      bool connected = false;
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        final sessions = container.read(sessionListProvider);
        if (sessions.isNotEmpty && sessions.first.connected) {
          connected = true;
          break;
        }
      }

      expect(connected, isTrue,
          reason: 'SSH session should reach connected state within 60s');

      container.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Inline image (iTerm2 OSC 1337)', () {
    testWidgets('remote OSC 1337 output creates a floating image',
        (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final host = Host(
        id: 'test-sshd',
        name: 'docker-sshd',
        hostname: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authType: AuthType.password,
        password: _sshPass,
      );
      final config = SshConnectionConfig(
        host: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authMethod: SshAuthMethod.password,
        password: _sshPass,
      );
      await container
          .read(sessionListProvider.notifier)
          .openSession(host, config);

      // Wait for the session to be connected and the shell to be ready.
      bool connected = false;
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        final sessions = container.read(sessionListProvider);
        if (sessions.isNotEmpty && sessions.first.connected) {
          connected = true;
          break;
        }
      }
      expect(connected, isTrue, reason: 'session should connect');

      final terminal = container.read(sessionListProvider).first.terminal;

      // Give the remote shell a moment to finish its MOTD / prompt, then send
      // the command that emits the OSC 1337 image sequence.
      await tester.pump(const Duration(seconds: 2));
      terminal.textInput('bash /tmp/send.sh\n');

      // Poll for the floating image to appear (SSH round-trip + decode).
      bool imageAppeared = false;
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (container.read(floatingImagesProvider).isNotEmpty) {
          imageAppeared = true;
          break;
        }
      }
      expect(imageAppeared, isTrue,
          reason: 'OSC 1337 output should produce a floating image');

      // Confirm the protocol request params were honoured.
      final img = container.read(floatingImagesProvider).first;
      expect(img.requestedWidth, 80);
      expect(img.requestedHeight, 40);
      expect(img.name, 't.png');

      container.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));

    // NOTE: this end-to-end zoom test is skipped in CI because simulating
    // "Alt held + pointer scroll" via the integration-test live binding does
    // not reliably update HardwareKeyboard state / route the wheel to the
    // overlay's Listener the way a real user interaction does. The zoom logic
    // itself (modifier detection, scale clamp, pinch, computeBaseDisplaySize)
    // is fully covered by the widget tests in
    // test/widgets/floating_image_overlay_test.dart. Keep this test for manual
    // on-device verification.
    testWidgets('Option/Alt + wheel zooms the floating image',
        skip: true, // live binding can't reliably inject Alt+wheel; see widget tests
        (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final host = Host(
        id: 'test-sshd',
        name: 'docker-sshd',
        hostname: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authType: AuthType.password,
        password: _sshPass,
      );
      final config = SshConnectionConfig(
        host: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authMethod: SshAuthMethod.password,
        password: _sshPass,
      );
      await container
          .read(sessionListProvider.notifier)
          .openSession(host, config);

      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (container
            .read(sessionListProvider)
            .isNotEmpty && container.read(sessionListProvider).first.connected) {
          break;
        }
      }

      final terminal = container.read(sessionListProvider).first.terminal;
      await tester.pump(const Duration(seconds: 2));
      terminal.textInput('bash /tmp/send.sh\n');

      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (container.read(floatingImagesProvider).isNotEmpty) break;
      }
      expect(container.read(floatingImagesProvider), isNotEmpty,
          reason: 'need an image to test zoom on');

      final scaleBefore =
          container.read(floatingImagesProvider).first.scale;
      final imgId = container.read(floatingImagesProvider).first.id;

      // Hold Option/Alt (the zoom modifier that survives macOS Cmd interception),
      // then dispatch wheel events. The Listener on the floating widget reads
      // HardwareKeyboard state + the ModifierTracker singleton.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      // Find the floating widget and scroll on its centre.
      final finder = find.byKey(ValueKey(imgId));
      Offset centre;
      if (finder.evaluate().isNotEmpty) {
        centre = tester.getCenter(finder);
      } else {
        // Fallback: any FloatingImageWidget on screen.
        centre = tester.getCenter(find.byType(FloatingImageWidget));
      }
      for (int i = 0; i < 5; i++) {
        GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
          position: centre,
          scrollDelta: const Offset(0, -100), // up = zoom in
        ));
        await tester.pump();
      }

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      final scaleAfter = container
          .read(floatingImagesProvider)
          .firstWhere((i) => i.id == imgId)
          .scale;
      expect(scaleAfter, greaterThan(scaleBefore),
          reason: 'Alt+wheel up should zoom in');

      container.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('SFTP', () {
    // Opens a session and returns the connected SftpService built on it.
    // Shared by the list/download smoke tests so each doesn't re-handshake.
    Future<SftpService> _connectSession(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      final host = Host(
        id: 'test-sshd',
        name: 'docker-sshd',
        hostname: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authType: AuthType.password,
        password: _sshPass,
      );
      final config = SshConnectionConfig(
        host: _sshHost,
        port: _sshPort,
        username: _sshUser,
        authMethod: SshAuthMethod.password,
        password: _sshPass,
      );
      await container.read(sessionListProvider.notifier).openSession(host, config);

      // Poll until connected (handshake + auth takes a few seconds).
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        final sessions = container.read(sessionListProvider);
        if (sessions.isNotEmpty && sessions.first.connected) break;
      }
      final sessions = container.read(sessionListProvider);
      expect(sessions.isNotEmpty && sessions.first.connected, isTrue,
          reason: 'SFTP smoke needs a connected session');
      return SftpService(sessions.first.sshService);
    }

    testWidgets('listdir / returns the marker file', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final sftp = await _connectSession(tester, container);
      final entries = await sftp.listdir('/');

      expect(entries, isNotEmpty, reason: 'root listing should not be empty');
      expect(
        entries.any((e) => e.name == 'picshell_sftp_marker.txt'),
        isTrue,
        reason: 'marker file from Dockerfile.sshd should be listed',
      );

      await sftp.close();
      container.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('download retrieves the marker file content', (tester) async {
      final container = await _initApp();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PicshellApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final sftp = await _connectSession(tester, container);
      final tmp = await Directory.systemTemp.createTemp('picshell_sftp_');
      final localPath = '${tmp.path}/marker.txt';
      await sftp.download('/picshell_sftp_marker.txt', localPath);

      final content = await File(localPath).readAsString();
      expect(content.trim(), 'picshell-sftp-smoke');

      await sftp.close();
      await tmp.delete(recursive: true);
      container.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
