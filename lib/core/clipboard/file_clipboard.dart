// core/clipboard/file_clipboard.dart
//
// State clipboard buat Copy/Cut file/folder BIASA (bukan dari dalam
// ZIP — itu ada di zip_clipboard.dart, TIDAK ikut berubah di revisi
// ini, tetap single-batch seperti semula).
//
// REVISI (panel clipboard mengambang multi-tujuan): dari SATU BATCH
// (paths + isCut global) jadi LIST ITEM AKUMULATIF. User bisa
// Copy/Cut dari beberapa folder berbeda di waktu berbeda, semua
// numpuk di list yang sama, lalu di-paste SEBAGIAN atau SELURUHNYA ke
// beberapa tujuan berbeda satu per satu (checklist per item, lihat
// explorer_screen.dart _ClipboardPanel).
//
// Item HILANG dari clipboard OTOMATIS begitu task Copy/Move-nya
// SUKSES — didengar lewat event FileCopied/FileMoved yang sudah
// di-fire TaskQueue (lihat task_queue.dart), BUKAN dihapus manual pas
// paste dipanggil. Konsekuensinya: kalau task gagal, event itu tidak
// pernah fire, jadi item otomatis TETAP ADA di clipboard, siap dicoba
// lagi — bukan hilang percuma.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../events/event_bus.dart';
import '../events/event_catalog.dart';

class ClipboardItem {
  final String path; // path lengkap file/folder yang di-copy/cut
  final bool isCut; // true = mode Cut (pindah), false = mode Copy (salin)

  const ClipboardItem({required this.path, required this.isCut});

  ClipboardItem copyWith({bool? isCut}) {
    return ClipboardItem(path: path, isCut: isCut ?? this.isCut);
  }
}

class FileClipboardNotifier extends StateNotifier<List<ClipboardItem>> {
  final DalXEventBus _eventBus;
  late final StreamSubscription<DalXEvent> _subscription;

  FileClipboardNotifier(this._eventBus) : super([]) {
    _subscription = _eventBus.stream.listen((event) {
      if (event is FileCopied) {
        removeByPaths(event.sourcePaths);
      } else if (event is FileMoved) {
        removeByPaths(event.sourcePaths);
      }
    });
  }

  /// Tambahkan [paths] ke clipboard dengan mode [isCut]. AKUMULATIF —
  /// item lama TIDAK hilang (beda dari versi lama yang mengganti
  /// seluruh isi clipboard). Kalau path yang sama sudah ada di
  /// clipboard, mode-nya di-update ke [isCut] yang baru tanpa
  /// mengubah posisinya di list.
  void add(List<String> paths, {required bool isCut}) {
    final existingPaths = {for (final item in state) item.path};
    final updated = [
      for (final item in state)
        if (paths.contains(item.path)) item.copyWith(isCut: isCut) else item,
    ];
    final newItems = paths.where((p) => !existingPaths.contains(p)).map(
          (p) => ClipboardItem(path: p, isCut: isCut),
        );
    state = [...updated, ...newItems];
  }

  /// Hapus item tertentu by path. Dipanggil OTOMATIS oleh listener di
  /// atas (paste sukses) MAUPUN manual dari UI (tombol X per-item).
  void removeByPaths(List<String> paths) {
    if (paths.isEmpty || state.isEmpty) return;
    final toRemove = paths.toSet();
    state = state.where((item) => !toRemove.contains(item.path)).toList();
  }

  void clear() => state = [];

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final fileClipboardProvider = StateNotifierProvider<FileClipboardNotifier, List<ClipboardItem>>(
  (ref) {
    final eventBus = ref.watch(eventBusProvider);
    return FileClipboardNotifier(eventBus);
  },
);