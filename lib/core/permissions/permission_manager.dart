// core/permissions/permission_manager.dart
//
// Mengurus permintaan izin akses storage penuh (MANAGE_EXTERNAL_STORAGE)
// yang dibutuhkan DalX untuk baca/tulis semua file, termasuk hidden
// files. Modul lain (file_engine, dll) TIDAK boleh panggil
// permission_handler langsung — selalu lewat sini, supaya kalau nanti
// ada perubahan cara minta izin, cukup diubah di satu tempat.

import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  /// Cek apakah izin akses storage penuh sudah diberikan.
  Future<bool> hasStorageAccess() async {
    final status = await Permission.manageExternalStorage.status;
    return status.isGranted;
  }

  /// Minta izin akses storage penuh. Mengembalikan true kalau
  /// diberikan, false kalau ditolak.
  ///
  /// Catatan: MANAGE_EXTERNAL_STORAGE membuka layar Settings sistem
  /// Android (bukan dialog biasa), karena ini izin sensitif.
  Future<bool> requestStorageAccess() async {
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }
}
