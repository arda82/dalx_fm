// features/explorer_ui/explorer_state.dart
//
// State layar Explorer: daftar file yang tampil + path saat ini.
// explorer_ui TIDAK memanggil file_engine secara langsung untuk
// tahu kapan harus refresh — dia dengar event FolderOpened lewat
// event bus (lihat ARCHITECTURE.md bagian 3).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';
import '../file_engine/file_engine.dart';

class ExplorerState {
  final String? currentPath;
  final List<FileItem> items;
  final bool isLoading;
  final String? errorMessage;

  const ExplorerState({
    this.currentPath,
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ExplorerState copyWith({
    String? currentPath,
    List<FileItem>? items,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ExplorerState(
      currentPath: currentPath ?? this.currentPath,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class ExplorerNotifier extends StateNotifier<ExplorerState> {
  final FileEngine _fileEngine;

  ExplorerNotifier(this._fileEngine, DalXEventBus eventBus)
      : super(const ExplorerState()) {
    // explorer_ui cukup dengar event FolderOpened — tidak perlu tahu
    // modul mana yang memicunya (bisa file_engine, bisa nanti dari
    // drawer, dst).
    eventBus.stream.whereType<FolderOpened>().listen((event) {
      _syncFromCurrentFolder();
    });
  }

  /// Dipakai tombol back Android: true kalau masih ada folder
  /// sebelumnya di history (jadi back cukup pindah folder, bukan
  /// keluar app).
  bool get canGoBack => _fileEngine.canGoBack;

  Future<void> openFolder(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.openFolder(path);
      state = state.copyWith(
        currentPath: path,
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> goBack() async {
    if (!_fileEngine.canGoBack) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.goBack();
      state = state.copyWith(
        currentPath: _fileEngine.currentPath,
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.refresh();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // Dipanggil saat ada FolderOpened dari luar (mis. suatu saat drawer
  // ikut memicu event ini). Untuk 0a, sumbernya cuma file_engine
  // sendiri, jadi ini semacam jaring pengaman kalau sumbernya nanti
  // bertambah.
  Future<void> _syncFromCurrentFolder() async {
    final path = _fileEngine.currentPath;
    if (path == null || path == state.currentPath) return;
    final items = await _fileEngine.refresh();
    state = state.copyWith(currentPath: path, items: items);
  }
}

final explorerProvider =
    StateNotifierProvider<ExplorerNotifier, ExplorerState>((ref) {
  final fileEngine = ref.watch(fileEngineProvider);
  final eventBus = ref.watch(eventBusProvider);
  return ExplorerNotifier(fileEngine, eventBus);
});
