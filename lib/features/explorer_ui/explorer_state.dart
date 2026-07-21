// features/explorer_ui/explorer_state.dart
//
// State layar Explorer: daftar file, path saat ini, multi-select,
// dan view mode (List/Grid — Fase 2). explorer_ui TIDAK memanggil
// file_engine atau task_queue secara langsung untuk tahu kapan harus
// refresh — dia dengar event lewat event bus (lihat ARCHITECTURE.md
// bagian 3).
//
// Operasi Copy/Move/Delete di sini memanggil TaskQueue (bukan
// dart:io langsung) — file_engine cuma untuk operasi ringan (New
// Folder, New File, Rename, Duplicate) dan navigasi.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';
import '../file_engine/file_engine.dart';
import '../task_queue/task_queue.dart';

enum ViewMode { list, grid }

class ExplorerState {
  final String? currentPath;
  final List<FileItem> items;
  final bool isLoading;
  final String? errorMessage;
  final Set<String> selectedPaths;
  final bool showHidden;
  final SortMode sortMode;
  final ViewMode viewMode;

  const ExplorerState({
    this.currentPath,
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
    this.selectedPaths = const {},
    this.showHidden = false,
    this.sortMode = SortMode.name,
    this.viewMode = ViewMode.list,
  });

  bool get isSelectMode => selectedPaths.isNotEmpty;

  ExplorerState copyWith({
    String? currentPath,
    List<FileItem>? items,
    bool? isLoading,
    String? errorMessage,
    Set<String>? selectedPaths,
    bool? showHidden,
    SortMode? sortMode,
    ViewMode? viewMode,
  }) {
    return ExplorerState(
      currentPath: currentPath ?? this.currentPath,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      showHidden: showHidden ?? this.showHidden,
      sortMode: sortMode ?? this.sortMode,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

class ExplorerNotifier extends StateNotifier<ExplorerState> {
  final FileEngine _fileEngine;
  final TaskQueue _taskQueue;

  // Dipakai untuk Cut-Paste: menyimpan path yang di-"cut" sampai user
  // paste di folder lain. Null berarti tidak ada operasi cut aktif.
  List<String>? _cutPaths;
  List<String>? _pendingCopyPaths;

  ExplorerNotifier(this._fileEngine, this._taskQueue, DalXEventBus eventBus)
      : super(const ExplorerState()) {
    // explorer_ui cukup dengar event — tidak perlu tahu modul mana
    // yang memicunya (file_engine untuk navigasi/rename/create/
    // duplicate, TaskQueue untuk copy/move/delete yang lebih berat).
    eventBus.stream.whereEventType<FolderOpened>().listen((_) {
      _syncFromCurrentFolder();
    });
    eventBus.stream.whereEventType<FileDeleted>().listen((_) {
      _syncFromCurrentFolder(force: true);
    });
    eventBus.stream.whereEventType<FileMoved>().listen((_) {
      _syncFromCurrentFolder(force: true);
    });
    eventBus.stream.whereEventType<FileCopied>().listen((_) {
      _syncFromCurrentFolder(force: true);
    });
    eventBus.stream.whereEventType<FileRenamed>().listen((_) {
      _syncFromCurrentFolder(force: true);
    });
    eventBus.stream.whereEventType<FileCreated>().listen((_) {
      _syncFromCurrentFolder(force: true);
    });
  }

  bool get canGoBack => _fileEngine.canGoBack;
  bool get hasCutPaths => _cutPaths != null && _cutPaths!.isNotEmpty;
  bool get hasPendingPaste => hasCutPaths || (_pendingCopyPaths?.isNotEmpty ?? false);

  Future<void> openFolder(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null, selectedPaths: {});
    try {
      final items = await _fileEngine.openFolder(path);
      state = state.copyWith(currentPath: path, items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> goBack() async {
    if (!_fileEngine.canGoBack) return;
    state = state.copyWith(isLoading: true, errorMessage: null, selectedPaths: {});
    try {
      final items = await _fileEngine.goBack();
      state = state.copyWith(currentPath: _fileEngine.currentPath, items: items, isLoading: false);
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

  // ---------------- Multi Selection & Action Mode ----------------

  void toggleSelection(String path) {
    final updated = Set<String>.from(state.selectedPaths);
    if (updated.contains(path)) {
      updated.remove(path);
    } else {
      updated.add(path);
    }
    state = state.copyWith(selectedPaths: updated);
  }

  void enterSelectMode(String path) {
    state = state.copyWith(selectedPaths: {path});
  }

  void exitSelectMode() {
    state = state.copyWith(selectedPaths: {});
  }

  // ---------------- New Folder / New File / Rename / Duplicate ----------------
  // (via file_engine — operasi ringan, bukan lewat TaskQueue)

  Future<void> createFolder(String name) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.createFolder(name);
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createFile(String name) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.createFile(name);
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> renameItem(String oldPath, String newName) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _fileEngine.rename(oldPath, newName);
      state = state.copyWith(items: items, isLoading: false, selectedPaths: {});
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Menduplikasi semua item yang sedang terpilih (Fase 2 — Duplicate).
  /// Dijalankan satu-satu lewat file_engine (bukan TaskQueue) karena
  /// termasuk operasi ringan, sama seperti Rename/New Folder.
  Future<void> duplicateSelected() async {
    final paths = state.selectedPaths.toList();
    if (paths.isEmpty) return;
    state = state.copyWith(selectedPaths: {}, isLoading: true, errorMessage: null);
    try {
      var items = state.items;
      for (final path in paths) {
        items = await _fileEngine.duplicate(path);
      }
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // ---------------- Copy / Cut / Paste / Delete (via TaskQueue) ----------------

  /// Hapus semua item yang sedang terpilih. Operasi berjalan lewat
  /// TaskQueue (async, punya progress) — UI tidak nge-block.
  Future<void> deleteSelected() async {
    final paths = state.selectedPaths.toList();
    if (paths.isEmpty) return;
    state = state.copyWith(selectedPaths: {});
    await _taskQueue.delete(paths);
  }

  /// Menandai item terpilih untuk di-copy. Paste dilakukan di folder
  /// tujuan lewat [pasteHere].
  void copySelected() {
    _cutPaths = null; // pastikan bukan mode cut
    _pendingCopyPaths = state.selectedPaths.toList();
    state = state.copyWith(selectedPaths: {});
  }

  /// Menandai item terpilih untuk dipindah (cut). Paste dilakukan di
  /// folder tujuan lewat [pasteHere].
  void cutSelected() {
    _pendingCopyPaths = null;
    _cutPaths = state.selectedPaths.toList();
    state = state.copyWith(selectedPaths: {});
  }

  /// Tempel (paste) item yang sebelumnya di-copy/cut ke folder yang
  /// sedang dibuka.
  Future<void> pasteHere() async {
    final destination = state.currentPath;
    if (destination == null) return;

    if (_cutPaths != null && _cutPaths!.isNotEmpty) {
      final paths = _cutPaths!;
      _cutPaths = null;
      await _taskQueue.move(paths, destination);
    } else if (_pendingCopyPaths != null && _pendingCopyPaths!.isNotEmpty) {
      final paths = _pendingCopyPaths!;
      _pendingCopyPaths = null;
      await _taskQueue.copy(paths, destination);
    }
  }

  // ---------------- Hidden Files, Sort & View Mode ----------------

  void toggleShowHidden() {
    _fileEngine.showHidden = !_fileEngine.showHidden;
    state = state.copyWith(showHidden: _fileEngine.showHidden);
    refresh();
  }

  void setSortMode(SortMode mode) {
    _fileEngine.sortMode = mode;
    state = state.copyWith(sortMode: mode);
    refresh();
  }

  /// Toggle List View <-> Grid View (Fase 2 — Explorer Polish).
  void toggleViewMode() {
    state = state.copyWith(
      viewMode: state.viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list,
    );
  }

  // Dipanggil saat ada event yang mengindikasikan isi folder berubah.
  // [force] = true untuk event dari TaskQueue/file_engine yang selalu
  // perlu refresh, meski currentPath tidak berubah (beda dengan
  // FolderOpened biasa yang hanya sync kalau path benar-benar baru).
  Future<void> _syncFromCurrentFolder({bool force = false}) async {
    final path = _fileEngine.currentPath;
    if (path == null) return;
    if (!force && path == state.currentPath) return;
    final items = await _fileEngine.refresh();
    state = state.copyWith(currentPath: path, items: items);
  }
}

final explorerProvider =
    StateNotifierProvider<ExplorerNotifier, ExplorerState>((ref) {
  final fileEngine = ref.watch(fileEngineProvider);
  final taskQueue = ref.watch(taskQueueProvider.notifier);
  final eventBus = ref.watch(eventBusProvider);
  return ExplorerNotifier(fileEngine, taskQueue, eventBus);
});