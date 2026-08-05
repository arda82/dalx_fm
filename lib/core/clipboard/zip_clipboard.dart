// core/clipboard/zip_clipboard.dart
//
// State clipboard KHUSUS buat Copy/Cut dari dalam ZipExplorerScreen
// (virtual browsing ZIP, lihat features/archive/zip_explorer_screen.dart).
// Dipisah dari clipboard cut/copy biasa (file_clipboard.dart) karena
// unit-nya beda: bukan path filesystem, tapi (zipPath, entryPath di
// dalam zip). Ditaruh di core/ (bukan features/) karena dipakai
// LINTAS 2 tempat (ZipExplorerScreen tempat Copy/Cut dipencet,
// ExplorerNotifier tempat Paste beneran dieksekusi).
//
// REVISI (panel clipboard mengambang multi-tujuan, sama kayak
// file_clipboard.dart): dari SATU BATCH (satu zipPath + list entri)
// jadi LIST ITEM AKUMULATIF. Item BISA dari ZIP yang BEDA-BEDA — user
// boleh Copy dari zip A, lalu browsing lagi masuk zip B, Copy dari
// situ juga, semua numpuk di clipboard yang sama. Makanya
// [ZipClipboardItem] bawa [zipPath] SENDIRI per item (bukan lagi satu
// zipPath global buat semua item).
//
// TIDAK langsung extract apa pun pas Copy/Cut ditekan — cuma nyimpen
// KETERANGAN. Extract beneran baru kejadian pas user Paste di folder
// asli (lihat TaskQueue.extractZipEntries). Item HILANG dari
// clipboard OTOMATIS begitu extract-nya SUKSES — didengar lewat event
// ZipEntriesExtracted (lihat event_catalog.dart), bukan dihapus
// manual pas paste dipanggil. Kalau extract gagal, item otomatis
// tetap ada, siap dicoba lagi.
//
// Cut dari dalam ZIP TIDAK PERNAH menulis ulang file ZIP asli (sudah
// dikonfirmasi Damar dari observasi file manager referensi) — "Cut"
// di sini SECARA TEKNIS sama persis kayak "Copy", isCut cuma dipakai
// buat pesan/tag UI ("akan dipindah" vs "akan disalin"), bukan beda
// eksekusi.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../events/event_bus.dart';
import '../events/event_catalog.dart';

class ZipClipboardItem {
  final String zipPath;
  final String entryPath; // path lengkap DI DALAM zip (delimiter '/'), file ATAU folder
  final bool isCut; // kosmetik doang (lihat catatan di atas), TIDAK ganti eksekusi

  const ZipClipboardItem({
    required this.zipPath,
    required this.entryPath,
    required this.isCut,
  });

  ZipClipboardItem copyWith({bool? isCut}) {
    return ZipClipboardItem(zipPath: zipPath, entryPath: entryPath, isCut: isCut ?? this.isCut);
  }
}

class ZipClipboardNotifier extends StateNotifier<List<ZipClipboardItem>> {
  final DalXEventBus _eventBus;
  late final StreamSubscription<DalXEvent> _subscription;

  ZipClipboardNotifier(this._eventBus) : super([]) {
    _subscription = _eventBus.stream.listen((event) {
      if (event is ZipEntriesExtracted) {
        removeEntries(event.zipPath, event.entryPaths);
      }
    });
  }

  /// Tambahkan entri dari [zipPath] ke clipboard. AKUMULATIF — item
  /// lama (termasuk dari zip lain) TIDAK hilang. Kalau entri yang
  /// sama (zipPath + entryPath sama-sama cocok) sudah ada, mode
  /// [isCut]-nya di-update tanpa mengubah posisi di list.
  void add(String zipPath, List<String> entryPaths, {required bool isCut}) {
    final updated = [
      for (final item in state)
        if (item.zipPath == zipPath && entryPaths.contains(item.entryPath))
          item.copyWith(isCut: isCut)
        else
          item,
    ];
    final existingInThisZip = state.where((i) => i.zipPath == zipPath).map((i) => i.entryPath).toSet();
    final newItems = entryPaths
        .where((e) => !existingInThisZip.contains(e))
        .map((e) => ZipClipboardItem(zipPath: zipPath, entryPath: e, isCut: isCut));
    state = [...updated, ...newItems];
  }

  /// Hapus entri tertentu dari [zipPath]. Dipanggil OTOMATIS oleh
  /// listener di atas (extract sukses) MAUPUN manual dari UI (X
  /// per-item).
  void removeEntries(String zipPath, List<String> entryPaths) {
    if (entryPaths.isEmpty || state.isEmpty) return;
    final toRemove = entryPaths.toSet();
    state = state.where((i) => !(i.zipPath == zipPath && toRemove.contains(i.entryPath))).toList();
  }

  void clear() => state = [];

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final zipClipboardProvider = StateNotifierProvider<ZipClipboardNotifier, List<ZipClipboardItem>>(
  (ref) {
    final eventBus = ref.watch(eventBusProvider);
    return ZipClipboardNotifier(eventBus);
  },
);
