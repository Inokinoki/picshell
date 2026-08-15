import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/models/session.dart';
import 'package:picshell/models/ssh_key.dart';
import 'package:picshell/providers/host_provider.dart';
import 'package:picshell/screens/hosts/host_edit_screen.dart';
import 'package:picshell/services/host_store.dart';

class _FakeHostStore implements HostStore {
  final List<Host> hosts;

  _FakeHostStore(this.hosts);

  @override
  Future<void> init() async {}

  @override
  List<Host> getHosts() => hosts;

  @override
  Future<void> addHost(Host host) async => hosts.add(host);

  @override
  Future<void> updateHost(Host host) async {
    final i = hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) hosts[i] = host;
  }

  @override
  Future<void> deleteHost(String id) async =>
      hosts.removeWhere((h) => h.id == id);

  @override
  Host? getHost(String id) =>
      hosts.where((h) => h.id == id).firstOrNull;

  @override
  List<SshKey> getKeys() => [];

  @override
  Future<void> addKey(SshKey key) async {}

  @override
  Future<void> deleteKey(String id) async {}

  @override
  SshKey? getKey(String id) => null;

  @override
  List<Session> getSessions() => [];

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  bool get isEncrypting => false;

  @override
  void setPassphrase(String passphrase) {}
}

Host _host(String id, {String? proxyHostId}) => Host(
      id: id,
      name: id,
      hostname: '$id.example',
      port: 22,
      username: 'user',
      authType: AuthType.password,
      proxyHostId: proxyHostId,
    );

void main() {
  // A routes via B; B itself gained its own jump host C. Editing A must not
  // build a DropdownButton whose value (B) is missing from its items — that
  // trips Flutter's "exactly one item with value" assertion.
  testWidgets('edit screen renders when saved jump host is filtered out',
      (tester) async {
    final store = _FakeHostStore([
      _host('a', proxyHostId: 'b'),
      _host('b', proxyHostId: 'c'),
      _host('c'),
    ]);
    final container = ProviderContainer(
      overrides: [hostStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostEditScreen(hostId: 'a')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connect via (ProxyJump, ssh -J)'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    // Renders without the DropdownButton value/items assertion firing, and
    // falls back to no selection (direct).
    expect(find.text('Connect via (ProxyJump, ssh -J)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    container.dispose();
  });

  // A host that is itself used as someone's jump host (C is used by B) must
  // not be offered a jump host of its own.
  testWidgets('host used as jump host renders with direct connection',
      (tester) async {
    final store = _FakeHostStore([
      _host('b', proxyHostId: 'c'),
      _host('c'),
    ]);
    final container = ProviderContainer(
      overrides: [hostStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostEditScreen(hostId: 'c')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connect via (ProxyJump, ssh -J)'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Connect via (ProxyJump, ssh -J)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    container.dispose();
  });
}
