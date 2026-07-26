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
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';
import '../../core/settings/app_settings.dart';
import '../file_engine/file_engine.dart';
import '../task_queue/task.dart';
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
  final ExplorerDefaultsNotifier _explorerDefaultsNotifier;

  // Dipakai untuk Cut-Paste: menyimpan path yang di-"cut" sampai user
  // paste di folder lain. Null berarti tidak ada operasi cut aktif.
  List<String>? _cutPaths;
  List<String>? _pendingCopyPaths;

  ExplorerNotifier(
    this._fileEngine,
    this._taskQueue,
    DalXEventBus eventBus,
    ExplorerDefaults defaults,
    this._explorerDefaultsNotifier,
  ) : super(ExplorerState(
          viewMode: defaults.defaultView == 'grid' ? ViewMode.grid : ViewMode.list,
          sortMode: _sortModeFromString(defaults.defaultSort),
          showHidden: defaults.defaultHidden,
        )) {
    // FileEngine juga perlu tau default sort/hidden dari awal, biar
    // openFolder() pertama kali langsung konsisten sama state di atas
    // (bukan cuma tampilan awal doang yang keliatan default, tapi
    // urutan/filter hasil baca folder-nya juga).
    _fileEngine.sortMode = state.sortMode;
    _fileEngine.showHidden = state.showHidden;

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

  static SortMode _sortModeFromString(String s) {
    switch (s) {
      case 'date':
        return SortMode.dateNewest;
      case 'size':
        return SortMode.size;
      default:
        return SortMode.name;
    }
  }

  /// Kebalikan [_sortModeFromString] — dipakai [setSortMode] buat
  /// nulis balik pilihan user ke SharedPreferences (lihat
  /// ExplorerDefaultsNotifier.setDefaultSort), supaya sort mode yang
  /// dipilih user PERSIST jadi default beneran, bukan cuma nempel di
  /// sesi Explorer yang lagi berjalan. `dateOldest` SENGAJA dipetakan
  /// ke string 'date' yang sama kayak `dateNewest` — ExplorerDefaults
  /// primitif cuma tau 3 kategori (name/date/size, lihat
  /// app_settings.dart), arah baru/lama dalam kategori 'date' bukan
  /// bagian dari "default" yang di-persist, cukup kategorinya.
  static String _sortModeToString(SortMode mode) {
    switch (mode) {
      case SortMode.dateNewest:
      case SortMode.dateOldest:
        return 'date';
      case SortMode.size:
        return 'size';
      case SortMode.name:
        return 'name';
    }
  }

  bool get canGoBack => _fileEngine.canGoBack;
  bool get atFilesystemRoot => _fileEngine.atFilesystemRoot;
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

  /// Root Mode saja: naik ke folder induk asli filesystem, di luar
  /// history ExplorerScreen ini. Lihat catatan di file_engine.dart.
  Future<void> goToParent() async {
    if (_fileEngine.atFilesystemRoot) return;
    state = state.copyWith(isLoading: true, errorMessage: null, selectedPaths: {});
    try {
      final items = await _fileEngine.goToParent();
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

  /// Batalkan clipboard copy/cut yang sedang menunggu di-paste, tanpa
  /// menyalin/memindah apa pun. Dipanggil dari tombol "Batal" di bar
  /// clipboard bawah layar.
  void cancelPendingPaste() {
    _cutPaths = null;
    _pendingCopyPaths = null;
    state = state.copyWith(); // trigger rebuild (field ini di luar ExplorerState)
  }

  /// Cek apakah ada nama item di clipboard yang sudah dipakai di
  /// folder tujuan saat ini. Dipanggil dari explorer_screen SEBELUM
  /// pasteHere, supaya bisa munculkan dialog Lewati/Timpa/Ganti Nama
  /// Otomatis kalau memang ada bentrok. Return list nama yang bentrok
  /// (kosong berarti aman, langsung paste tanpa dialog).
  Future<List<String>> checkPasteConflicts() async {
    final destination = state.currentPath;
    final paths = _cutPaths ?? _pendingCopyPaths;
    if (destination == null || paths == null || paths.isEmpty) return [];

    final conflicts = <String>[];
    for (final path in paths) {
      final name = path.split(Platform.pathSeparator).last;
      final destPath = '$destination${Platform.pathSeparator}$name';
      if (await File(destPath).exists() || await Directory(destPath).exists()) {
        conflicts.add(name);
      }
    }
    return conflicts;
  }

  /// Tempel (paste) item yang sebelumnya di-copy/cut ke folder yang
  /// sedang dibuka. [strategy] dipakai kalau ada nama yang bentrok —
  /// default renameAuto aman dipakai walau tidak ada konflik sama
  /// sekali (tidak berpengaruh kalau tidak ada bentrok).
  Future<void> pasteHere({ConflictStrategy strategy = ConflictStrategy.renameAuto}) async {
    final destination = state.currentPath;
    if (destination == null) return;

    if (_cutPaths != null && _cutPaths!.isNotEmpty) {
      final paths = _cutPaths!;
      _cutPaths = null;
      await _taskQueue.move(paths, destination, strategy: strategy);
    } else if (_pendingCopyPaths != null && _pendingCopyPaths!.isNotEmpty) {
      final paths = _pendingCopyPaths!;
      _pendingCopyPaths = null;
      await _taskQueue.copy(paths, destination, strategy: strategy);
    }
  }

  // ---------------- Fase 5 & Fase 8 Pilar #2: Archive (Compress/Extract) ----------------

  /// Kompres item yang sedang terpilih jadi satu file arsip di folder
  /// yang sedang dibuka. [fileNameInput] dari input dialog user.
  /// [format] default ZIP; [ArchiveFormat.sevenZip] jalan lewat native
  /// (Fase 8 Pilar #2) — lihat TaskQueue.compress.
  Future<void> compressSelected(
    String fileNameInput, {
    ArchiveFormat format = ArchiveFormat.zip,
  }) async {
    final destination = state.currentPath;
    final paths = state.selectedPaths.toList();
    if (destination == null || paths.isEmpty) return;
    state = state.copyWith(selectedPaths: {});
    await _taskQueue.compress(paths, destination, fileNameInput, format: format);
  }

  /// Cek apakah sub-folder hasil extract (nama = nama arsip tanpa
  /// ekstensinya, format apa pun — zip/7z/rar/tar/tar.gz) sudah ada
  /// di folder tujuan. Dipanggil dari explorer_screen SEBELUM
  /// extractArchive, supaya bisa munculkan dialog Lewati/Timpa/Ganti
  /// Nama Otomatis kalau memang bentrok.
  Future<bool> checkExtractConflict(String archivePath, String destinationDir) async {
    final archiveName = archivePath.split(Platform.pathSeparator).last;
    final baseName = stripArchiveExtension(archiveName);
    final destPath = '$destinationDir${Platform.pathSeparator}$baseName';
    return await Directory(destPath).exists() || await File(destPath).exists();
  }

  /// Ekstrak [archivePath] ke [destinationDir] — [destinationDir] bisa
  /// folder saat ini ("Di sini") atau folder hasil pilihan user lewat
  /// folder picker ("Pilih"). Format archive auto-detect dari
  /// ekstensi [archivePath] (lihat TaskQueue.extract) — tidak perlu
  /// parameter tambahan di sini.
  Future<void> extractArchive(
    String archivePath,
    String destinationDir, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    state = state.copyWith(selectedPaths: {});
    await _taskQueue.extract(archivePath, destinationDir, strategy: strategy);
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
    // Persist ke SharedPreferences (lewat ExplorerDefaultsNotifier)
    // — sebelumnya cuma diubah di state Riverpod sesi berjalan, jadi
    // balik ke default lama tiap app di-restart. Fire-and-forget
    // (tidak di-await) karena UI Explorer tidak perlu nunggu proses
    // simpan selesai buat langsung kelihatan responsif.
    _explorerDefaultsNotifier.setDefaultSort(_sortModeToString(mode));
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

/// SATU INSTANCE PER rootPath (family) — lihat catatan panjang di
/// file_engine.dart soal kenapa provider singleton biasa bikin state
/// Internal Storage/SD Card/USB OTG saling menimpa.
final explorerProvider = StateNotifierProvider.family<ExplorerNotifier, ExplorerState, String>(
  (ref, rootPath) {
    final fileEngine = ref.watch(fileEngineProvider(rootPath));
    final taskQueue = ref.watch(taskQueueProvider.notifier);
    final eventBus = ref.watch(eventBusProvider);
    // .read (bukan .watch) SENGAJA — defaults cuma dipakai sekali saat
    // ExplorerNotifier ini pertama kali dibuat (initial state). Kalau
    // user ubah default di Settings pas Explorer lagi kebuka, itu
    // cuma berlaku buat sesi Explorer BARU berikutnya, bukan langsung
    // ubah state Explorer yang sedang aktif (yang benar, karena kalau
    // .watch, ganti default akan ke-reset Explorer yang lagi dibuka
    // user tanpa diminta).
    final defaults = ref.read(explorerDefaultsProvider);
    final explorerDefaultsNotifier = ref.read(explorerDefaultsProvider.notifier);
    return ExplorerNotifier(fileEngine, taskQueue, eventBus, defaults, explorerDefaultsNotifier);
  },
);