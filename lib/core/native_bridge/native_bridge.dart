// core/native_bridge/native_bridge.dart
//
// Wrapper Dart untuk semua operasi native Fase 1: Open With,
// Install/Uninstall APK, Media Scanner, dan baca data intent masuk
// (dipakai bareng intent_bridge.dart). Modul lain TIDAK boleh
// panggil MethodChannel langsung — selalu lewat sini, sama seperti
// pola PermissionManager di core/permissions.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NativeBridge {
  static const _channel = MethodChannel('com.dalx.app/native_bridge');

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
