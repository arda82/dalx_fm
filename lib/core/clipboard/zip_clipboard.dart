// core/clipboard/zip_clipboard.dart
//
// State clipboard KHUSUS buat Copy/Cut dari dalam ZipExplorerScreen
// (virtual browsing ZIP, lihat features/archive/zip_explorer_screen.dart).
// Dipisah dari clipboard cut/copy biasa (yang tinggal di
// ExplorerNotifier, per-instance/per-rootPath) karena ini perlu
// diakses LINTAS 2 tempat berbeda (ZipExplorerScreen tempat Copy/Cut
// dipencet, ExplorerNotifier tempat Paste beneran dieksekusi) — jadi
// ditaruh di core/ (bukan salah satu features/), konsisten sama
// aturan core/ tidak boleh depend ke features/ (isinya cuma path
// String polos, sama sekali tidak tahu-menahu soal FileItem/dll).
//
// TIDAK langsung extract apa pun pas Copy/Cut ditekan — cuma nyimpen
// KETERANGAN (path ZIP-nya, entry mana aja, cut atau copy). Extract
// beneran baru kejadian pas user Paste di folder asli (lihat
// TaskQueue.extractZipEntries) — biar nggak buang kerjaan kalau
// ternyata user batal paste.
//
// Cut dari dalam ZIP TIDAK PERNAH menulis ulang file ZIP asli (sudah
// dikonfirmasi Damar dari observasi file manager referensi) — "Cut"
// di sini SECARA TEKNIS sama persis kayak "Copy", isCut cuma dipakai
// buat pesan UI ("akan dipindah" vs "akan disalin"), bukan beda
// eksekusi.

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ZipClipboardData {
  final String zipPath;
  final List<String> entryPaths; // path lengkap DI DALAM zip (relatif ke root zip), file ATAU folder
  final bool isCut;

  const ZipClipboardData({
    required this.zipPath,
    required this.entryPaths,
    required this.isCut,
  });
}

class ZipClipboardNotifier extends StateNotifier<ZipClipboardData?> {
  ZipClipboardNotifier() : super(null);

  void set(String zipPath, List<String> entryPaths, {required bool isCut}) {
    state = ZipClipboardData(zipPath: zipPath, entryPaths: entryPaths, isCut: isCut);
  }

  void clear() => state = null;
}

final zipClipboardProvider = StateNotifierProvider<ZipClipboardNotifier, ZipClipboardData?>(
  (ref) => ZipClipboardNotifier(),
);
