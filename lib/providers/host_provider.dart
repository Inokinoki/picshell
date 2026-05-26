import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/host.dart';
import '../services/host_store.dart';

final hostStoreProvider = Provider<HostStore>((ref) {
  throw UnimplementedError('Initialize HostStore in main()');
});

final hostListProvider = StateNotifierProvider<HostListNotifier, List<Host>>((
  ref,
) {
  final store = ref.watch(hostStoreProvider);
  return HostListNotifier(store);
});

class HostListNotifier extends StateNotifier<List<Host>> {
  final HostStore _store;

  HostListNotifier(this._store) : super(_store.getHosts());

  void refresh() => state = _store.getHosts();

  Future<void> add(Host host) async {
    await _store.addHost(host);
    refresh();
  }

  Future<void> update(Host host) async {
    await _store.updateHost(host);
    refresh();
  }

  Future<void> delete(String id) async {
    await _store.deleteHost(id);
    refresh();
  }
}
