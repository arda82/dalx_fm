// features/file_engine/file_engine.dart
//
// File Engine: navigasi folder (Sub-Fase 0a) + operasi ringan yang
// TIDAK butuh Task Queue (New Folder, New File, Rename, Duplicate —
// instan, bukan operasi besar). Copy/Move/Delete lewat TaskQueue
// (features/task_queue), bukan di sini — lihat ARCHITECTURE.md
// bagian 7.
//
// file_engine adalah satu-satunya modul yang boleh memicu event
// FolderOpened, FileCreated, dan FileRenamed.
//
// Root Mode (lihat core/settings/app_settings.dart): saat aktif,
// begitu history navigasi di ExplorerScreen habis (canGoBack false),
// goToParent() dipakai buat naik ke folder induk ASLI filesystem
// (di luar history), terus sampai mentok "/". Saat non-root, jalur
// ini tidak pernah dipanggil — ExplorerScreen langsung arahkan ke
// Layar Awal begitu history habis.

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../../core/settings/app_settings.dart';

enum SortMode { name, dateNewest, dateOldest, size }

class FileEngine {
  final DalXEventBus _eventBus;
  final NativeBridge _nativeBridge;
  final PerFolderSortStore _perFolderSortStore;
  final List<String> _history = [];

  bool showHidden = false;
  SortMode sortMode = SortMode.name;

  FileEngine(this._eventBus, this._nativeBridge, this._perFolderSortStore);

  /// Path folder yang sedang dibuka. Null kalau belum pernah buka
  /// folder sama sekali.
  String? get currentPath => _history.isEmpty ? null : _history.last;

  bool get canGoBack => _history.length > 1;

  /// True kalau folder yang sedang dibuka adalah root filesystem asli
  /// ("/") — dipakai Root Mode buat tau kapan berhenti naik.
  bool get atFilesystemRoot => currentPath == '/';

  /// Buka folder di [path], baca isinya, dan pancarkan FolderOpened.
  /// Melempar exception kalau path bukan direktori atau tidak bisa
  /// dibaca (mis. permission belum diberikan).
  ///
  /// [sortMode] di-load per-path DI SINI (bukan 1 default global lagi)
  /// — folder yang belum pernah di-set manual sortnya jatuh ke
  /// fallback SortMode.name.
  Future<List<FileItem>> openFolder(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileSystemException('Folder tidak ditemukan', path);
    }

    sortMode = _sortModeFromString(await _perFolderSortStore.getSort(path));

    final items = await _listFolder(dir);

    _history.add(path);
    _eventBus.fire(FolderOpened(path));

    return items;
  }

  /// Dipanggil dari explorer_state.dart pas user ganti sort lewat menu
  /// titik-tiga — persist KHUSUS buat [currentPath] (per-folder, bukan
  /// global). [sortMode] field di-update SINKRON duluan (sebelum
  /// bagian async-nya) supaya caller bisa langsung refresh() tanpa
  /// perlu nunggu proses simpan ke SharedPreferences selesai.
  Future<void> setSortModeForCurrentFolder(SortMode mode) async {
    sortMode = mode;
    final path = currentPath;
    if (path != null) {
      await _perFolderSortStore.setSort(path, _sortModeToString(mode));
    }
  }

  static SortMode _sortModeFromString(String? s) {
    switch (s) {
      case 'dateNewest':
        return SortMode.dateNewest;
      case 'dateOldest':
        return SortMode.dateOldest;
      case 'size':
        return SortMode.size;
      default:
        return SortMode.name;
    }
  }

  static String _sortModeToString(SortMode mode) => mode.name;

  /// Kembali ke folder sebelumnya di history. Melempar StateError
  /// kalau tidak ada folder sebelumnya (cek [canGoBack] dulu).
  Future<List<FileItem>> goBack() async {
    if (!canGoBack) {
      throw StateError('Tidak ada folder sebelumnya di history');
    }
    _history.removeLast(); // buang folder saat ini
    final previousPath = _history.removeLast(); // ambil & buang folder sebelumnya
    return openFolder(previousPath); // openFolder akan menambah lagi ke history
  }

  /// Root Mode saja: naik ke folder INDUK ASLI filesystem dari
  /// [currentPath], di luar history ExplorerScreen ini (mis. dari
  /// /storage/emulated/0 naik ke /storage, lalu /). Melempar
  /// StateError kalau sudah di root filesystem ("/") — cek
  /// [atFilesystemRoot] dulu sebelum panggil ini.
  Future<List<FileItem>> goToParent() async {
    final path = currentPath;
    if (path == null) {
      throw StateError('Belum ada folder yang dibuka');
    }
    final parent = _parentOf(path);
    if (parent == null) {
      throw StateError('Sudah di root filesystem');
    }
    return openFolder(parent);
  }

  String? _parentOf(String path) {
    if (path == '/') return null;
    final normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = normalized.lastIndexOf('/');
    if (idx <= 0) return '/';
    return normalized.substring(0, idx);
  }

  /// Baca ulang isi folder yang sedang dibuka tanpa mengubah history.
  Future<List<FileItem>> refresh() async {
    final path = currentPath;
    if (path == null) {
      throw StateError('Belum ada folder yang dibuka');
    }
    final dir = Directory(path);
    return _listFolder(dir);
  }

  /// Membuat folder baru bernama [name] di dalam folder yang sedang
  /// dibuka. Melempar exception kalau nama sudah dipakai atau gagal
  /// dibuat (mis. permission).
  Future<List<FileItem>> createFolder(String name) async {
    final path = currentPath;
    if (path == null) {
      throw StateError('Belum ada folder yang dibuka');
    }
    final newDir = Directory('$path${Platform.pathSeparator}$name');
    if (await newDir.exists()) {
      throw FileSystemException('Folder dengan nama itu sudah ada', newDir.path);
    }
    await newDir.create();
    _eventBus.fire(FileCreated(newDir.path, isFolder: true));
    return refresh();
  }

  /// Rename file/folder di [oldPath] jadi [newName] (nama saja, bukan
  /// path lengkap). Melempar exception kalau nama tujuan sudah dipakai.
  Future<List<FileItem>> rename(String oldPath, String newName) async {
    final parentPath = oldPath.substring(0, oldPath.lastIndexOf(Platform.pathSeparator));
    final newPath = '$parentPath${Platform.pathSeparator}$newName';

    final isDir = await Directory(oldPath).exists();
    final entity = isDir ? Directory(oldPath) : File(oldPath);

    if (await (isDir ? Directory(newPath) : File(newPath)).exists()) {
      throw FileSystemException('Nama tujuan sudah dipakai', newPath);
    }

    await entity.rename(newPath);
    _eventBus.fire(FileRenamed(oldPath, newPath));
    return refresh();
  }

  /// Membuat file kosong baru bernama [name] di folder yang sedang
  /// dibuka. Fase 2 (New File) — isi/edit file menyusul di code_editor
  /// (Fase 4).
  Future<List<FileItem>> createFile(String name) async {
    final path = currentPath;
    if (path == null) {
      throw StateError('Belum ada folder yang dibuka');
    }
    final newFile = File('$path${Platform.pathSeparator}$name');
    if (await newFile.exists()) {
      throw FileSystemException('File dengan nama itu sudah ada', newFile.path);
    }
    await newFile.create();
    _eventBus.fire(FileCreated(newFile.path, isFolder: false));
    return refresh();
  }

  /// Menduplikasi file/folder di [path] ke folder yang sama, nama
  /// otomatis "nama (1)", "nama (2)", dst. Fase 2 (Duplicate).
  Future<List<FileItem>> duplicate(String path) async {
    final isDir = await Directory(path).exists();
    final parentPath = path.substring(0, path.lastIndexOf(Platform.pathSeparator));
    final originalName = path.split(Platform.pathSeparator).last;

    final ext = isDir
        ? ''
        : (originalName.contains('.') ? '.${originalName.split('.').last}' : '');
    final baseName = isDir
        ? originalName
        : (ext.isEmpty ? originalName : originalName.substring(0, originalName.length - ext.length));

    var counter = 1;
    String newPath;
    do {
      newPath = '$parentPath${Platform.pathSeparator}$baseName ($counter)$ext';
      counter++;
    } while (await File(newPath).exists() || await Directory(newPath).exists());

    if (isDir) {
      await _copyDirectoryRecursive(Directory(path), Directory(newPath));
    } else {
      await File(path).copy(newPath);
    }

    _eventBus.fire(FileCreated(newPath, isFolder: isDir));
    return refresh();
  }

  Future<void> _copyDirectoryRecursive(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final newPath = '${destination.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectoryRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<List<FileItem>> _listFolder(Directory dir) async {
    // Sebagian folder (paling sering Android/data & Android/obb) bisa
    // gagal dibaca TOTAL lewat dart:io walau MANAGE_EXTERNAL_STORAGE
    // aktif — ini bug yang sudah dikonfirmasi tim Flutter sendiri
    // (flutter/flutter#108232, duplikat #40504): dart:io
    // Directory.list() melempar "Permission denied, errno=13" khusus
    // di path itu. File manager native (Amaze, CX File Manager) gak
    // kena ini karena mereka pakai java.io.File, bukan dart:io.
    //
    // Strateginya: coba dart:io dulu (lebih cepat buat kasus normal).
    // Kalau errornya bikin listing kosong TOTAL (bukan folder yang
    // memang kosong), fallback ke native Java File API lewat
    // NativeBridge.
    final entities = <FileSystemEntity>[];
    var hadStreamError = false;
    final doneCompleter = Completer<void>();

    dir.list(recursive: false, followLinks: false).listen(
      entities.add,
      onError: (_) {
        // Satu entry (atau seluruh listing) gagal dibaca — diabaikan
        // di sini, diproses lebih lanjut di bawah lewat hadStreamError.
        hadStreamError = true;
      },
      onDone: () => doneCompleter.complete(),
      cancelOnError: false,
    );
    await doneCompleter.future;

    if (hadStreamError && entities.isEmpty) {
      return _listFolderNative(dir.path);
    }

    final items = <FileItem>[];

    for (final entity in entities) {
      try {
        final stat = await entity.stat();
        final name = entity.path.split(Platform.pathSeparator).last;

        // Show/Hide Hidden Files — sesuai state showHidden, biasanya
        // dikontrol dari dropdown menu titik tiga di Explorer.
        if (!showHidden && name.startsWith('.')) continue;

        items.add(FileItem(
          name: name,
          path: entity.path,
          type: entity is Directory ? FileItemType.folder : FileItemType.file,
          sizeBytes: entity is File ? stat.size : 0,
          modifiedAt: stat.modified,
        ));
      } catch (_) {
        // Item ini gak bisa di-stat (permission denied spesifik buat
        // item ini) — skip, jangan gagalin seluruh folder.
        continue;
      }
    }

    _sortItems(items);
    return items;
  }

  /// Fallback lewat NativeBridge.listDirectoryNative (java.io.File) —
  /// lihat komentar panjang di _listFolder soal kenapa ini dibutuhkan.
  Future<List<FileItem>> _listFolderNative(String path) async {
    final entries = await _nativeBridge.listDirectoryNative(path);
    final items = <FileItem>[];

    for (final e in entries) {
      if (!showHidden && e.name.startsWith('.')) continue;
      items.add(FileItem(
        name: e.name,
        path: e.path,
        type: e.isDirectory ? FileItemType.folder : FileItemType.file,
        sizeBytes: e.isDirectory ? 0 : e.sizeBytes,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(e.modifiedAtMillis),
      ));
    }

    _sortItems(items);
    return items;
  }

  void _sortItems(List<FileItem> items) {
    items.sort((a, b) {
      // Folder selalu di atas file, terlepas dari sortMode.
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;

      switch (sortMode) {
        case SortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.dateNewest:
          return b.modifiedAt.compareTo(a.modifiedAt); // terbaru dulu
        case SortMode.dateOldest:
          return a.modifiedAt.compareTo(b.modifiedAt); // terlama dulu
        case SortMode.size:
          return b.sizeBytes.compareTo(a.sizeBytes); // terbesar dulu
      }
    });
  }
}

/// Provider Riverpod untuk FileEngine — SATU INSTANCE PER rootPath
/// (family), bukan singleton. Sebelum ini singleton biasa, dan itu
/// penyebab bug "SD Card kebuka isinya Internal Storage": history
/// navigasi & currentPath dari kunjungan sebelumnya nyangkut ke
/// rootPath yang beda, karena semua ExplorerScreen berbagi instance
/// yang sama.
final fileEngineProvider = Provider.family<FileEngine, String>((ref, rootPath) {
  final eventBus = ref.watch(eventBusProvider);
  final nativeBridge = ref.watch(nativeBridgeProvider);
  final perFolderSortStore = ref.watch(perFolderSortStoreProvider);
  return FileEngine(eventBus, nativeBridge, perFolderSortStore);
});

/// Hitung jumlah item di dalam sebuah folder, dengan cache tervalidasi
/// lewat modifiedAt (lihat komentar panjang PerFolderItemCountStore di
/// app_settings.dart). Dipakai [DalxFolderItemCount] (thumbnail_tile.dart)
/// buat subtitle "N item" di List View.
///
/// Return null kalau folder gak bisa dibaca (permission denied dsb) —
/// caller cukup gak nampilin apa-apa, bukan nampilin error.
class FolderItemCounter {
  final PerFolderItemCountStore _store;
  FolderItemCounter(this._store);

  Future<int?> count(String path, DateTime folderModifiedAt) async {
    final modifiedAtMillis = folderModifiedAt.millisecondsSinceEpoch;
    try {
      final cached = await _store.get(path);
      if (cached != null && cached.modifiedAtMillis == modifiedAtMillis) {
        return cached.count; // folder belum berubah sejak terakhir dihitung
      }

      var itemCount = 0;
      await for (final _ in Directory(path).list(recursive: false, followLinks: false)) {
        itemCount++;
      }

      await _store.set(path, itemCount, modifiedAtMillis);
      return itemCount;
    } catch (_) {
      return null;
    }
  }
}

/// Provider biasa (BUKAN family) — operasi ini gak terikat rootPath
/// ExplorerScreen tertentu, satu instance dipakai bareng buat semua
/// folder di storage manapun.
final folderItemCounterProvider = Provider<FolderItemCounter>((ref) {
  return FolderItemCounter(ref.watch(perFolderItemCountStoreProvider));
});