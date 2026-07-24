// core/cache/cache_manager.dart
//
// Fase 7 — "Bersihkan Cache" di drawer. Yang dibersihkan: direktori
// cache app (getTemporaryDirectory(), otomatis terhapus sistem
// kapan pun tapi bisa numpuk kalau nggak pernah dibersihkan manual —
// dipakai video_player/beberapa plugin buat file sementara). File
// asli user di storage TIDAK PERNAH disentuh — cuma folder cache
// internal app sendiri.
//
// CATATAN: DalX belum generate thumbnail gambar/video sungguhan
// (Grid View di explorer_screen.dart masih pakai icon generik per
// tipe file, bukan render thumbnail asli) — jadi "Thumbnail Cache"
// dari nama fase di roadmap belum ada isinya buat dibersihkan.
// Baru "Folder Cache" (temp dir app) yang riil ada & dibersihkan di
// sini. Thumbnail generation sungguhan di luar scope Fase 7 ini.

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheManager {
  /// Total ukuran isi direktori cache app, dalam bytes.
  Future<int> getCacheSize() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      return await _dirSize(dir);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // File race condition (kehapus di tengah proses baca) — skip.
          }
        }
      }
    } catch (_) {
      // Directory tidak bisa dibaca — anggap 0, bukan error fatal.
    }
    return total;
  }

  /// Hapus semua isi direktori cache app (bukan direktorinya sendiri,
  /// biar plugin lain yang masih pegang referensi ke folder itu tidak
  /// error). Return jumlah bytes yang berhasil dibebaskan.
  Future<int> clearCache() async {
    final freedBytes = await getCacheSize();
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Ada file yang lagi dipakai/tidak bisa dihapus — lanjut ke
          // file berikutnya, jangan gagalkan seluruh proses.
        }
      }
    } catch (_) {
      // Abaikan — clearCache tetap return apa yang berhasil dihitung.
    }
    return freedBytes;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
