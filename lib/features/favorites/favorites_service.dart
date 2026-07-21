// features/favorites/favorites_service.dart
//
// Favorites — daftar path file/folder yang ditandai user, persist
// lintas sesi lewat SharedPreferences. Modul ini TIDAK pakai event
// bus karena statusnya preferensi user, bukan perubahan filesystem.
// explorer_ui memanggil provider ini langsung, sama seperti pola
// file_engine/task_queue (lihat ARCHITECTURE.md bagian 3).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'dalx_favorites';

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_prefsKey) ?? []).toSet();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.toList());
  }

  bool isFavorite(String path) => state.contains(path);

  Future<void> toggle(String path) async {
    final updated = Set<String>.from(state);
    updated.contains(path) ? updated.remove(path) : updated.add(path);
    state = updated;
    await _persist();
  }

  /// Toggle banyak path sekaligus (multi-select). Kalau semua path
  /// sudah favorit, semua dihapus; kalau belum semua, sisanya ditambah.
  Future<void> toggleMultiple(List<String> paths) async {
    final updated = Set<String>.from(state);
    paths.every(updated.contains) ? updated.removeAll(paths) : updated.addAll(paths);
    state = updated;
    await _persist();
  }

  Future<void> remove(String path) async {
    state = Set<String>.from(state)..remove(path);
    await _persist();
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});