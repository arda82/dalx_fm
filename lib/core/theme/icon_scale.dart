// core/theme/icon_scale.dart
//
// Sumber tunggal untuk ukuran ikon di seluruh DalX. Dibuat karena
// sebelumnya tiap tempat pasang angka sendiri-sendiri (list tile
// leading tanpa size eksplisit ~24, thumbnail 40x40 radius 4,
// _MenuRow icon size 18, _ClipboardBarButton icon size 24, drawer
// tile default ~24) — hasilnya baris file/folder, drawer, dan menu
// titik tiga kelihatan tidak serasi satu sama lain, dan yang paling
// parah: TIDAK IKUT Settings > Font Size sama sekali (cuma teks yang
// ikut fontScaleProvider, ikon selalu ukuran tetap).
//
// Patokan angka "Sedang" (fontScale 1.0) diambil dari kotak logo D
// di header AppDrawer yang sudah lebih dulu ada (34x34, radius 9) —
// supaya file/folder tile di Explorer terasa satu keluarga visual
// dengan branding DalX sendiri, bukan angka baru yang asing.
//
// --- Dua kategori ikon ---
// 1. BOXED  — ikon file/folder di Explorer (List & Grid View) DAN
//    slot thumbnail (APK/foto/video). Selalu dibungkus wadah
//    rounded-square supaya ikon tipis (PDF/JSON/XLSX dll) punya
//    bobot visual yang setara dengan thumbnail asli yang padat warna
//    — lihat mockup "Sesudah" yang sudah disetujui.
// 2. STANDALONE — ikon polos tanpa wadah: drawer, dropdown menu
//    titik tiga (_MenuRow), tombol clipboard bar. Sebelumnya
//    ukurannya beda-beda (18/24/24 tanpa alasan) — sekarang satu
//    angka dasar yang sama, supaya "selaras" antar tempat.
//
// Kedua kategori sama-sama dikalikan fontScaleProvider — jadi pas
// user pilih Kecil/Sedang/Besar/Ekstra Besar di Settings, folder,
// ikon file, ikon drawer, dan ikon menu titik tiga ikut membesar/
// mengecil bersamaan, bukan cuma teksnya.

import 'package:flutter/material.dart';

/// ===== BOXED (Explorer file/folder tile + thumbnail slot) =====
/// Angka dasar di fontScale 1.0 ("Sedang") — SAMA PERSIS dengan
/// kotak logo D di AppDrawer header.
const double kIconBoxBaseSize = 34;
const double kIconBoxBaseRadius = 9;
const double kIconGlyphBaseSize = 19;

/// ===== STANDALONE (drawer tile, more-menu row, clipboard bar) =====
/// Satu angka dasar yang sama dipakai di ketiga tempat itu — dulu
/// masing-masing pasang ukuran sendiri (18/24/24), sekarang selaras.
const double kStandaloneIconBaseSize = 22;

double iconBoxSize(double fontScale) => kIconBoxBaseSize * fontScale;
double iconBoxRadius(double fontScale) => kIconBoxBaseRadius * fontScale;
double iconGlyphSize(double fontScale) => kIconGlyphBaseSize * fontScale;
double standaloneIconSize(double fontScale) => kStandaloneIconBaseSize * fontScale;

/// Proporsi tetap radius:wadah dan glyph:wadah dari patokan List View
/// (9/34 dan 19/34) — dipakai supaya wadah yang lebih besar (mis. Grid
/// View 56dp) tetap "satu keluarga" bentuknya dengan wadah List View,
/// bukan angka radius/glyph baru yang lepas dari patokan.
const double kIconBoxRadiusRatio = kIconBoxBaseRadius / kIconBoxBaseSize;
const double kIconGlyphSizeRatio = kIconGlyphBaseSize / kIconBoxBaseSize;

/// Warna latar wadah ikon (folder/file yang bukan thumbnail asli).
/// Sengaja abu sangat muda/putih transparan tipis — bukan warna baru,
/// masih di bawah 5% area layar sesuai guideline "Function First,
/// Color Last": ini cuma wadah netral, bukan penanda kategori warna.
Color iconBoxBackground(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F4F8);
}
