// core/device_info/device_info_manager.dart
//
// Jembatan ke platform channel native (lihat MainActivity.kt) untuk
// baca kapasitas storage (StatFs) dan RAM (ActivityManager) asli
// device — dart:io tidak punya akses langsung ke API ini karena
// keduanya spesifik Android.
//
// Modul lain (storage_overview, dll) TIDAK boleh panggil MethodChannel
// langsung — selalu lewat sini, sama seperti pola PermissionManager.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageInfo {
  final int totalBytes;
  final int freeBytes;

  const StorageInfo({required this.totalBytes, required this.freeBytes});

  int get usedBytes => totalBytes - freeBytes;
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

class RamInfo {
  final int totalBytes;
  final int availableBytes;

  const RamInfo({required this.totalBytes, required this.availableBytes});

  int get usedBytes => totalBytes - availableBytes;
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

class DeviceInfoManager {
  static const _channel = MethodChannel('com.dalx.app/device_info');

  Future<StorageInfo> getStorageInfo() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getStorageInfo');
    return StorageInfo(
      totalBytes: result?['totalBytes'] as int? ?? 0,
      freeBytes: result?['freeBytes'] as int? ?? 0,
    );
  }

  Future<RamInfo> getRamInfo() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getRamInfo');
    return RamInfo(
      totalBytes: result?['totalBytes'] as int? ?? 0,
      availableBytes: result?['availableBytes'] as int? ?? 0,
    );
  }
}

final deviceInfoManagerProvider = Provider<DeviceInfoManager>((ref) => DeviceInfoManager());
