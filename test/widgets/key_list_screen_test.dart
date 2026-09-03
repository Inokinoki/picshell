import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/services/host_store.dart';
import 'package:picshell/screens/keys/key_list_screen.dart';

/// Fake store whose deleteKey actually removes (the shared one in
/// app_flow_test.dart is a no-op). Only the methods KeyListScreen touches
/// are implemented meaningfully.
class _FakeHostStore implements HostStore {
  final List<SshKey> _keys;
  _FakeHostStore(this._keys);

  @override
  Future<void> init() async {}

  @override
  List<SshKey> getKeys() => List.unmodifiable(_keys);

  @override
  Future<void> addKey(SshKey key) async => _keys.add(key);

  @override
  Future<void> deleteKey(String id) async =>
      _keys.removeWhere((k) => k.id == id);

  @override
  SshKey? getKey(String id) =>
      _keys.where((k) => k.id == id).firstOrNull;

  // Unused by KeyListScreen but required by the interface.
  @override
  List<Host> getHosts() => [];
  @override
  Future<void> addHost(Host host) async {}
  @override
  Future<void> updateHost(Host host) async {}
  @override
  Future<void> deleteHost(String id) async {}
  @override
  Host? getHost(String id) => null;
  @override
  List<Session> getSessions() => [];
  @override
  Future<void> saveSession(Session session) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  bool get isEncrypting => false;

  @override
  bool get hasUnmarkedSecrets => false;
  @override
  void setPassphrase(String passphrase) {}
  @override
  Future<void> reEncryptAll(String newPassphrase) async {}
}

SshKey _key(String id, String name, {String pub = 'ssh-ed25519 AAAA'}) =>
    SshKey(id: id, name: name, privateKeyPem: 'pem', publicKey: pub);

Widget _build(HostStore store) {
  final container = ProviderContainer(overrides: [
    hostStoreProvider.overrideWithValue(store),
  ]);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: KeyListScreen(),
    ),
  );
}

void main() {
  testWidgets('renders empty state when no keys', (tester) async {
    final store = _FakeHostStore([]);
    await tester.pumpWidget(_build(store));
    await tester.pumpAndSettle();

    expect(find.text('No SSH keys imported'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('lists imported keys', (tester) async {
    final store = _FakeHostStore([
      _key('k1', 'work_key'),
      _key('k2', 'personal_key'),
    ]);
    await tester.pumpWidget(_build(store));
    await tester.pumpAndSettle();

    expect(find.text('work_key'), findsOneWidget);
    expect(find.text('personal_key'), findsOneWidget);
  });

  testWidgets('delete button removes key after confirmation', (tester) async {
    final store = _FakeHostStore([_key('k1', 'work_key')]);
    await tester.pumpWidget(_build(store));
    await tester.pumpAndSettle();

    expect(find.text('work_key'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    // Confirmation dialog.
    expect(find.text('Delete Key'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('work_key'), findsNothing);
  });

  testWidgets('cancel in delete dialog keeps the key', (tester) async {
    final store = _FakeHostStore([_key('k1', 'work_key')]);
    await tester.pumpWidget(_build(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('work_key'), findsOneWidget);
  });

  testWidgets('shows public key snippet', (tester) async {
    final store = _FakeHostStore([
      _key('k1', 'work_key', pub: 'ssh-ed25519 AAAAC3NzaC1lZDIx'),
    ]);
    await tester.pumpWidget(_build(store));
    await tester.pumpAndSettle();

    // The truncated public key string should appear in the subtitle.
    expect(find.textContaining('ssh-ed25519 AAAAC3NzaC1lZDIx'), findsOneWidget);
  });
}
