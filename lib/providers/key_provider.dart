import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ssh_key.dart';
import '../services/host_store.dart';
import 'host_provider.dart';

final keyListProvider = StateNotifierProvider<KeyListNotifier, List<SshKey>>((
  ref,
) {
  final store = ref.watch(hostStoreProvider);
  return KeyListNotifier(store);
});

class KeyListNotifier extends StateNotifier<List<SshKey>> {
  final HostStore _store;

  KeyListNotifier(this._store) : super(_store.getKeys());

  void refresh() => state = _store.getKeys();

  Future<void> add(SshKey key) async {
    await _store.addKey(key);
    refresh();
  }

  Future<void> delete(String id) async {
    await _store.deleteKey(id);
    refresh();
  }
}
