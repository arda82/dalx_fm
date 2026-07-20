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

class NativeBridge {
  static const _channel = MethodChannel('com.dalx.app/native_bridge');
  static const _storageEventChannel = EventChannel('com.dalx.app/storage_stream');

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
