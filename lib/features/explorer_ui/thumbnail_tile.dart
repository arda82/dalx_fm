// features/explorer_ui/thumbnail_tile.dart
//
// Widget thumbnail lazy untuk List & Grid View — dipakai buat item
// yang FileItem.isThumbnailable (gambar/video). Ini bagian dari
// perbaikan "kekurangan" sebelum Fase 8: sebelumnya Grid/List View
// cuma nampilin icon generik per tipe file, sekarang bisa nampilin
// thumbnail asli.
//
// Generate & cache disk thumbnail-nya sepenuhnya dilakukan native
// (lihat NativeBridge.kt generateThumbnail, cache dir DalX sendiri —
// ikut kesapu "Bersihkan Cache" drawer karena satu lokasi). Widget
// ini cuma tanggung jawab lazy-load & tampilan sisi Dart.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/models/file_item.dart';
import '../../core/native_bridge/native_bridge.dart';

/// Cache in-memory (BUKAN persist, hilang begitu app di-kill) supaya
/// method channel generateThumbnail cuma dipanggil SEKALI per file
/// selama app masih hidup, walau widget-nya di-dispose/rebuild
/// berkali-kali gara-gara ListView/GridView.builder recycle widget
/// pas di-scroll bolak-balik. Thumbnail hasil generate sendiri sudah
/// persist di cache disk native — ini cuma cache Future-nya di
/// memory Dart.
final Map<String, Future<String?>> _thumbnailFutureCache = {};

/// Dipanggil dari CacheManager.clearCache() lewat "Bersihkan Cache" —
/// begitu file thumbnail di disk ikut kehapus, cache Future in-memory
/// ini WAJIB ikut dikosongkan juga. Kalau tidak, thumbnail lama yang
/// sudah pernah di-resolve bakal terus dipakai dari memory (path-nya
/// masih "sukses" menunjuk ke file yang sudah tidak ada) sampai app
/// di-restart.
void clearThumbnailMemoryCache() {
  _thumbnailFutureCache.clear();
}

/// Aktifin auto-clear cache in-memory begitu event [CacheCleared]
/// kedengeran (dipicu app_drawer.dart pas "Bersihkan Cache" sukses).
///
/// Provider biasa (BUKAN autoDispose/keepAlive) cuma "hidup" selama
/// ada widget yang nge-watch-nya — makanya di-watch dari
/// ExplorerScreen.build() (lihat explorer_screen.dart), bukan cuma
/// didefinisikan di sini. Dipilih ExplorerScreen karena di situlah
/// DalxThumbnail dipakai (List & Grid View), jadi selama ada layar
/// Explorer terbuka, listener ini otomatis aktif.
final thumbnailCacheClearListenerProvider = Provider<void>((ref) {
  final bus = ref.watch(eventBusProvider);
  final subscription = bus.stream.whereEventType<CacheCleared>().listen(
        (_) => clearThumbnailMemoryCache(),
      );
  ref.onDispose(subscription.cancel);
});

/// Widget thumbnail lazy: tampilkan [fallback] dulu (icon generik),
/// baru swap ke gambar/frame video asli begitu native selesai
/// generate atau ambil dari cache disk. Cuma dipanggil untuk item
/// yang [FileItem.isThumbnailable] — pemanggil wajib cek itu duluan,
/// widget ini tidak cek ulang.
class DalxThumbnail extends ConsumerWidget {
  final FileItem item;
  final Widget fallback;
  final BoxFit fit;

  const DalxThumbnail({
    super.key,
    required this.item,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheKey = '${item.path}|${item.modifiedAt.millisecondsSinceEpoch}';
    final future = _thumbnailFutureCache.putIfAbsent(
      cacheKey,
      () => ref.read(nativeBridgeProvider).generateThumbnail(
            item.path,
            modifiedAtMillis: item.modifiedAt.millisecondsSinceEpoch,
            isVideo: item.isVideo,
          ),
    );

    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final thumbPath = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || thumbPath == null) {
          return fallback;
        }
        return Image.file(
          File(thumbPath),
          fit: fit,
          // gaplessPlayback: hindari flicker balik ke kosong pas
          // widget rebuild (mis. Grid/List rebuild karena state lain
          // berubah) padahal gambar sebelumnya sudah pernah tampil.
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        );
      },
    );
  }
}
