import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:picshell/models/host.dart';
import 'package:picshell/services/host_store.dart';
import 'dart:io';

void main() {
  late HostStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picshell_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HostAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AuthTypeAdapter());
    }
    store = HostStore();
    await store.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('add and retrieve host', () async {
    final host = Host(
      id: '1',
      name: 'Test',
      hostname: '192.168.1.1',
      username: 'root',
    );
    await store.addHost(host);
    expect(store.getHosts().length, 1);
    expect(store.getHost('1')?.name, 'Test');
  });

  test('delete host', () async {
    final host = Host(
      id: '1',
      name: 'Test',
      hostname: '1.2.3.4',
      username: 'u',
    );
    await store.addHost(host);
    await store.deleteHost('1');
    expect(store.getHosts().length, 0);
  });
}
