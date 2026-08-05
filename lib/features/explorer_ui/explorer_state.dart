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
//
// REVISI (panel clipboard mengambang): file clipboard (bukan zip)
// sekarang list akumulatif (lihat file_clipboard.dart). Paste-nya
// TERPISAH dari zip clipboard total — pasteSelected/checkFilePaste-
// Conflicts baru khusus file clipboard, terima [paths] EKSPLISIT
// (subset yang dicentang user di panel), bukan implisit baca seluruh
// isi clipboard kayak sebelumnya. pasteZipHere/checkZipPasteConflicts
// TIDAK berubah sama sekali dari versi lama — zip clipboard tetap
// single-batch, di luar scope revisi ini.

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/clipboard/zip_clipboard.dart';
import '../../core/clipboard/file_clipboard.dart';
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
  final ZipClipboardNotifier _zipClipboardNotifier;

  final FileClipboardNotifier _fileClipboardNotifier;

  ExplorerNotifier(
    this._fileEngine,
    this._taskQueue,
    DalXEventBus eventBus,
    ExplorerDefaults defaults,
    this._zipClipboardNotifier,
    this._fileClipboardNotifier,
  ) : super(ExplorerState(
          viewMode: defaults.defaultView == 'grid' ? ViewMode.grid : ViewMode.list,
          showHidden: defaults.defaultHidden,
          // sortMode SENGAJA tidak di-seed dari defaults di sini lagi
          // (per-folder sekarang, bukan default global — lihat
          // file_engine.dart PerFolderSortStore). Nilai sortMode yang
          // BENAR baru didapat begitu openFolder() pertama kali
          // selesai (lihat method openFolder di bawah, sync dari
          // _fileEngine.sortMode). SortMode.name di sini cuma
          // placeholder sesaat sebelum itu.
        )) {
    _fileEngine.sortMode = state.sortMode;
    _fileEngine.showHidden = state.showHidden;

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
  bool get atFilesystemRoot => _fileEngine.atFilesystemRoot;

  Future<void> openFolder(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null, selectedPaths: {});
    try {
      final items = await _fileEngine.openFolder(path);
      // sortMode disinkron dari _fileEngine SETELAH openFolder selesai
      // — di dalamnya sudah di-load per-folder (lihat file_engine.dart
      // PerFolderSortStore), jadi tiga-titik menu Explorer nampilin
      // sort yang BENAR buat folder ini, bukan sort folder sebelumnya.
      state = state.copyWith(currentPath: path, items: items, isLoading: false, sortMode: _fileEngine.sortMode);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> goBack() async {
    if (!_fileEngine.canGoBack) return;
    state = state.copyWith(isLoading: true, errorMessage: null, selectedPaths: {});
    try {
      final items = await _fileEngine.goBack();
      state = state.copyWith(
        currentPath: _fileEngine.currentPath,
        items: items,
        isLoading: false,
        sortMode: _fileEngine.sortMode,
      );
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
      state = state.copyWith(
        currentPath: _fileEngine.currentPath,
        items: items,
        isLoading: false,
        sortMode: _fileEngine.sortMode,
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
  }// hasCutPaths (versi lama, single-mode global) DIHAPUS — clipboard
  // sekarang per-item bisa campur Copy+Move, tidak ada lagi "satu
  // mode buat semua". Ga ada pemanggil aktifnya juga (cuma nongol di
  // komentar), aman dibuang.

  bool get hasPendingZipPaste => _zipClipboardNotifier.state != null;
  bool get hasPendingFilePaste => _fileClipboardNotifier.state.isNotEmpty;

  Future<void> openFolder(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _fileEngine.openFolder(path);
      final items = await _fileEngine.refresh();
      state = state.copyWith(currentPath: path, items: items, isLoading: false, sortMode: _fileEngine.sortMode);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // ... (method navigasi/refresh lain di antara sini TIDAK berubah,
  // lihat file lama kalau butuh referensi lengkap — cuma potong biar
  // fokus ke bagian yang beneran diedit)

  // ---------------- Copy / Cut / Paste / Delete (via TaskQueue) ----------------

  Future<void> deleteSelected() async {
    final paths = state.selectedPaths.toList();
    if (paths.isEmpty) return;
    state = state.copyWith(selectedPaths: {});
    await _taskQueue.delete(paths);
  }

  /// Menandai item terpilih untuk di-copy. AKUMULATIF ke clipboard
  /// (lihat FileClipboardNotifier.add) — item lama yang belum
  /// di-paste TIDAK hilang.
  void copySelected() {
    _fileClipboardNotifier.add(state.selectedPaths.toList(), isCut: false);
    _zipClipboardNotifier.clear(); // cuma 1 JENIS clipboard aktif (file vs zip), bukan soal Copy vs Move lagi
    state = state.copyWith(selectedPaths: {});
  }

  /// Menandai item terpilih untuk dipindah (cut). AKUMULATIF, sama
  /// seperti [copySelected].
  void cutSelected() {
    _fileClipboardNotifier.add(state.selectedPaths.toList(), isCut: true);
    _zipClipboardNotifier.clear();
    state = state.copyWith(selectedPaths: {});
  }

  /// Batalkan clipboard ZIP yang sedang menunggu di-paste. Dipanggil
  /// dari tombol "Batal" di bar clipboard ZIP (bar lama, tidak
  /// berubah). Clipboard file REGULER punya cancel-all sendiri di
  /// panel baru (langsung lewat fileClipboardProvider, lihat
  /// explorer_screen.dart _ClipboardPanel) — tidak lewat sini lagi.
  void cancelPendingPaste() {
    _zipClipboardNotifier.clear();
    state = state.copyWith();
  }

  /// Cek konflik nama KHUSUS clipboard ZIP (tidak berubah dari versi
  /// lama).
  Future<List<String>> checkZipPasteConflicts() async {
    final destination = state.currentPath;
    if (destination == null) return [];

    final zipClip = _zipClipboardNotifier.state;
    if (zipClip == null) return [];

    final conflicts = <String>[];
    for (final path in zipClip.entryPaths) {
      final name = path.split('/').last;
      final destPath = '$destination${Platform.pathSeparator}$name';
      if (await File(destPath).exists() || await Directory(destPath).exists()) {
        conflicts.add(name);
      }
    }
    return conflicts;
  }

  /// Tempel clipboard ZIP ke folder saat ini (tidak berubah).
  Future<void> pasteZipHere({ConflictStrategy strategy = ConflictStrategy.renameAuto}) async {
    final destination = state.currentPath;
    if (destination == null) return;

    final zipClip = _zipClipboardNotifier.state;
    if (zipClip == null) return;

    _zipClipboardNotifier.clear();
    await _taskQueue.extractZipEntries(zipClip.zipPath, zipClip.entryPaths, destination);
  }

  /// Cek konflik nama buat subset [paths] EKSPLISIT dari clipboard
  /// file reguler — [paths] datang dari item yang DICENTANG user di
  /// panel, bukan implisit seluruh isi clipboard (beda dari versi
  /// lama, karena sekarang paste bisa parsial).
  Future<List<String>> checkFilePasteConflicts(List<String> paths) async {
    final destination = state.currentPath;
    if (destination == null || paths.isEmpty) return [];

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

  /// Tempel item TERPILIH (dicentang user di panel) ke folder yang
  /// sedang dibuka. [copyPaths]/[movePaths] sudah dipisah oleh
  /// pemanggil (explorer_screen.dart) berdasarkan mode per-item —
  /// dijalankan sebagai DUA task terpisah kalau campuran, karena
  /// TaskQueue.copy/move masing-masing cuma terima satu mode per
  /// panggilan.
  ///
  /// TIDAK clear clipboard manual di sini — item yang berhasil
  /// diantar hilang OTOMATIS lewat listener FileCopied/FileMoved di
  /// FileClipboardNotifier begitu task-nya SUKSES. Kalau task gagal,
  /// item otomatis tetap ada, siap dicoba paste ulang.
  Future<void> pasteSelected(
    List<String> copyPaths,
    List<String> movePaths, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final destination = state.currentPath;
    if (destination == null) return;

    if (copyPaths.isNotEmpty) {
      await _taskQueue.copy(copyPaths, destination, strategy: strategy);
    }
    if (movePaths.isNotEmpty) {
      await _taskQueue.move(movePaths, destination, strategy: strategy);
    }
  }

  // ... (compressSelected, checkExtractConflict, extractArchive,
  // toggleShowHidden, setSortMode, toggleViewMode, _syncFromCurrentFolder
  // TIDAK BERUBAH — tetap sama persis kayak file lama, tidak
  // disalin ulang di sini biar tidak berulang)
}

final explorerProvider = StateNotifierProvider.family<ExplorerNotifier, ExplorerState, String>(
  (ref, rootPath) {
    final fileEngine = ref.watch(fileEngineProvider(rootPath));
    final taskQueue = ref.watch(taskQueueProvider.notifier);
    final eventBus = ref.watch(eventBusProvider);
    final defaults = ref.read(explorerDefaultsProvider);
    final zipClipboardNotifier = ref.read(zipClipboardProvider.notifier);
    final fileClipboardNotifier = ref.read(fileClipboardProvider.notifier);
    return ExplorerNotifier(fileEngine, taskQueue, eventBus, defaults, zipClipboardNotifier, fileClipboardNotifier);
  },
);

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
    // sortMode field FileEngine di-update SINKRON di dalam method ini
    // (sebelum bagian async-nya) — lihat file_engine.dart, jadi aman
    // langsung refresh() tanpa nunggu proses simpan ke
    // SharedPreferences selesai. Persist-nya per-folder (currentPath),
    // BUKAN default global lagi — sesuai keputusan Damar.
    _fileEngine.setSortModeForCurrentFolder(mode);
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
    final zipClipboardNotifier = ref.read(zipClipboardProvider.notifier);
    final fileClipboardNotifier = ref.read(fileClipboardProvider.notifier);
    return ExplorerNotifier(fileEngine, taskQueue, eventBus, defaults, zipClipboardNotifier, fileClipboardNotifier);
  },
);
