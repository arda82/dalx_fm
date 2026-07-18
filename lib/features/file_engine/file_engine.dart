// features/file_engine/file_engine.dart
//
// File Engine Sub-Fase 0a: navigasi folder saja (Open/Back/Refresh).
// Operasi yang MENGUBAH filesystem (Copy/Move/Delete/dll) baru masuk
// di Sub-Fase 0b, lewat Task Queue — lihat ARCHITECTURE.md bagian 7.
//
// file_engine adalah satu-satunya modul yang boleh memicu event
// FolderOpened (lihat core/events/event_catalog.dart).

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';

class FileEngine {
  final DalXEventBus _eventBus;
  final List<String> _history = [];

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

  Future<List<FileItem>> _listFolder(Directory dir) async {
    final entities = await dir.list().toList();
    final items = <FileItem>[];

    for (final entity in entities) {
      final stat = await entity.stat();
      final name = entity.path.split(Platform.pathSeparator).last;

      items.add(FileItem(
        name: name,
        path: entity.path,
        type: entity is Directory ? FileItemType.folder : FileItemType.file,
        sizeBytes: entity is File ? stat.size : 0,
        modifiedAt: stat.modified,
      ));
    }

    // Folder dulu, baru file — masing-masing diurutkan nama A-Z.
    // Aturan sort lengkap (Default Sort dari Settings) menyusul di 0b.
    items.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }
}

/// Provider Riverpod untuk FileEngine — satu instance dipakai bersama.
final fileEngineProvider = Provider<FileEngine>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  return FileEngine(eventBus);
});
