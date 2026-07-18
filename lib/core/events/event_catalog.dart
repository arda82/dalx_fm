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
// SUB-FASE 0b DAN SETERUSNYA — BELUM DIIMPLEMENTASI
// ============================================================
//
// Didaftarkan di sini sebagai catatan cakupan, TAPI belum
// diimplementasikan — jangan dipakai sebelum sub-fase terkait
// benar-benar berjalan:
//
//   - FileCreated     (Sub-Fase 0b: New Folder / New File)
//   - FileDeleted     (Sub-Fase 0b: Delete, lewat Task Queue)
//   - FileRenamed     (Sub-Fase 0b: Rename)
//   - FileMoved       (Sub-Fase 0b: Cut-Paste, lewat Task Queue)
//   - FileCopied      (Sub-Fase 0b: Copy-Paste, lewat Task Queue)
//   - StorageRemoved  (Sub-Fase 0b: kebalikan StorageMounted)
//   - TaskProgress    (Sub-Fase 0b: update progress Task Queue)
//   - TaskCompleted   (Sub-Fase 0b: task selesai, sukses/gagal)
