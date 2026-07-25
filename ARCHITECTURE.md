# DalX — Architecture

Dokumen ini adalah acuan arsitektur DalX. Dibaca ulang tiap kali mulai
sub-fase baru atau lupa alasan di balik sebuah keputusan desain.

> **Status keseluruhan (per update ini):** Sub-Fase 0a, 0b, dan Fase
> 1–7 **SELESAI & TERUJI**. Perbaikan pra-Fase 8 (Thumbnail
> Generation, Storage Fix, Grid View tuning — lihat bagian 7.1)
> **SELESAI**. Fase 8: Pilar #1 (Preview PPT) & Pilar #2 (Compress
> Native, + Task Progress Banner) **SELESAI** — lihat bagian 7.2.
> Pilar #3 (Edit PDF) berikutnya. Fase 9 (Database Viewer) baru
> placeholder ide, belum dibahas scope-nya — lihat bagian 7.3.

## 1. Gambaran Umum

DalX adalah file manager Android yang dirancang menjadi "pusat komando"
untuk power user & developer — satu app menggantikan kombinasi file
manager + code editor + document viewer + archive tool.

**Prinsip inti:**
- Kecil & ringan — modular, fitur berat di-load on-demand
- Powerful tapi bukan bloated — tiap fitur harus benar-benar dipakai
- Developer-first — code editor & akses file tersembunyi adalah nilai
  jual utama

**Dibangun dari nol** memakai Flutter (bukan fork project GitHub).
Project open source lain (mis. Amaze File Manager, Material Files)
boleh dipelajari sebagai referensi arsitektur/logic, tidak pernah
sebagai basis kode.

## 2. Struktur Folder (kondisi terkini)

```
lib/
├── main.dart                    ← eksekutor: setup Riverpod, rute awal
│                                   (baca homePathProvider utk halaman
│                                   awal, handle intent dari app lain)
│
├── core/                         ← hal fundamental lintas fitur
│   ├── events/                   ← Event System (bus + katalog event)
│   │   └── event_bus.dart        ← whereEventType<T>() extension custom
│   ├── permissions/               ← Permission Manager
│   ├── models/                   ← FileItem (isImage/isVideo/isCodeFile/
│   │                                isArchive/isPdf/isSpreadsheet, dst)
│   ├── storage_access/            ← StorageAccess, storageAccessProvider
│   │                                (deteksi SD Card/USB OTG real-time)
│   ├── device_info/                ← StatFs + ActivityManager asli (RAM,
│   │                                kapasitas storage)
│   ├── settings/                  ← app_settings.dart: themeModeProvider,
│   │                                localeProvider, explorerDefaultsProvider,
│   │                                fontScaleProvider, homePathProvider,
│   │                                RootModeNotifier/rootModeProvider
│   ├── cache/                      ← cache_manager.dart (getCacheSize/
│   │                                clearCache, cache dir app doang)
│   ├── localization/                ← app_strings.dart (AppStrings.of(context),
│   │                                pure Dart, bukan gen-l10n/.arb)
│   ├── intent_bridge/                ← routing intent dari app lain
│   └── native_bridge/               ← NativeBridge.dart & .kt (method
│                                    channel ke MainActivity.kt)
│
└── features/                     ← satu folder = satu fitur/menu
    ├── file_engine/                ← Copy/Move/Delete/Rename/New Folder
    ├── explorer_ui/                ← List/Grid, breadcrumb, search, sort,
    │                                action mode, drawer, pick mode,
    │                                thumbnail_tile.dart (lihat 7.1)
    ├── storage_overview/            ← "Layar Awal" default, kartu
    │                                Internal/SD/USB + RAM real-time
    ├── task_queue/                  ← DalXTask model, TaskType, ConflictStrategy,
    │                                task_progress_banner.dart (lihat 7.2)
    ├── favorites/                    ← favorites_service.dart (persist
    │                                SharedPreferences), favorites_screen.dart
    ├── settings/                     ← settings_screen.dart
    ├── media_viewer/                  ← ImageViewerScreen, VideoViewerScreen
    ├── code_editor/                   ← code_editor_screen.dart (re_editor),
    │                                language_detector.dart
    ├── archive/                       ← compress/extract ZIP+tar/tar.gz (Dart,
    │                                task_queue yang eksekusi) + 7z/RAR (native,
    │                                lihat 7.2) — SEMUA lewat task_queue.dart,
    │                                bukan folder archive/ terpisah secara fisik
    ├── doc_viewer/                     ← pdf_viewer_screen.dart, xlsx_editor_screen.dart
    ├── ppt_viewer/                     ← pptx_parser.dart, ppt_viewer_screen.dart
    │                                (Fase 8 Pilar #1, SELESAI — lihat 7.2)
    │
    │   ─── BELUM DIIMPLEMENTASI ───
    ├── pdf_editor/                     (rencana: rotate/split/merge/reorder,
    │                                Fase 8 Pilar #3, lihat bagian 7.2)
    └── db_viewer/                      (rencana: Fase 9, lihat bagian 7.3 —
                                        ide awal, scope belum dibahas)
```

## 3. Aturan Komunikasi Antar Modul

**Modul di `features/` DILARANG saling memanggil langsung.**
Semua komunikasi antar modul WAJIB lewat Event System (`core/events`).

```
❌ SALAH
file_engine memanggil fungsi di explorer_ui secara langsung

✅ BENAR
file_engine memicu event FolderOpened lewat core/events
explorer_ui mendengarkan event tersebut, lalu update tampilannya sendiri
```

**Kenapa disiplin ini penting:** kalau `file_engine` manggil `explorer_ui`
langsung, begitu ada fitur baru yang juga perlu tahu "folder dibuka"
(misal `code_editor`), kode `file_engine` harus diedit lagi untuk
manggil modul baru itu juga. Dengan event, `file_engine` cukup teriak
sekali — siapa pun yang mau dengar tinggal daftar sendiri.

`core/` bukan tempat "class besar dipakai bareng-bareng secara
langsung" — dia jembatan/kerangka fundamental (Event System, Permission,
SAF, model data) yang semua modul boleh pakai tanpa perlu kenal modul
lain secara langsung.

**Godaan yang harus dihindari:** "ah ini kan cuma sekali, panggil
langsung aja" — sekali pengecualian ini dibuat, disiplin arsitektur
bocor dan lama-lama rusak dari dalam.

**Pengecualian yang sudah disepakati:** provider Riverpod yang berupa
`.family` (mis. `fileEngineProvider`, `explorerProvider`) BUKAN
pelanggaran aturan ini — itu soal scoping state per-instance
(lihat bagian 8), bukan komunikasi lintas modul.

## 4. Katalog Event (kondisi terkini)

Daftar lengkap & komentar detail ada di kode:
`core/events/event_catalog.dart`. Ringkasan di sini untuk referensi
cepat tanpa buka kode.

| Event | Dipicu saat | Dipakai oleh |
|---|---|---|
| `FolderOpened` | User membuka folder tertentu | explorer_ui, breadcrumb |
| `StorageMounted` | Storage device (SD Card/USB OTG) terpasang | storage_overview, drawer |
| `FileCreated` | File/folder baru dibuat (New Folder/New File) | explorer_ui, media_scanner |
| `FileDeleted` | File/folder dihapus (lewat Task Queue) | explorer_ui |
| `FileRenamed` | File/folder di-rename | explorer_ui |
| `FileMoved` | File/folder dipindah (Cut-Paste, Task Queue) | explorer_ui, media_scanner |
| `FileCopied` | File/folder disalin (Copy-Paste, Task Queue) | explorer_ui, media_scanner |
| `TaskProgress` | Progress task berjalan (update berkala) | task_queue UI |
| `TaskCompleted` | Task selesai (sukses/gagal) | task_queue UI, explorer_ui |
| `ExternalFileOpened` | DalX dibuka dari luar via file (Open With / Share) | explorer_ui |
| `ApkInstallRequested` | User pilih Install APK dari Explorer | native_bridge |
| `CacheCleared` | "Bersihkan Cache" (drawer) selesai hapus isi cache disk | explorer_ui (thumbnail_tile.dart, hapus cache in-memory) |

Belum diimplementasikan, dicatat sebagai cakupan Fase 8:
- `StorageRemoved` (kebalikan `StorageMounted`) — relevan begitu USB
  OTG penuh dikerjakan.

## 5. Struktur Navigasi (hasil desain UI/UX, sudah terimplementasi)

**Sidebar drawer** (dibuka lewat hamburger icon di Toolbar), berisi:
Layar Awal, Internal Storage, SD Card, USB OTG, Favorites, Task Queue,
Bersihkan Cache (aksi langsung), Settings, About.

- **Layar Awal** — path dinamis (`homePathProvider`), default ke
  `StorageOverviewScreen`, bisa diarahkan ke folder lain lewat
  Settings. Satu-satunya entri drawer menuju overview tersebut —
  tidak ada entri "Home" terpisah.
- **Bersihkan Cache** — begitu di-tap langsung eksekusi
  `CacheManager.clearCache()`, bukan submenu/halaman terpisah. Hanya
  membersihkan cache dir app, bukan thumbnail (DalX belum generate
  thumbnail gambar/video — di luar scope sampai saat ini).
- **Task Queue** — layar tersendiri, diakses dari drawer.

**Toolbar Explorer:** Hamburger, Judul Folder, Search, Menu (titik tiga,
dropdown menempel di bawah tombol). Isi menu: Folder Baru, File Baru,
Tampilkan/Sembunyikan File Tersembunyi, Tampilan List/Grid.

**Action mode toolbar** (multi-select aktif), urutan kiri ke kanan:
Trash, Copy, Cut, Rename, titik tiga (Share, File Info).

**Grid View:** `crossAxisCount` 5, `childAspectRatio` 0.78. Belum ada
thumbnail gambar/video asli — masih icon generik per tipe file.

**Sort Mode:** Name, Size (1 arah), Date dipecah jadi `dateNewest` &
`dateOldest` (2 arah terpisah).

**Root Mode (toggle manual di Settings, default OFF):** menentukan
perilaku tombol back begitu history navigasi Explorer habis.
- OFF → kembali ke Layar Awal (`Navigator.pushAndRemoveUntil`,
  bersihkan seluruh back-stack).
- ON → naik ke folder induk asli filesystem (`FileEngine.goToParent()`)
  sampai mentok root `/`, baru pop/exit biasa.

**Warna aksen:** satu warna solid `#0A84FF` untuk semua elemen UI
fungsional. Gradient (`#0A84FF` → `#00C6FF`) khusus branding/logo.

## 6. Settings (isi final, terimplementasi)

**Tampilan Aplikasi:** Theme (dark/light/system), Language (id/en)
**Explorer:** Default View, Default Sort, Hidden File Default, Font
Size (skala teks list file doang, bukan seluruh app), Layar Awal
(path picker)
**Root Mode:** toggle manual, default OFF (lihat bagian 5)
**Tentang:** Version info, link ke About

Catatan: "Konfirmasi sebelum Hapus" WAJIB aktif secara default dan
tidak muncul di Settings sama sekali — perilaku baku di balik layar,
bukan preferensi yang bisa dimatikan atau bahkan dilihat user.

**Localization:** infrastruktur `AppStrings` (pure Dart, lewat
`Localizations`/`LocalizationsDelegate` bawaan Flutter, bukan
gen-l10n/.arb) sudah terpasang penuh di: main, drawer, file info
sheet, task queue, explorer, settings. Belum disentuh (tinggal
bertahap): code editor, xlsx editor, pdf viewer, image/video viewer,
favorites, storage overview, folder picker.

## 7. Roadmap Sub-Fase

**Sub-Fase 0a — Kerangka Hidup** ✅ SELESAI & TERUJI
Event System dasar, Permission Manager, SAF dasar, File Engine
Open/Close/Back/Refresh, Explorer List View + Breadcrumb, Storage
Overview minimal.

**Sub-Fase 0b — File Manager Fungsional** ✅ SELESAI & TERUJI
Copy/Move/Paste/Rename/Delete/New Folder, Task Queue penuh, Multi
Selection + action mode, Search, Sort, Show/Hide Hidden, Storage
Overview lengkap (SD/USB/RAM), File Information lengkap.

**Fase 1 — Android Integration Lanjutan** ✅ SELESAI & TERUJI
Document Picker, Open With (in & out — intent-filter `ACTION_VIEW`
sudah aktif di Manifest), Share Sheet, Install/Uninstall APK, Media
Scanner listener, Intent Handler.

**Fase 1.5 — Storage Access & Root Mode** ✅ SELESAI & TERUJI
*(di luar penomoran awal, ditambahkan di tengah jalan)*
Deteksi SD Card/USB OTG real-time, RAM real-time, Root Mode toggle.

**Fase 2 — Explorer Polish** ✅ SELESAI & TERUJI
Grid View, Favorites, Duplicate, New File.

**Fase 3 — Media Viewer** ✅ SELESAI & TERUJI
Preview foto (photo_view + PageView, swipe se-folder) & video
(video_player polos, kontrol custom).

**Fase 4 — Code Editor** ✅ SELESAI & TERUJI
Baca & edit banyak bahasa (re_editor + re_highlight), Cari/Ganti,
Select All, Indent/Outdent, Word Wrap, Undo/Redo, Save. File >3MB
read-only.

**Fase 5 — Archive** ✅ SELESAI & TERUJI
Compress/Extract ZIP (pure Dart, `package:archive`), resolusi konflik
nama (`ConflictStrategy`), semua lewat Task Queue.

**Fase 6 — Doc Viewer** ✅ SELESAI & TERUJI
Baca PDF (`flutter_pdfview`, scroll+zoom doang). Baca & tulis XLSX
(`package:excel` + `pluto_grid`, grid editable, multi-sheet).

**Fase 7 — Settings, Cache, Localization** ✅ SELESAI & TERUJI
Theme/Language/Font Size lengkap, Bersihkan Cache, localization
infrastruktur + sebagian besar layar utama sudah dilokalisasi
(lihat bagian 6), APK size optimization (minify + shrink + proguard,
split-per-abi).

## 7.1 Perbaikan Pra-Fase 8 (selesai)

Sebelum mulai Fase 8, 3 kekurangan yang ditemukan Damar dibereskan
dulu (item "Sapu Cache Semua App via Root Mode" SENGAJA di-skip,
bukan dikerjakan):

**A. Thumbnail Generation**
- Native (`NativeBridge.kt`, method `generateThumbnail`): gambar
  didecode pakai `inSampleSize` (downscale SAAT decode, bukan decode
  resolusi penuh baru resize — aman buat foto kamera puluhan MB),
  video pakai `MediaMetadataRetriever.getFrameAtTime()`. Semua jalan
  di **background thread** (bukan platform thread) supaya tidak
  freeze UI pas scroll cepat.
- Hasil JPEG disimpan di `cacheDir/thumbnails/` (native), key dari
  MD5 hash `path|modifiedAtMillis` — **idempotent** (cache hit
  langsung balik cepat tanpa decode ulang) dan otomatis "invalid"
  sendiri kalau file aslinya berubah, tanpa tracking manual.
- Dart (`thumbnail_tile.dart`, baru, di `features/explorer_ui/`):
  widget `DalxThumbnail` lazy-load + cache in-memory `Future` (biar
  method channel tidak dipanggil berulang pas `ListView`/`GridView`
  recycle widget saat scroll bolak-balik). Dipasang di List & Grid
  View (`explorer_screen.dart`), fallback ke icon generik selagi
  loading/gagal.
- `FileItem` dapat getter `isThumbnailable` (`isImage || isVideo`).

**B. Storage Discrepancy (DalX vs Settings Android vs CX File Manager)**
- Root cause: `totalBytes` dihitung dari `StatFs.blockCountLong`
  mentah, yang cuma menghitung block riil di partisi data (~10%
  lebih kecil dari kapasitas nominal chip karena overhead sistem/
  wear-leveling tidak masuk hitungan block filesystem biasa) —
  sedangkan Settings Android & CX baca dari sumber yang kembalikan
  kapasitas "resmi".
- Fix: `totalBytes` diganti ke **`StorageStatsManager.getTotalBytes()`**
  di 2 tempat — `MainActivity.kt` (`getStorageInfo`, Internal Storage,
  pakai `StorageManager.UUID_DEFAULT`) dan `NativeBridge.kt`
  (`getStorageCapacity`, SD Card/USB OTG, UUID dicari lewat
  `StorageManager.getUuidForPath()` dari path manapun). `freeBytes`
  tetap dari `StatFs` (sudah akurat). Ada fallback ke `StatFs` mentah
  kalau API gagal.
- Bug kedua (independen, cosmetic): format tampilan GB di
  `storage_overview_screen.dart` & `cache_manager.dart` pakai basis
  biner (`1024³`, GiB) tapi labelnya ditulis "GB" — diseragamkan ke
  basis desimal (`1000³`) supaya matching konvensi Settings/CX.
- Event baru `CacheCleared` (lihat bagian 4) ditambah karena
  `CacheManager` (plain class, tidak punya akses `eventBus`/`ref`)
  perlu cara ngasih tau `thumbnail_tile.dart` buat bersihin cache
  in-memory-nya begitu cache disk dibersihkan — dipicu dari
  `app_drawer.dart` (yang punya `ref`), BUKAN dari dalam
  `CacheManager` sendiri.

**C. Grid View — Ukuran & Kerapian (permintaan Damar, dibandingkan
langsung dengan CX File Manager lewat screenshot)**
- Icon dibesarkan 32px → 52px (kontainer 40×40 → 56×56), font nama
  file 10px → 13px, `childAspectRatio` disesuaikan 0.78 → 0.68.
- Bug alignment: `Column` isi tiap grid tile pakai
  `mainAxisAlignment.center` — nama file 1 baris vs 2 baris punya
  tinggi konten beda, jadi icon ikut kegeser naik-turun antar cell
  dalam baris yang sama (kelihatan "berantakan" walau urutan file-nya
  sebenarnya sudah benar/alfabetis, sama persis dengan CX). Fix:
  `mainAxisAlignment.start` + tinggi teks direserve TETAP (34px,
  cukup 2 baris) — posisi icon jadi selalu sama persis di semua cell.

## 7.2 Roadmap Fase 8 — Native Power-up

**Status: 🔧 SEDANG BERJALAN** — Pilar #1 & #2 **SELESAI**, Pilar #3
(Edit PDF) berikutnya.

Urutan pengerjaan (prioritas Damar):

1. **Preview PPT** ✅ SELESAI
   Buka `.pptx`, render tiap slide, swipe next/prev. **Preview doang
   — tidak ada edit** sama sekali. `features/ppt_viewer/`:
   `pptx_parser.dart` (parsing XML manual — belum ada package Flutter
   matang untuk `.pptx`, resolve urutan slide via `presentation.xml`
   + `.rels`, extract teks & gambar per shape dengan posisi relatif),
   `ppt_viewer_screen.dart` (`PageView`, render via `Stack`+
   `Positioned`+`LayoutBuilder`, parsing dijalankan lewat `compute()`
   supaya tidak blocking UI). Package baru: `xml: ^6.5.0`. Batasan
   disadari: chart/table/SmartArt/animasi tidak didukung, styling
   teks diabaikan, shape placeholder (posisi diwarisi Layout/Master)
   dilewati.

2. **Compress native** ✅ SELESAI (scope direvisi saat implementasi)
   - Approach: **Apache Commons Compress + XZ Java** (7z) + **junrar**
     (RAR, di-hosting JitPack — bukan Commons Compress, yang memang
     tidak pernah support RAR karena lisensi/patent), lewat JNI/
     Kotlin via `NativeBridge` — bukan libarchive/FFI.
   - **Revisi scope dari rencana awal**: TERNYATA tar/tar.gz TIDAK
     perlu native — `package:archive` (Dart, sudah dependency sejak
     Fase 5) sudah cukup (`TarDecoder`+`GZipDecoder`). Jadi native
     HANYA dipakai untuk **7z (compress+extract)** dan **RAR
     (extract doang)** — lebih kecil dari rencana awal, sejalan
     filosofi "ringan".
   - Compress (bikin arsip baru): **ZIP (Dart, tidak berubah) + 7z
     (native, baru)**. UI: `SegmentedButton` ZIP/7Z di dialog Compress.
   - Extract: **ZIP (Dart) + 7z (native) + RAR (native) + tar/tar.gz
     (Dart)** — auto-detect dari ekstensi file, tidak perlu pilihan
     manual user.
   - Level kompresi 7z: satu level default, tidak ada opsi atur.
   - Progress native dilaporkan via `EventChannel` baru
     `"com.dalx.app/archive_stream"` (bukan return value method call)
     — supaya real-time selama proses jalan, bukan lompat 0%->100%.
   - **Batasan disadari**: cancel/pause **TIDAK didukung** untuk 3
     operasi native (compress 7z, extract 7z, extract RAR) — loop-nya
     jalan di Kotlin, bukan Dart, jadi `_cancelFlags`/`_pauseFlags`
     Task Queue tidak ke-cek di situ. ZIP & tar/tar.gz (Dart) tetap
     bisa cancel/pause normal.
   - `TaskType`/`DalXTask` model **TIDAK berubah** — format archive
     cukup dibaca dari ekstensi file (destinationPath/sourcePaths),
     tidak perlu field baru.
   - Dependency baru: `android/app/build.gradle` (commons-compress,
     xz, junrar), `android/build.gradle` (repo JitPack buat junrar),
     `proguard-rules.pro` (dontwarn slf4j/brotli/zstd, keep
     commons-compress & junrar).

   **Tambahan di luar rencana awal — Task Progress Banner**: banner
   mengambang (`features/task_queue/task_progress_banner.dart`)
   dipasang lewat `MaterialApp.builder` di `main.dart` — muncul di
   layar MANA PUN selagi ada task `isActive`, non-blocking (user
   tetap bisa browsing sambil proses jalan). Tombol aksi beda
   tergantung task: Copy/Move/Delete/Compress-ZIP/Extract-ZIP/
   Extract-tar → "Batalkan" (beneran cancel); Compress-7z/Extract-7z/
   Extract-RAR → "Sembunyikan" (banner hilang, proses TETAP lanjut —
   jujur soal batasan cancel di atas, tidak menyesatkan user).

3. **Edit PDF** — BERIKUTNYA
   Scope: **Rotate / Split / Merge / Reorder halaman** — manipulasi
   struktur halaman saja. **Tidak termasuk** edit teks isi PDF atau
   anotasi (highlight/gambar) di iterasi ini.

4. **USB OTG penuh**
   - Approach: **SAF resmi saja** (Storage Access Framework standar
     Android) — **bukan** Root Mode dan **bukan** native USB host
     API.
   - Konsekuensi sadar: akses lewat document picker sistem (bukan
     browsing bebas seperti Internal Storage), tapi semua device
     kebagian tanpa syarat khusus (tidak perlu root).
   - `StorageRemoved` (kebalikan `StorageMounted`, lihat bagian 4)
     relevan mulai dikerjakan di sini.

   *(Root Mode sebagai jalur bonus untuk USB OTG di device yang
   sudah di-root, dan native USB host API sebagai riset masa depan —
   keduanya secara sadar DITUNDA, bukan bagian dari scope Fase 8
   saat ini.)*

## 7.3 Fase 9 — Database Viewer (placeholder, scope belum dibahas)

Ide dari Damar: kemampuan baca (dan mungkin nanti tulis) file
database dari Explorer — semacam DB Browser for SQLite versi ringan
(buka `.db`/`.sqlite`, lihat skema, browse isi tabel, mungkin run
query `SELECT`). SENGAJA dipisah dari Fase 8 ("Native Power-up")
karena kemungkinan besar **tidak butuh native sama sekali** —
`package:sqlite3` (binding Dart resmi ke SQLite engine) sudah matang,
beda dari kasus PPT yang kepaksa parsing manual. Dikerjakan SETELAH
Fase 8 tuntas (Pilar #3 & #4), scope detail (baca-only vs baca-tulis,
run query bebas vs browse-only, dst) belum dibahas — catatan ini
cuma placeholder supaya tidak lupa idenya.

## 8. Keputusan Teknis

| Aspek | Keputusan |
|---|---|
| Framework | Flutter (Dart) |
| State management | Riverpod. Provider `.family` dipakai untuk state yang perlu scoped per-instance (mis. `fileEngineProvider`, `explorerProvider` di-key oleh `rootPath` — bukan singleton global, supaya Internal Storage/SD Card/USB OTG/folder Root Mode tidak berbagi state navigasi) |
| Minimum SDK | Android 11 / SDK 30 |
| compileSdk | 35 (dinaikkan dari 34 karena `video_player_android` narik androidx.media3 1.5.1) |
| AGP | 8.6.1 (dinaikkan dari 8.3.2 karena dependency `flutter_pdfview`/`pluto_grid`/`excel` narik androidx.core-ktx 1.16.0) |
| Gradle wrapper | 8.7 (syarat minimal untuk AGP 8.6) |
| Kotlin | 2.0.21 |
| Nama app | DalX |
| Package name | `com.dalx.app` (huruf kecil semua) |
| Arsitektur | Modular, komunikasi antar modul hanya lewat Event System |
| Localization | Custom `AppStrings` pure Dart via `Localizations`/`LocalizationsDelegate` bawaan Flutter — bukan `flutter gen-l10n`/`.arb`, supaya tidak ada code-gen step tambahan di CI |
| Compress/Archive (Fase 5) | `package:archive` pure Dart, ZIP saja |
| Compress/Archive (Fase 8, rencana) | Apache Commons Compress + XZ Java via JNI/Kotlin (`NativeBridge`) — bukan libarchive/FFI |
| Thumbnail generation | Native (Kotlin, background thread) — bukan pakai `ContentResolver.loadThumbnail()` (cuma jalan untuk file yang ter-index MediaStore, banyak file relevan buat power user DalX ada di luar situ). Cache disk key: MD5 `path\|modifiedAtMillis`, idempotent |
| Total storage (Internal/SD/USB) | `StorageStatsManager.getTotalBytes()` — bukan `StatFs.blockCountLong` mentah (lebih kecil ~10% dari kapasitas nominal, tidak matching Settings Android/CX File Manager) |
| Format ukuran (GB/MB ditampilkan ke user) | Basis desimal (`1000³`/`1000²`) — bukan biner (`1024³`, GiB) berlabel salah "GB" |
| APK size | `minifyEnabled` + `shrinkResources` + ProGuard aktif; split-per-ABI WAJIB lewat flag CLI `flutter build apk --split-per-abi` di workflow, bukan `splits{abi{}}` manual di `build.gradle` (konflik dengan abiFilters otomatis Flutter Gradle Plugin versi baru) |
| Workflow build | Develop di Termux (Android), build APK via GitHub Actions (Flutter 3.29.3) — mengikuti pola project TaniLog |
