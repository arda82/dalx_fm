// features/task_queue/task_queue.dart
//
// Task Queue: satu-satunya jalur untuk operasi yang MENGUBAH
// filesystem (Copy/Move/Delete). Semua modul lain (explorer_ui, dll)
// tidak boleh memanggil dart:io langsung untuk operasi ini — selalu
// lewat sini, supaya konsisten dengan Task Queue UI (progress,
// pause/resume/cancel) dan Event System.
//
// Sub-Fase 0b: pause/resume BELUM diimplementasikan penuh untuk
// operasi file individual (delete satu file tidak bisa "dijeda" di
// tengah), tapi API-nya sudah disiapkan untuk operasi multi-file
// yang bisa dijeda ANTAR file (bukan di tengah satu file).

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import 'task.dart';

class TaskQueue extends StateNotifier<List<DalXTask>> {
  final DalXEventBus _eventBus;
  int _idCounter = 0;
  final Map<String, bool> _cancelFlags = {};
  final Map<String, bool> _pauseFlags = {};

  TaskQueue(this._eventBus) : super([]);

  String _newTaskId() => 'task_${_idCounter++}';

  /// Menambahkan task Delete ke antrian dan langsung menjalankannya.
  Future<void> delete(List<String> paths) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.delete,
      sourcePaths: paths,
    );
    _addTask(task);
    await _runDelete(task);
  }

  /// Menambahkan task Copy ke antrian dan langsung menjalankannya.
  /// [strategy] menentukan perlakuan kalau ada nama yang sudah dipakai
  /// di folder tujuan (dipilih user lewat dialog di explorer_screen
  /// SEBELUM method ini dipanggil — lihat ExplorerNotifier.pasteHere).
  Future<void> copy(
    List<String> sourcePaths,
    String destinationPath, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.copy,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath,
    );
    _addTask(task);
    await _runCopyOrMove(task, isMove: false, strategy: strategy);
  }

  /// Menambahkan task Move (Cut-Paste) ke antrian dan langsung
  /// menjalankannya. Lihat catatan [strategy] di [copy].
  Future<void> move(
    List<String> sourcePaths,
    String destinationPath, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.move,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath,
    );
    _addTask(task);
    await _runCopyOrMove(task, isMove: true, strategy: strategy);
  }

  /// Kompres [sourcePaths] jadi satu file ZIP di [destinationDir].
  /// [zipFileName] nama yang diketik user di dialog (boleh tanpa
  /// ".zip", ditambah otomatis). Kalau nama itu sudah dipakai di
  /// folder tujuan, otomatis di-increment "(1)", "(2)", dst — TANPA
  /// nanya user ulang (beda dari konflik Paste/Extract, karena ini
  /// file baru yang memang lagi dibuat user sendiri).
  Future<void> compress(
    List<String> sourcePaths,
    String destinationDir,
    String zipFileName,
  ) async {
    final fileName = zipFileName.toLowerCase().endsWith('.zip') ? zipFileName : '$zipFileName.zip';
    final resolvedPath = await _resolveAvailableFilePath(destinationDir, fileName);

    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.compress,
      sourcePaths: sourcePaths,
      destinationPath: resolvedPath,
    );
    _addTask(task);
    await _runCompress(task);
  }

  /// Ekstrak isi [zipPath] ke sub-folder baru di [destinationDir],
  /// nama sub-folder = nama file zip tanpa ".zip". [strategy]
  /// menentukan perlakuan kalau nama sub-folder itu sudah dipakai di
  /// [destinationDir] (dipilih user lewat dialog konflik di
  /// explorer_screen — sama komponen dengan konflik Paste).
  Future<void> extract(
    String zipPath,
    String destinationDir, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final zipName = zipPath.split(Platform.pathSeparator).last;
    final baseName = zipName.toLowerCase().endsWith('.zip')
        ? zipName.substring(0, zipName.length - 4)
        : zipName;
    var destPath = '$destinationDir${Platform.pathSeparator}$baseName';

    final destExists = await Directory(destPath).exists() || await File(destPath).exists();
    if (destExists) {
      if (strategy == ConflictStrategy.skip) {
        // Tidak ada arti "lewati" kalau user memang lagi minta
        // extract — treat sebagai batal total, tidak buat task apa pun.
        return;
      } else if (strategy == ConflictStrategy.renameAuto) {
        destPath = await _resolveUniqueDestPath(destinationDir, baseName);
      }
      // ConflictStrategy.overwrite: destPath dipakai apa adanya, isi
      // hasil extract bercampur/menimpa isi folder yang sudah ada.
    }

    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.extract,
      sourcePaths: [zipPath],
      destinationPath: destPath,
    );
    _addTask(task);
    await _runExtract(task);
  }

  void pause(String taskId) {
    _pauseFlags[taskId] = true;
    _updateTask(taskId, (t) => t.copyWith(status: TaskStatus.paused));
  }

  void resume(String taskId) {
    _pauseFlags[taskId] = false;
    _updateTask(taskId, (t) => t.copyWith(status: TaskStatus.running));
  }

  void cancel(String taskId) {
    _cancelFlags[taskId] = true;
    _updateTask(taskId, (t) => t.copyWith(status: TaskStatus.cancelled));
  }

  /// Membuang task yang sudah selesai (completed/failed/cancelled)
  /// dari daftar — dipanggil dari tombol "Hapus selesai" di UI.
  void clearCompleted() {
    state = state.where((t) => !t.isDone).toList();
  }

  void _addTask(DalXTask task) {
    state = [...state, task];
  }

  void _updateTask(String taskId, DalXTask Function(DalXTask) update) {
    state = [
      for (final t in state)
        if (t.id == taskId) update(t) else t,
    ];
  }

  Future<void> _waitIfPaused(String taskId) async {
    while (_pauseFlags[taskId] == true) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _runDelete(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));
    final deleted = <String>[];

    try {
      for (var i = 0; i < task.sourcePaths.length; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final path = task.sourcePaths[i];
        final entity = await _resolveEntity(path);
        await entity.delete(recursive: true);
        deleted.add(path);

        final progress = (i + 1) / task.sourcePaths.length;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileDeleted(deleted));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task delete gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  Future<void> _runCopyOrMove(
    DalXTask task, {
    required bool isMove,
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));

    try {
      for (var i = 0; i < task.sourcePaths.length; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final sourcePath = task.sourcePaths[i];
        final name = sourcePath.split(Platform.pathSeparator).last;
        var destPath = '${task.destinationPath}${Platform.pathSeparator}$name';

        final destExists = await File(destPath).exists() || await Directory(destPath).exists();

        if (destExists) {
          if (strategy == ConflictStrategy.skip) {
            // Lewati item ini sepenuhnya, lanjut ke item berikutnya.
            final progress = (i + 1) / task.sourcePaths.length;
            _updateTask(task.id, (t) => t.copyWith(progress: progress));
            _eventBus.fire(TaskProgress(task.id, progress));
            continue;
          } else if (strategy == ConflictStrategy.renameAuto) {
            destPath = await _resolveUniqueDestPath(task.destinationPath!, name);
          }
          // ConflictStrategy.overwrite: biarkan destPath apa adanya —
          // File.copy menimpa file tujuan otomatis, dan copy folder
          // rekursif menggabungkan (merge) isi + menimpa file bentrok.
        }

        final entity = await _resolveEntity(sourcePath);
        if (entity is File) {
          await entity.copy(destPath);
          if (isMove) await entity.delete();
        } else if (entity is Directory) {
          await _copyDirectoryRecursive(entity, Directory(destPath));
          if (isMove) await entity.delete(recursive: true);
        }

        final progress = (i + 1) / task.sourcePaths.length;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      if (isMove) {
        _eventBus.fire(FileMoved(task.sourcePaths, task.destinationPath!));
      } else {
        _eventBus.fire(FileCopied(task.sourcePaths, task.destinationPath!));
      }
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task ${task.type} gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  Future<void> _runCompress(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));

    try {
      final archive = Archive();
      final total = task.sourcePaths.length;

      for (var i = 0; i < total; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final sourcePath = task.sourcePaths[i];
        final entity = await _resolveEntity(sourcePath);
        final baseName = sourcePath.split(Platform.pathSeparator).last;

        if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(baseName, bytes.length, bytes));
        } else if (entity is Directory) {
          await _addDirectoryToArchive(archive, entity, baseName);
        }

        // Sisakan 10% progress buat proses encode+tulis ZIP di akhir,
        // supaya progress bar gak "macet" di 100% pas file besar
        // masih diproses jadi bytes ZIP.
        final progress = total == 0 ? 0.9 : (i + 1) / total * 0.9;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      final zipData = ZipEncoder().encode(archive);
      await File(task.destinationPath!).writeAsBytes(zipData!);

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(task.destinationPath!, isFolder: false));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task compress gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  Future<void> _addDirectoryToArchive(Archive archive, Directory dir, String archivePathPrefix) async {
    await for (final entity in dir.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final archivePath = '$archivePathPrefix/$name';
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, archivePath);
      }
    }
  }

  Future<void> _runExtract(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));

    try {
      final zipPath = task.sourcePaths.first;
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final destDir = Directory(task.destinationPath!);
      await destDir.create(recursive: true);

      final total = archive.files.length;
      for (var i = 0; i < total; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final file = archive.files[i];
        final outPath = '${destDir.path}${Platform.pathSeparator}${file.name}';

        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }

        final progress = (i + 1) / total;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(task.destinationPath!, isFolder: true));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task extract gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  /// Beda dari [_resolveUniqueDestPath]: cek dulu apakah [fileName]
  /// polos (tanpa suffix) di [dir] masih kosong — kalau iya, dipakai
  /// apa adanya. Baru kalau sudah dipakai, increment "(1)", "(2)",
  /// dst. Dipakai Compress supaya nama pertama tidak selalu dapat
  /// "(1)" walau folder tujuan masih kosong.
  Future<String> _resolveAvailableFilePath(String dir, String fileName) async {
    final candidate = '$dir${Platform.pathSeparator}$fileName';
    final exists = await File(candidate).exists() || await Directory(candidate).exists();
    if (!exists) return candidate;
    return _resolveUniqueDestPath(dir, fileName);
  }

  /// Cari nama tujuan yang belum dipakai di [destinationDir], gaya
  /// "nama (1)", "nama (2)", dst — sama seperti FileEngine.duplicate.
  Future<String> _resolveUniqueDestPath(String destinationDir, String originalName) async {
    final dotIndex = originalName.lastIndexOf('.');
    final isDir = await Directory('$destinationDir${Platform.pathSeparator}$originalName').exists();
    final ext = (!isDir && dotIndex > 0) ? originalName.substring(dotIndex) : '';
    final baseName = (!isDir && dotIndex > 0) ? originalName.substring(0, dotIndex) : originalName;

    var counter = 1;
    String candidate;
    String candidatePath;
    do {
      candidate = '$baseName ($counter)$ext';
      candidatePath = '$destinationDir${Platform.pathSeparator}$candidate';
      counter++;
    } while (await File(candidatePath).exists() || await Directory(candidatePath).exists());

    return candidatePath;
  }

  Future<FileSystemEntity> _resolveEntity(String path) async {
    if (await Directory(path).exists()) return Directory(path);
    return File(path);
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
}

final taskQueueProvider = StateNotifierProvider<TaskQueue, List<DalXTask>>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  return TaskQueue(eventBus);
});
