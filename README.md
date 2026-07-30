# DalX

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

File manager Android buat power user & developer — dibangun dari nol
pakai Flutter, bukan fork project lain. Satu app buat gantiin
kombinasi file manager + code editor + document viewer + archive
tool.

> Package: `com.dalx.app` · Min SDK 30 (Android 11+) · Dikembangin
> full lewat Termux (tanpa komputer/USB), build via GitHub Actions.

---

## Kenapa DalX?

Kebanyakan file manager Android itu dua ekstrem: bawaan HP yang
kelewat terbatas, atau "power" file manager yang penuh fitur gak
kepake sampai berat & ribet. DalX dirancang di tengah — kecil &
ringan, tapi gak ketinggalan buat kerjaan teknis harian.

---

## Fitur

### File Management
- Copy, Move, Rename, Delete, New Folder/File, Duplicate — semua
  lewat Task Queue (async, ada progress, bisa pause/resume/cancel*)
- Clipboard Copy/Cut **lintas storage root** (Internal ↔ SD Card ↔
  USB OTG)
- Multi-selection dengan action mode toolbar
- List View & Grid View, Sort per-folder, Show/Hide Hidden Files
- Search, Favorites
- Font Size app-wide (Kecil/Sedang/Besar/Sangat Besar — ikon ikut
  scale juga)

### Viewer & Editor
- Code Editor dengan syntax highlighting (py/java/kotlin/dart/js/dll)
- PDF Viewer
- XLSX Viewer & Editor
- PPT Viewer (parsing manual dari XML, tanpa library native berat)
- Image, Video, Audio Viewer
- Database (.db/.sqlite) Viewer

### Archive
- Compress/Extract ZIP, TAR, TAR.GZ (pure Dart)
- Compress 7Z & Extract RAR (native Kotlin — Apache Commons Compress
  + XZ Java + junrar), dengan progress real-time

### Storage
- Overview Internal Storage, SD Card, USB OTG, RAM
- Thumbnail generation native (foto/video), di-cache
- Dukungan SD Card & USB OTG (baca/tulis dasar; lihat keterbatasan)

### Android Integration
- Share Sheet, Open With, Install/Uninstall APK
- Muncul di system chooser lewat `ACTION_VIEW` intent-filter
- Storage size ngikutin cara hitung Android Settings

### Lainnya
- Bahasa Indonesia (localization custom, tanpa `flutter gen-l10n`)
- Tema warna aksen konsisten satu warna solid di seluruh UI

\* lihat bagian Keterbatasan di bawah.

---

## Keterbatasan yang Disadari

Bagian ini sengaja ditulis eksplisit — beberapa hal di bawah **bukan
bug**, tapi batasan yang sudah diriset & diputuskan, biar gak
diinvestigasi ulang di kemudian hari.

- **`Android/data` & `Android/obb` gak bisa ditampilin isinya** — ini
  batasan level OS sejak Android 11, berlaku ke semua file manager
  non-root (yang lain cuma nyintesis nama folder dari
  `PackageManager`, bukan `readdir()` beneran). DalX nampilin notice
  informatif, bukan folder kosong yang menyesatkan.
- **Cancel/Pause gak jalan buat operasi native 7Z/RAR** — loop
  eksekusinya jalan di Kotlin, bukan Dart, jadi belum bisa
  diinterupsi dari sisi Flutter. ZIP/TAR/TAR.GZ (pure Dart) gak kena
  batasan ini.
- **Root Explorer belum ada** — semua fitur di atas jalan tanpa root.
  Akses `su` shell-out di luar cakupan versi sekarang.
- **USB OTG belum diuji penuh** — dukungan dasar ada, tapi belum
  ditest menyeluruh buat semua skenario copy/paste lintas storage
  (khususnya OTG ↔ Internal/SD Card).
- **Localization belum 100% merata** — beberapa layar (code editor,
  xlsx editor, pdf viewer, image/video viewer, dll) masih ada string
  hardcoded, infrastruktur udah siap tinggal diterapin bertahap.
- **PDF/PPT baru bisa preview, belum bisa edit** — masuk roadmap Fase
  8 lanjutan.

---

## Tech Stack

| | |
|---|---|
| Framework | Flutter 3.29.3 |
| State management | Riverpod |
| Android Gradle Plugin | 8.6.1 |
| Kotlin | 2.0.21 |
| Gradle | 8.7 |
| Min SDK | 30 (Android 11) |
| Compile SDK | 35 |

**Native (Kotlin):** Apache Commons Compress 1.26.2, XZ Java 1.9,
junrar 7.5.5, `StorageStatsManager`, `MediaMetadataRetriever`,
`BitmapFactory`

**Flutter packages:** `riverpod`, `package:archive`, `package:xml`,
`share_plus`, `photo_view`, `video_player`, `re_editor`/`re_highlight`,
`flutter_pdfview`, `package:excel`, `pluto_grid`, `path_provider`,
`shared_preferences`

---

## Build & Install

DalX dikembangin sepenuhnya di Termux (Android), tanpa komputer/USB.
Build APK-nya lewat GitHub Actions, bukan `flutter run` lokal.

1. Push perubahan ke branch yang di-watch workflow.
2. GitHub Actions build APK (termasuk split-per-ABI).
3. Download APK hasil build dari Actions artifact.
4. Install manual (sideload) di device — `Unknown Sources` harus
   diizinkan buat source installer yang dipakai.

Belum ada rilis via Play Store / F-Droid — murni sideload buat
sekarang.

---

## Arsitektur

Struktur folder, aturan komunikasi antar modul (Event System), dan
katalog event lengkap ada di [`ARCHITECTURE.md`](./ARCHITECTURE.md).

Prinsip inti: `core/` gak boleh depend ke `features/`, dan modul di
`features/` gak boleh saling panggil langsung — semua lewat Event
System.

---

## Status

Development aktif, saat ini di **Fase 8 — Native Power-up**
(compress native 7Z/RAR, PPT preview selesai; PDF/PPT editing & USB
OTG penuh masih berjalan).

---

## Lisensi

MIT — lihat [`LICENSE`](./LICENSE).
