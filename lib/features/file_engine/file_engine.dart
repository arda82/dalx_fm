// features/file_engine/file_engine.dart
//
// File Engine: navigasi folder (Sub-Fase 0a) + operasi ringan yang
// TIDAK butuh Task Queue (New Folder, Rename — instan, bukan operasi
// besar). Copy/Move/Delete lewat TaskQueue (features/task_queue),
// bukan di sini — lihat ARCHITECTURE.md bagian 7.
//
// file_engine adalah satu-satunya modul yang boleh memicu event
// FolderOpened, FileCreated, dan FileRenamed.

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';

enum SortMode { name, date, size }

class FileEngine {
  final DalXEventBus _eventBus;
  final List<String> _history = [];

  bool showHidden = false;
  SortMode sortMode = SortMode.name;

  FileEngine(this._eventBus);

  /// Path folder yang sedang dibuka. Null kalau belum pernah buka
  /// folder sama sekali.
  String? get currentPath => _history.isEmpty ? null : _history.last;

  bool get canGoBack => _history.length > 1;

  /// Buka folder di [path], baca isinya, dan pancarkan FolderOpened.
  /// Melempar exception kalau path bukan direktori atau tidak bisa
  /// dibaca (mis. permission belum diberikan).
  Future<List<FileItem>> openFolder(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileSystemException('Folder tidak ditemukan', path);
    }

    final items = await _listFolder(dir);

    _history.add(path);
    _eventBus.fire(FolderOpened(path));

    return items;
  }

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

  Future<List<FileItem>> _listFolder(Directory dir) async {
    final entities = await dir.list().toList();
    final items = <FileItem>[];

    for (final entity in entities) {
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
    }

    items.sort((a, b) {
      // Folder selalu di atas file, terlepas dari sortMode.
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;

      switch (sortMode) {
        case SortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.date:
          return b.modifiedAt.compareTo(a.modifiedAt); // terbaru dulu
        case SortMode.size:
          return b.sizeBytes.compareTo(a.sizeBytes); // terbesar dulu
      }
    });

    return items;
  }
}

/// Provider Riverpod untuk FileEngine — satu instance dipakai bersama.
final fileEngineProvider = Provider<FileEngine>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  return FileEngine(eventBus);
});
