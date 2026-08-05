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
import '../../core/native_bridge/native_bridge.dart';
import 'task.dart';

/// Buang ekstensi arsip dari [fileName] apa pun formatnya (zip/7z/rar/
/// tar/tar.gz/tgz) — dipakai buat nentuin nama sub-folder tujuan
/// extract. Top-level (bukan method privat TaskQueue) supaya bisa
/// dipakai juga dari explorer_state.dart (checkExtractConflict), yang
/// perlu hitungan nama sama persis SEBELUM task dikirim ke TaskQueue.
/// ".tar.gz"/".tgz" dicek DULUAN (ekstensi ganda) sebelum ekstensi
/// tunggal biasa, supaya "arsip.tar.gz" jadi "arsip" bukan "arsip.tar".
String stripArchiveExtension(String fileName) {
  final lower = fileName.toLowerCase();
  const doubleExts = ['.tar.gz'];
  for (final ext in doubleExts) {
    if (lower.endsWith(ext)) return fileName.substring(0, fileName.length - ext.length);
  }
  const singleExts = ['.zip', '.7z', '.rar', '.tar', '.tgz', '.gz'];
  for (final ext in singleExts) {
    if (lower.endsWith(ext)) return fileName.substring(0, fileName.length - ext.length);
  }
  return fileName;
}

/// Format buat MEMBUAT arsip baru (Compress). Extract sendiri auto-
/// detect dari ekstensi sourceFile, tidak butuh enum ini — lihat
/// [TaskQueue.extract].
enum ArchiveFormat { zip, sevenZip }

class TaskQueue extends StateNotifier<List<DalXTask>> {
  final DalXEventBus _eventBus;
  final NativeBridge _nativeBridge;
  int _idCounter = 0;
  final Map<String, bool> _cancelFlags = {};
  final Map<String, bool> _pauseFlags = {};

  TaskQueue(this._eventBus, this._nativeBridge) : super([]);

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

  /// Kompres [sourcePaths] jadi satu file arsip di [destinationDir].
  /// [fileNameInput] nama yang diketik user di dialog (boleh tanpa
  /// ekstensi, ditambah otomatis sesuai [format]). Kalau nama itu
  /// sudah dipakai di folder tujuan, otomatis di-increment "(1)",
  /// "(2)", dst — TANPA nanya user ulang (beda dari konflik
  /// Paste/Extract, karena ini file baru yang memang lagi dibuat user
  /// sendiri).
  ///
  /// [format] default ZIP (pure Dart, package:archive — sudah ada
  /// sejak Fase 5). [ArchiveFormat.sevenZip] jalan lewat native
  /// (Commons Compress, Fase 8 Pilar #2) — progress-nya datang dari
  /// [NativeBridge.archiveProgress], BUKAN dihitung di sini.
  Future<void> compress(
    List<String> sourcePaths,
    String destinationDir,
    String fileNameInput, {
    ArchiveFormat format = ArchiveFormat.zip,
  }) async {
    final ext = format == ArchiveFormat.sevenZip ? '.7z' : '.zip';
    final fileName = fileNameInput.toLowerCase().endsWith(ext) ? fileNameInput : '$fileNameInput$ext';
    final resolvedPath = await _resolveAvailableFilePath(destinationDir, fileName);

    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.compress,
      sourcePaths: sourcePaths,
      destinationPath: resolvedPath,
    );
    _addTask(task);
    if (format == ArchiveFormat.sevenZip) {
      await _runCompress7zNative(task);
    } else {
      await _runCompress(task);
    }
  }

  /// Ekstrak isi [archivePath] ke sub-folder baru di [destinationDir],
  /// nama sub-folder = nama file arsip tanpa ekstensinya. [strategy]
  /// menentukan perlakuan kalau nama sub-folder itu sudah dipakai di
  /// [destinationDir] (dipilih user lewat dialog konflik di
  /// explorer_screen — sama komponen dengan konflik Paste).
  ///
  /// Format DIDETEKSI OTOMATIS dari ekstensi [archivePath] — bukan
  /// parameter terpisah, karena file yang mau di-extract sudah pasti
  /// datang dengan ekstensinya sendiri (beda dari [compress] yang
  /// filenya belum ada). ZIP & tar/tar.gz jalan pure Dart
  /// (package:archive), 7z & RAR jalan lewat native (Fase 8 Pilar #2)
  /// — progressnya dari [NativeBridge.archiveProgress].
  Future<void> extract(
    String archivePath,
    String destinationDir, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final fileName = archivePath.split(Platform.pathSeparator).last;
    final baseName = stripArchiveExtension(fileName);
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
      sourcePaths: [archivePath],
      destinationPath: destPath,
    );
    _addTask(task);

    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.7z')) {
      await _runExtract7zNative(task);
    } else if (lowerName.endsWith('.rar')) {
      await _runExtractRarNative(task);
    } else if (lowerName.endsWith('.tar.gz') || lowerName.endsWith('.tgz') || lowerName.endsWith('.tar')) {
      await _runExtractTar(task, isGzipped: !lowerName.endsWith('.tar'));
    } else {
      // Default/fallback: ZIP (juga menangkap ekstensi tidak dikenal
      // — daripada gagal total, coba perlakukan sebagai ZIP dulu).
      await _runExtract(task);
    }
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

    // Path yang BENERAN berhasil dicopy/dipindah doang (bukan
    // task.sourcePaths mentah) — item yang di-skip TIDAK masuk sini,
    // biar FileCopied/FileMoved di bawah cuma laporin yang beneran
    // sukses. Ini yang FileClipboardNotifier andalkan buat auto-hapus
    // item dari clipboard (lihat core/clipboard/file_clipboard.dart)
    // — kalau di-skip tetap ikut dilaporkan, item bakal kehapus dari
    // clipboard padahal gak pernah beneran nyampe ke tujuan.
    final actuallyProcessed = <String>[];

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
        actuallyProcessed.add(sourcePath);

        final progress = (i + 1) / task.sourcePaths.length;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      if (actuallyProcessed.isNotEmpty) {
        if (isMove) {
          _eventBus.fire(FileMoved(actuallyProcessed, task.destinationPath!));
        } else {
          _eventBus.fire(FileCopied(actuallyProcessed, task.destinationPath!));
        }
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

  // ---------------- Fase 8 Pilar #2: Compress Native (7z & RAR) ----------------
  // CATATAN PENTING: cancel/pause TIDAK didukung untuk 3 method di
  // bawah ini — beda dari _runCompress/_runExtract (ZIP) yang bisa
  // cek _cancelFlags tiap iterasi karena loop-nya di Dart. Di sini
  // loop-nya jalan di native Kotlin (lihat NativeBridge.kt), Dart
  // cuma "nunggu" & dengerin progress lewat stream — request
  // cancel/pause TIDAK akan berhenti di tengah proses native. Ini
  // keterbatasan yang disadari (best-effort), bukan bug — konsisten
  // sama semangat "sebisanya" yang sudah disepakati sebelumnya buat
  // fitur native lain di Fase 8.

  /// Dengerin [NativeBridge.archiveProgress] selama [nativeCall]
  /// berjalan, update [DalXTask] & fire [TaskProgress] tiap event
  /// masuk — dipakai bareng ke-3 method native compress/extract di
  /// bawah biar nggak duplikasi listener setup.
  Future<void> _runNativeArchiveOp(DalXTask task, Future<void> Function() nativeCall) async {
    final subscription = _nativeBridge.archiveProgress.where((e) => e.taskId == task.id).listen((e) {
      _updateTask(task.id, (t) => t.copyWith(progress: e.progress));
      _eventBus.fire(TaskProgress(task.id, e.progress));
    });
    try {
      await nativeCall();
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _runCompress7zNative(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));
    try {
      await _runNativeArchiveOp(
        task,
        () => _nativeBridge.compress7z(task.id, task.sourcePaths, task.destinationPath!),
      );
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(task.destinationPath!, isFolder: false));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task compress (7z) gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  Future<void> _runExtract7zNative(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));
    try {
      await _runNativeArchiveOp(
        task,
        () => _nativeBridge.extract7z(task.id, task.sourcePaths.first, task.destinationPath!),
      );
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(task.destinationPath!, isFolder: true));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task extract (7z) gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  Future<void> _runExtractRarNative(DalXTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));
    try {
      await _runNativeArchiveOp(
        task,
        () => _nativeBridge.extractRar(task.id, task.sourcePaths.first, task.destinationPath!),
      );
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(task.destinationPath!, isFolder: true));
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task extract (RAR) gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  // ---------------- Copy/Cut dari ZipExplorerScreen (Virtual Browsing) ----------------

  /// Extract HANYA entry tertentu (file/folder terpilih user lewat
  /// Copy/Cut di ZipExplorerScreen) dari [zipPath] ke [destinationDir]
  /// — BUKAN extract seluruh isi arsip (itu tetap lewat [extract]
  /// biasa). Reuse [TaskType.extract] yang sudah ada (bukan enum
  /// baru) — secara konsep ini tetap "mengekstrak dari arsip", cuma
  /// sebagian bukan semua.
  ///
  /// [entryFullPaths] adalah path lengkap DI DALAM zip (dipisah '/'),
  /// boleh file atau folder — kalau folder, SEMUA file di dalamnya
  /// (rekursif) ikut ke-extract, dengan struktur folder itu sendiri
  /// dipertahankan sebagai folder baru di [destinationDir] (bukan
  /// isinya "tumpah" rata di destinationDir).
  ///
  /// [strategy] menentukan perlakuan kalau nama TOP-LEVEL entri
  /// (nama file/folder yang dipilih, BUKAN nama file di dalamnya
  /// satu-satu) sudah dipakai di [destinationDir] — resolusinya per
  /// entri TERPILIH, bukan per file individual di dalam folder yang
  /// dipilih (biar "Lewati"/"Ganti Nama Otomatis" konsisten: kalau
  /// pilih folder, seluruh folder itu yang dilewati/di-rename, bukan
  /// isinya berantakan sebagian ke-rename sebagian nggak).
  Future<void> extractZipEntries(
    String zipPath,
    List<String> entryFullPaths,
    String destinationDir, {
    ConflictStrategy strategy = ConflictStrategy.renameAuto,
  }) async {
    final task = DalXTask(
      id: _newTaskId(),
      type: TaskType.extract,
      sourcePaths: [zipPath],
      destinationPath: destinationDir,
    );
    _addTask(task);
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));

    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Resolusi konflik nama DULUAN per entri TOP-LEVEL yang dipilih,
      // SEBELUM kumpulin file-file di dalamnya satu-satu.
      // outputNameFor[entryFullPath] = nama hasil resolusi (null =
      // entri ini DILEWATI total, strategy skip — TIDAK ikut
      // di-extract sama sekali, dan TIDAK dianggap "berhasil diantar"
      // buat clipboard, lihat extractedEntries di bawah).
      final outputNameFor = <String, String?>{};
      for (final entryFullPath in entryFullPaths) {
        final originalName = entryFullPath.split('/').last;
        var outputName = originalName;
        final destPath = '$destinationDir${Platform.pathSeparator}$originalName';
        final destExists = await File(destPath).exists() || await Directory(destPath).exists();
        if (destExists) {
          if (strategy == ConflictStrategy.skip) {
            outputNameFor[entryFullPath] = null;
            continue;
          } else if (strategy == ConflictStrategy.renameAuto) {
            final uniquePath = await _resolveUniqueDestPath(destinationDir, originalName);
            outputName = uniquePath.split(Platform.pathSeparator).last;
          }
          // ConflictStrategy.overwrite: outputName dipakai apa adanya
          // — sama kayak _runCopyOrMove, isi yang sudah ada bakal
          // ketimpa/di-merge.
        }
        outputNameFor[entryFullPath] = outputName;
      }

      // Kumpulin semua file (bukan folder marker) yang match salah
      // satu entryFullPaths (persis ATAU descendant-nya kalau itu
      // folder) yang TIDAK di-skip — biar tau total buat hitung
      // progress duluan. relativePath pakai outputName HASIL RESOLUSI
      // (bukan nama asli) sebagai segmen pertama.
      final matches = <MapEntry<String, ArchiveFile>>[];
      for (final entryFullPath in entryFullPaths) {
        final outputName = outputNameFor[entryFullPath];
        if (outputName == null) continue; // di-skip

        final segments = entryFullPath.split('/');
        final parentPrefix = segments.length > 1 ? '${segments.sublist(0, segments.length - 1).join('/')}/' : '';
        for (final file in archive.files) {
          if (!file.isFile) continue;
          final name = file.name.replaceAll('\\', '/');
          final isSelf = name == entryFullPath;
          final isDescendant = name.startsWith('$entryFullPath/');
          if (!isSelf && !isDescendant) continue;
          // Suffix SETELAH nama asli entri (bisa '' buat file tunggal,
          // atau '/sisa/path...' buat isi folder) ditempel ke
          // outputName HASIL RESOLUSI — biar rename top-level ikut
          // "menular" ke semua file di dalamnya.
          final relativeSuffix = name.substring(parentPrefix.length + segments.last.length);
          matches.add(MapEntry('$outputName$relativeSuffix', file));
        }
      }

      final total = matches.isEmpty ? 1 : matches.length;
      for (var i = 0; i < matches.length; i++) {
        if (_cancelFlags[task.id] == true) break;
        await _waitIfPaused(task.id);

        final relativePath = matches[i].key;
        final file = matches[i].value;
        final outFile = File('$destinationDir${Platform.pathSeparator}$relativePath');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);

        final progress = (i + 1) / total;
        _updateTask(task.id, (t) => t.copyWith(progress: progress));
        _eventBus.fire(TaskProgress(task.id, progress));
      }

      if (_cancelFlags[task.id] == true) {
        _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: 'Dibatalkan'));
        return;
      }

      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.completed, progress: 1.0));
      _eventBus.fire(FileCreated(destinationDir, isFolder: true));
      // Entri yang BENERAN diantar doang (bukan entryFullPaths
      // mentah) — entri yang di-skip TIDAK dilaporkan "berhasil",
      // biar tetap nangkring di clipboard (bisa dicoba lagi ke
      // tujuan lain), bukan ikut kehapus padahal gak pernah nyampe.
      final extractedEntries = entryFullPaths.where((e) => outputNameFor[e] != null).toList();
      if (extractedEntries.isNotEmpty) {
        _eventBus.fire(ZipEntriesExtracted(zipPath, extractedEntries));
      }
      _eventBus.fire(TaskCompleted(task.id, success: true));
    } catch (e) {
      debugPrint('Task extractZipEntries gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
    }
  }

  /// Extract tar/tar.gz — PURE DART (package:archive), BUKAN native.
  /// archive package sudah cukup buat format ini (TarDecoder +
  /// GZipDecoder), jadi tidak perlu Commons Compress sama sekali
  /// (lihat ARCHITECTURE.md bagian 7.2 Pilar #2, revisi scope).
  /// Progress dihitung di Dart sama seperti [_runExtract] (ZIP), bisa
  /// di-cancel/pause normal (beda dari 3 method native di atas).
  Future<void> _runExtractTar(DalXTask task, {required bool isGzipped}) async {
    _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.running));
    try {
      final path = task.sourcePaths.first;
      final rawBytes = await File(path).readAsBytes();
      final tarBytes = isGzipped ? GZipDecoder().decodeBytes(rawBytes) : rawBytes;
      final archive = TarDecoder().decodeBytes(tarBytes);

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
      debugPrint('Task extract (tar) gagal: $e');
      _updateTask(task.id, (t) => t.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      _eventBus.fire(TaskCompleted(task.id, success: false, errorMessage: e.toString()));
    } finally {
      _cancelFlags.remove(task.id);
      _pauseFlags.remove(task.id);
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
  final nativeBridge = ref.watch(nativeBridgeProvider);
  return TaskQueue(eventBus, nativeBridge);
});
