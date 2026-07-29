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
import '../../core/settings/app_settings.dart';
import '../../core/theme/icon_scale.dart';

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
            isApk: item.isApk,
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

/// Ikon file/folder BOXED dipakai di List & Grid View — satu wadah
/// rounded-square yang sama persis buat SEMUA tipe (folder, ikon
/// dokumen tipis, maupun thumbnail asli APK/foto/video), supaya
/// tidak ada lagi ikon yang kelihatan "tenggelam" (PDF/JSON kecil
/// tipis) di sebelah ikon yang "berat" (thumbnail APK/foto penuh
/// warna) — lihat mockup icon-size-mockup.html bagian "Sesudah".
///
/// Ukurannya IKUT fontScaleProvider (Settings > Font Size): di
/// "Sedang" wadahnya 34x34/radius 9/glyph 19 (sama persis kotak logo
/// D di AppDrawer header), di "Kecil"/"Besar"/"Ekstra Besar" ikut
/// naik-turun proporsional lewat helper di core/theme/icon_scale.dart
/// — bukan angka tetap kayak sebelumnya.
class DalxFileIcon extends ConsumerWidget {
  final FileItem item;
  final IconData icon;

  /// Warna aksen kalau item folder (dalxAccent) — null buat file
  /// biasa (pakai warna abu default dari tema).
  final Color? accentColor;

  /// Ukuran dasar wadah SEBELUM dikali fontScale. Default
  /// kIconBoxBaseSize (34, patokan List View). Grid View pakai wadah
  /// lebih besar (mis. 56) — radius & glyph dihitung tetap dari rasio
  /// yang sama (kIconBoxRadiusRatio/kIconGlyphSizeRatio) supaya
  /// bentuknya selaras dengan List View, bukan wadah baru yang lepas.
  final double boxBaseSize;

  const DalxFileIcon({
    super.key,
    required this.item,
    required this.icon,
    this.accentColor,
    this.boxBaseSize = kIconBoxBaseSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontScaleProvider);
    final boxSize = boxBaseSize * fontScale;
    final radius = boxBaseSize * kIconBoxRadiusRatio * fontScale;
    final glyphSize = boxBaseSize * kIconGlyphSizeRatio * fontScale;

    final fallbackBox = _plainBox(context, boxSize, radius, glyphSize);

    if (item.isThumbnailable) {
      // Thumbnail asli (APK/foto/video) dipangkas pas ke wadah yang
      // SAMA ukurannya dengan ikon dokumen biasa — sebelumnya
      // thumbnail selalu 40x40 radius 4 tetap, tidak pernah selaras
      // dengan ikon lain dan tidak ikut Font Size sama sekali.
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: boxSize,
          height: boxSize,
          child: DalxThumbnail(
            item: item,
            fit: BoxFit.cover,
            fallback: fallbackBox,
          ),
        ),
      );
    }

    return fallbackBox;
  }

  Widget _plainBox(BuildContext context, double boxSize, double radius, double glyphSize) {
    return Container(
      width: boxSize,
      height: boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: iconBoxBackground(context),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        icon,
        size: glyphSize,
        color: accentColor ?? Colors.grey,
      ),
    );
  }
}
