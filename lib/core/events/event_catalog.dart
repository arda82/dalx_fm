// core/events/event_catalog.dart
//
// Katalog SEMUA event yang beredar di DalX. Ini satu-satunya tempat
// modul boleh saling "bicara" — lihat ARCHITECTURE.md bagian 3 untuk
// alasan kenapa panggilan langsung antar modul di features/ dilarang.
//
// Cara menambah event baru:
//   1. Tambahkan class baru di file ini, turunan dari DalXEvent.
//   2. Tulis komentar jelas: dipicu kapan, data apa yang dibawa.
//   3. Tambahkan barisnya ke tabel katalog di ARCHITECTURE.md bagian 4.
//   4. Jangan buat event yang belum ada "pelanggan" nyata.

/// Base class seluruh event di DalX. Semua event yang lewat
/// core/events wajib turunan dari ini.
abstract class DalXEvent {
  const DalXEvent();
}

// ============================================================
// SUB-FASE 0a — Kerangka Hidup
// ============================================================

/// Dipicu saat user berhasil membuka sebuah folder di Explorer
/// (baik lewat tap folder, back, atau navigasi breadcrumb).
///
/// Dibawa: [path] — path folder yang baru dibuka.
///
/// Didengarkan oleh:
/// - explorer_ui   → refresh daftar file yang ditampilkan
/// - (breadcrumb, bagian dari explorer_ui) → update breadcrumb trail
///
/// Dipicu oleh:
/// - file_engine (satu-satunya modul yang boleh memicu event ini)
class FolderOpened extends DalXEvent {
  final String path;
  const FolderOpened(this.path);
}

/// Dipicu saat storage device (SD Card atau USB OTG) terpasang atau
/// terdeteksi tersedia oleh sistem Android.
///
/// Dibawa: [storageId] — identifier storage (mis. "sdcard", "usb_otg"),
///         [displayName] — nama yang ditampilkan ke user.
///
/// Didengarkan oleh:
/// - storage_overview → update kartu storage yang tadinya "Tidak
///   terpasang" jadi aktif dengan data kapasitas
/// - drawer (bagian dari explorer_ui/shell) → aktifkan entri SD
///   Card/USB OTG yang tadinya redup (muted)
///
/// Dipicu oleh:
/// - core/storage_access (listener sistem Android untuk mount event)
class StorageMounted extends DalXEvent {
  final String storageId;
  final String displayName;
  const StorageMounted(this.storageId, this.displayName);
}

// ============================================================
// SUB-FASE 0b — File Manager Fungsional
// ============================================================

/// Dipicu saat file/folder baru berhasil dibuat (New Folder/New File).
///
/// Dibawa: [path] — path lengkap item baru, [isFolder] — tipe item.
///
/// Didengarkan oleh: explorer_ui (refresh daftar file)
/// Dipicu oleh: file_engine
class FileCreated extends DalXEvent {
  final String path;
  final bool isFolder;
  const FileCreated(this.path, {required this.isFolder});
}

/// Dipicu saat file/folder berhasil dihapus (lewat Task Queue).
///
/// Dibawa: [paths] — daftar path yang dihapus (bisa multi-select).
///
/// Didengarkan oleh: explorer_ui (refresh daftar file)
/// Dipicu oleh: task_queue, setelah operasi delete selesai
class FileDeleted extends DalXEvent {
  final List<String> paths;
  const FileDeleted(this.paths);
}

/// Dipicu saat file/folder berhasil di-rename.
///
/// Dibawa: [oldPath], [newPath].
///
/// Didengarkan oleh: explorer_ui (refresh daftar file)
/// Dipicu oleh: file_engine
class FileRenamed extends DalXEvent {
  final String oldPath;
  final String newPath;
  const FileRenamed(this.oldPath, this.newPath);
}

/// Dipicu saat file/folder berhasil dipindah (Cut-Paste), lewat Task Queue.
///
/// Dibawa: [sourcePaths] — path asal (bisa multi), [destinationPath]
/// — folder tujuan.
///
/// Didengarkan oleh: explorer_ui (refresh daftar file di folder asal
/// maupun tujuan kalau sedang dibuka)
/// Dipicu oleh: task_queue, setelah operasi move selesai
class FileMoved extends DalXEvent {
  final List<String> sourcePaths;
  final String destinationPath;
  const FileMoved(this.sourcePaths, this.destinationPath);
}

/// Dipicu saat file/folder berhasil disalin (Copy-Paste), lewat Task Queue.
///
/// Dibawa: [sourcePaths] — path asal (bisa multi), [destinationPath]
/// — folder tujuan.
///
/// Didengarkan oleh: explorer_ui (refresh daftar file di folder tujuan
/// kalau sedang dibuka)
/// Dipicu oleh: task_queue, setelah operasi copy selesai
class FileCopied extends DalXEvent {
  final List<String> sourcePaths;
  final String destinationPath;
  const FileCopied(this.sourcePaths, this.destinationPath);
}

/// Dipicu berkala selama sebuah task di Task Queue berjalan, untuk
/// update progress bar.
///
/// Dibawa: [taskId] — id unik task, [progress] — 0.0 s/d 1.0.
///
/// Didengarkan oleh: task_queue UI (layar Task Queue)
/// Dipicu oleh: task_queue, selama eksekusi operasi
class TaskProgress extends DalXEvent {
  final String taskId;
  final double progress;
  const TaskProgress(this.taskId, this.progress);
}

/// Dipicu saat sebuah task selesai, baik sukses maupun gagal.
///
/// Dibawa: [taskId], [success], [errorMessage] (null kalau sukses).
///
/// Didengarkan oleh: task_queue UI, explorer_ui (untuk trigger refresh
/// setelah operasi selesai)
/// Dipicu oleh: task_queue
class TaskCompleted extends DalXEvent {
  final String taskId;
  final bool success;
  final String? errorMessage;
  const TaskCompleted(this.taskId, {required this.success, this.errorMessage});
}

// ============================================================
// FASE 1 DAN SETERUSNYA — BELUM DIIMPLEMENTASI
// ============================================================
//
// Didaftarkan sebagai catatan cakupan, belum diimplementasikan:
//
//   - StorageRemoved  (kebalikan StorageMounted, Fase 1/8 - USB OTG)
