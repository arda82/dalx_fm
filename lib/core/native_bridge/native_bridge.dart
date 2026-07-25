// core/native_bridge/native_bridge.dart
//
// Wrapper Dart untuk semua operasi native Fase 1: Open With,
// Install/Uninstall APK, Media Scanner, dan baca data intent masuk
// (dipakai bareng intent_bridge.dart). Modul lain TIDAK boleh
// panggil MethodChannel langsung — selalu lewat sini, sama seperti
// pola PermissionManager di core/permissions.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Info satu storage volume (Internal/SD Card/USB OTG) dari
/// StorageManager sistem Android. DalX tidak dapat kepastian mutlak
/// dari sistem apakah suatu volume removable itu "SD Card" atau "USB
/// OTG" — keduanya sama-sama muncul sebagai volume removable, jadi
/// [label] (mis. "SD card", "USB Drive") dipakai buat pencocokan kata
/// kunci di core/storage_access.
class StorageVolumeInfo {
  final String path;
  final String label;
  final bool isRemovable;
  final bool isPrimary;
  final String state;

  const StorageVolumeInfo({
    required this.path,
    required this.label,
    required this.isRemovable,
    required this.isPrimary,
    required this.state,
  });

  factory StorageVolumeInfo.fromMap(Map<dynamic, dynamic> map) {
    return StorageVolumeInfo(
      path: map['path'] as String? ?? '',
      label: map['label'] as String? ?? 'Storage',
      isRemovable: map['isRemovable'] as bool? ?? false,
      isPrimary: map['isPrimary'] as bool? ?? false,
      state: map['state'] as String? ?? 'unknown',
    );
  }
}

/// Satu entry file/folder hasil listing native (Java File API), dipakai
/// khusus untuk fallback saat dart:io gagal (lihat listDirectoryNative
/// di NativeBridge).
class NativeFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final int modifiedAtMillis;

  const NativeFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAtMillis,
  });

  factory NativeFileEntry.fromMap(Map<dynamic, dynamic> map) {
    return NativeFileEntry(
      name: map['name'] as String? ?? '',
      path: map['path'] as String? ?? '',
      isDirectory: map['isDirectory'] as bool? ?? false,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAtMillis: (map['modifiedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Satu event progress dari [NativeBridge.archiveProgress] — dikirim
/// native selama compress7z/extract7z/extractRar berjalan.
class ArchiveProgressEvent {
  final String taskId;
  final double progress; // 0.0 - 1.0
  const ArchiveProgressEvent({required this.taskId, required this.progress});
}

class NativeBridge {
  static const _channel = MethodChannel('com.dalx.app/native_bridge');
  static const _storageEventChannel = EventChannel('com.dalx.app/storage_stream');
  static const _archiveEventChannel = EventChannel('com.dalx.app/archive_stream');

  /// Buka file lewat app lain (Open With), mirip "Open With" di file
  /// manager pada umumnya. [mimeType] opsional, default '*/*'.
  Future<void> openWith(String path, {String mimeType = '*/*'}) async {
    await _channel.invokeMethod('openWith', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  /// Cek apakah DalX sudah punya izin install app dari sumber tidak
  /// dikenal (Android 8+/API 26+; selalu true di bawahnya).
  Future<bool> canInstallPackages() async {
    final result = await _channel.invokeMethod<bool>('canInstallPackages');
    return result ?? false;
  }

  /// Buka layar Settings sistem untuk minta izin install APK.
  Future<void> requestInstallPermission() async {
    await _channel.invokeMethod('requestInstallPermission');
  }

  /// Trigger installer APK sistem untuk file di [path].
  Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }

  /// Trigger uninstaller sistem untuk [packageName].
  Future<void> uninstallApk(String packageName) async {
    await _channel.invokeMethod('uninstallApk', {'packageName': packageName});
  }

  /// Minta sistem Android re-scan [path] supaya muncul di
  /// galeri/app musik/dll (MediaScannerConnection).
  Future<void> scanMedia(String path) async {
    await _channel.invokeMethod('scanMedia', {'path': path});
  }

  /// Dipakai saat DalX dibuka dalam mode Document Picker (app lain
  /// minta DalX jadi file picker-nya) — kembalikan file terpilih ke
  /// app pemanggil lalu tutup DalX.
  Future<void> returnPickedFile(String path) async {
    await _channel.invokeMethod('returnPickedFile', {'path': path});
  }

  /// Baca data intent yang membuka DalX saat ini (dipanggil sekali
  /// di startup lewat intent_bridge.dart).
  Future<Map<dynamic, dynamic>> getLaunchIntentData() async {
    final result =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('getLaunchIntentData');
    return result ?? {'action': 'none', 'paths': <String>[]};
  }

  /// Fallback listing direktori lewat Java File API native (BUKAN
  /// dart:io) — dipakai file_engine saat dart:io Directory.list()
  /// gagal total (bug Flutter yang dikonfirmasi di
  /// flutter/flutter#108232, paling sering kena di Android/data &
  /// Android/obb walau MANAGE_EXTERNAL_STORAGE aktif).
  Future<List<NativeFileEntry>> listDirectoryNative(String path) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listDirectoryNative',
      {'path': path},
    );
    return (result ?? [])
        .map((e) => NativeFileEntry.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  // ---------------- Fase 1.5: Storage Eksternal ----------------

  /// Query sekali daftar semua storage volume yang di-mount (Internal,
  /// SD Card, USB OTG). Dipakai buat load awal (Storage Overview,
  /// drawer) — komplemen [storageVolumeChanges] yang real-time.
  Future<List<StorageVolumeInfo>> getStorageVolumes() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getStorageVolumes');
    return (result ?? [])
        .map((e) => StorageVolumeInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// Kapasitas (total & free bytes) storage di [path] mana pun — bukan
  /// cuma Internal Storage seperti getStorageInfo di device_info.
  Future<Map<String, int>> getStorageCapacity(String path) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getStorageCapacity',
      {'path': path},
    );
    return {
      'totalBytes': (result?['totalBytes'] as num?)?.toInt() ?? 0,
      'freeBytes': (result?['freeBytes'] as num?)?.toInt() ?? 0,
    };
  }

  /// Stream real-time: nyala tiap kali SD Card/USB OTG dicolok atau
  /// dicabut (StorageManager.registerStorageVolumeCallback di sisi
  /// native), bukan hasil polling manual dari Dart.
  Stream<List<StorageVolumeInfo>> get storageVolumeChanges {
    return _storageEventChannel.receiveBroadcastStream().map((event) {
      final list = event as List<dynamic>;
      return list.map((e) => StorageVolumeInfo.fromMap(e as Map<dynamic, dynamic>)).toList();
    });
  }

  // ---------------- Thumbnail Generation (kekurangan pra-Fase 8) ----------------

  /// Generate (atau ambil dari cache disk kalau sudah ada) thumbnail
  /// untuk file gambar/video di [path]. [modifiedAtMillis] dipakai
  /// native sebagai bagian cache key (bareng [path]) — thumbnail
  /// otomatis "invalid" sendiri kalau file aslinya berubah, tanpa
  /// perlu tracking manual dari Dart. Native yang generate DAN cek
  /// cache disk-nya sekaligus (idempotent) — panggilan kedua untuk
  /// file yang sama langsung balik cepat tanpa decode ulang.
  ///
  /// Return path file thumbnail JPEG kecil di cache dir DalX, atau
  /// null kalau gagal (file korup, dll) — caller WAJIB fallback ke
  /// icon generik, bukan anggap ini selalu sukses.
  Future<String?> generateThumbnail(
    String path, {
    required int modifiedAtMillis,
    required bool isVideo,
  }) async {
    try {
      return await _channel.invokeMethod<String>('generateThumbnail', {
        'path': path,
        'modifiedAtMillis': modifiedAtMillis,
        'isVideo': isVideo,
      });
    } on PlatformException {
      return null;
    }
  }

  // ---------------- Compress Native: 7z & RAR (Fase 8 Pilar #2) ----------------
  // SENGAJA cuma 7z (compress+extract) & RAR (extract) — ZIP dan
  // tar/tar.gz TETAP pure Dart via package:archive (lihat
  // ARCHITECTURE.md bagian 7.2 Pilar #2, revisi scope), jadi TIDAK
  // ada method compressZip/extractTar dsb di sini — itu sepenuhnya
  // ditangani task_queue.dart tanpa lewat native_bridge sama sekali.
  //
  // Progress operasi ini TIDAK dibalikin lewat return value method di
  // bawah (method-nya cuma nunggu sampai selesai/gagal) — progress
  // real-time selama proses jalan didengarkan terpisah lewat
  // [archiveProgress] (EventChannel), di-key per [taskId] biar Task
  // Queue Dart tau progress ini punya task yang mana.

  /// Compress [sourcePaths] (file/folder, direkursif kalau folder)
  /// jadi satu file 7z di [destinationPath]. Melempar
  /// [PlatformException] kalau gagal (source tidak ke-baca, disk
  /// penuh, dll) — caller (task_queue.dart) yang tangani jadi
  /// TaskStatus.failed.
  Future<void> compress7z(
    String taskId,
    List<String> sourcePaths,
    String destinationPath,
  ) async {
    await _channel.invokeMethod('compress7z', {
      'taskId': taskId,
      'sourcePaths': sourcePaths,
      'destinationPath': destinationPath,
    });
  }

  /// Extract file 7z di [sourcePath] ke folder [destinationDir].
  Future<void> extract7z(
    String taskId,
    String sourcePath,
    String destinationDir,
  ) async {
    await _channel.invokeMethod('extract7z', {
      'taskId': taskId,
      'sourcePath': sourcePath,
      'destinationDir': destinationDir,
    });
  }

  /// Extract file RAR di [sourcePath] ke folder [destinationDir].
  /// Progress buat RAR CUMA 2 titik (0% mulai, 100% selesai) — bukan
  /// per-file granular kayak 7z, trade-off yang disadari (lihat
  /// catatan di NativeBridge.kt extractRarAsync).
  Future<void> extractRar(
    String taskId,
    String sourcePath,
    String destinationDir,
  ) async {
    await _channel.invokeMethod('extractRar', {
      'taskId': taskId,
      'sourcePath': sourcePath,
      'destinationDir': destinationDir,
    });
  }

  /// Stream progress real-time buat [compress7z]/[extract7z]/
  /// [extractRar] yang lagi jalan. Dengarkan & filter berdasar
  /// [ArchiveProgressEvent.taskId] yang cocok sama task yang sedang
  /// ditunggu (Task Queue jalan sekuensial, tapi filter ini tetap
  /// dijaga jaga-jaga ke depan kalau suatu saat ada paralel).
  Stream<ArchiveProgressEvent> get archiveProgress {
    return _archiveEventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<dynamic, dynamic>;
      return ArchiveProgressEvent(
        taskId: map['taskId'] as String? ?? '',
        progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      );
    });
  }

  // ---------------- Edit PDF: Rotate (Fase 8 Pilar #3) ----------------

  /// Rotate SEMUA halaman file PDF di [sourcePath] sejauh [degrees]
  /// (kelipatan 90 — 90/180/270/-90 dst), simpan hasilnya sebagai
  /// file BARU di [destinationPath] (TIDAK menimpa file asli — lebih
  /// aman, konsisten sama prinsip proyek "jangan rusak data user
  /// tanpa sengaja"). Operasi RINGAN (cuma ubah dictionary /Rotate
  /// per halaman, bukan render ulang isi), jadi TIDAK ada progress
  /// granular — cukup tunggu sampai selesai/gagal.
  Future<void> rotatePdf(
    String sourcePath,
    String destinationPath,
    int degrees,
  ) async {
    await _channel.invokeMethod('rotatePdf', {
      'sourcePath': sourcePath,
      'destinationPath': destinationPath,
      'degrees': degrees,
    });
  }

  /// Tebak MIME type dari ekstensi file, dipakai untuk [openWith] dan
  /// deteksi APK. Sederhana by-extension, bukan pakai package
  /// eksternal — cukup untuk kebutuhan Fase 1.
  static String mimeTypeFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'mp4': 'video/mp4', 'mkv': 'video/x-matroska', 'mov': 'video/quicktime',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg', 'flac': 'audio/flac',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'zip': 'application/zip',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? '*/*';
  }
}

final nativeBridgeProvider = Provider<NativeBridge>((ref) => NativeBridge());
