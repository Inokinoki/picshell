import 'package:hive/hive.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/session.dart';

class HostStore {
  static const _hostsBox = 'hosts';
  static const _keysBox = 'ssh_keys';
  static const _sessionsBox = 'sessions';

  late Box<Host> _hosts;
  late Box<SshKey> _keys;
  late Box<Session> _sessions;

  Future<void> init() async {
    _hosts = await Hive.openBox<Host>(_hostsBox);
    _keys = await Hive.openBox<SshKey>(_keysBox);
    _sessions = await Hive.openBox<Session>(_sessionsBox);
  }

  // Host CRUD
  List<Host> getHosts() => _hosts.values.toList();

  Future<void> addHost(Host host) async {
    await _hosts.put(host.id, host);
  }

  Future<void> updateHost(Host host) async {
    await _hosts.put(host.id, host);
  }

  Future<void> deleteHost(String id) async {
    await _hosts.delete(id);
  }

  Host? getHost(String id) => _hosts.get(id);

  // SSH Key CRUD
  List<SshKey> getKeys() => _keys.values.toList();

  Future<void> addKey(SshKey key) async {
    await _keys.put(key.id, key);
  }

  Future<void> deleteKey(String id) async {
    await _keys.delete(id);
  }

  SshKey? getKey(String id) => _keys.get(id);

  // Session CRUD
  List<Session> getSessions() => _sessions.values.toList();

  Future<void> saveSession(Session session) async {
    await _sessions.put(session.id, session);
  }

  Future<void> deleteSession(String id) async {
    await _sessions.delete(id);
  }
}
