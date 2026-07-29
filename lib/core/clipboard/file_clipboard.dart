// core/clipboard/file_clipboard.dart
//
// State clipboard buat Copy/Cut file/folder BIASA (bukan dari dalam
// ZIP — itu ada di zip_clipboard.dart, pola file ini persis nyontek
// itu).
//
// Riwayat: awalnya ini dua field privat (_cutPaths/_pendingCopyPaths)
// langsung di ExplorerNotifier, per-instance/per-rootPath (lihat
// explorerProvider.family di explorer_state.dart). Ternyata itu bug:
// Copy di Internal Storage lalu Paste di SD Card (atau sebaliknya)
// gak kebaca, karena tiap rootPath punya ExplorerNotifier terpisah —
// field privat itu gak pernah nyambung lintas instance. Dipindah ke
// sini (global, satu provider dipakai semua rootPath) biar clipboard
// beneran nyambung lintas storage manapun, sama kayak zip clipboard
// yang dari awal sudah didesain global untuk alasan serupa.

import 'package:flutter_riverpod/flutter_riverpod.dart';

class FileClipboardData {
  final List<String> paths; // path lengkap file/folder yang di-copy/cut
  final bool isCut; // true = mode Cut (pindah), false = mode Copy (salin)

  const FileClipboardData({
    required this.paths,
    required this.isCut,
  });
}

class FileClipboardNotifier extends StateNotifier<FileClipboardData?> {
  FileClipboardNotifier() : super(null);

  void set(List<String> paths, {required bool isCut}) {
    state = FileClipboardData(paths: paths, isCut: isCut);
  }

  void clear() => state = null;
}

final fileClipboardProvider = StateNotifierProvider<FileClipboardNotifier, FileClipboardData?>(
  (ref) => FileClipboardNotifier(),
);
