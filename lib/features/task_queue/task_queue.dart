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
  Future<void> copy(List<String> sourcePaths, String destinationPath) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.copy,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath,
    );
    _addTask(task);
    await _runCopyOrMove(task, isMove: false);
  }

  /// Menambahkan task Move (Cut-Paste) ke antrian dan langsung
  /// menjalankannya.
  Future<void> move(List<String> sourcePaths, String destinationPath) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.move,
      sourcePaths: sourcePaths,
      destinationPath: destinationPath,
    );
    _addTask(task);
    await _runCopyOrMove(task, isMove: true);
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

  Future<void> _runCopyOrMove(DalXTask task, {required bool isMove}) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));

    try {
      for (var i = 0; i < task.sourcePaths.length; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final sourcePath = task.sourcePaths[i];
        final name = sourcePath.split(Platform.pathSeparator).last;
        final destPath = '${task.destinationPath}${Platform.pathSeparator}$name';

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
