# DalX — Architecture

Dokumen ini adalah acuan arsitektur DalX. Dibaca ulang tiap kali mulai
sub-fase baru atau lupa alasan di balik sebuah keputusan desain.

> **Status keseluruhan (per update ini):** Sub-Fase 0a, 0b, dan Fase
> 1–7 **SELESAI & TERUJI**. Fase 8 sedang di tahap perencanaan scope
> (lihat bagian 7).

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
    │                                action mode, drawer, pick mode
    ├── storage_overview/            ← "Layar Awal" default, kartu
    │                                Internal/SD/USB + RAM real-time
    ├── task_queue/                  ← DalXTask model, TaskType, ConflictStrategy
    ├── favorites/                    ← favorites_service.dart (persist
    │                                SharedPreferences), favorites_screen.dart
    ├── settings/                     ← settings_screen.dart
    ├── media_viewer/                  ← ImageViewerScreen, VideoViewerScreen
    ├── code_editor/                   ← code_editor_screen.dart (re_editor),
    │                                language_detector.dart
    ├── archive/                       ← compress/extract ZIP (task_queue
    │                                yang eksekusi, lewat package archive)
    ├── doc_viewer/                     ← pdf_viewer_screen.dart, xlsx_editor_screen.dart
    │
    │   ─── BELUM DIIMPLEMENTASI (Fase 8, lihat bagian 7) ───
    ├── ppt_viewer/                     (rencana: preview .pptx)
    ├── pdf_editor/                     (rencana: rotate/split/merge/reorder)
    └── (compress native masuk ke archive/ yang sudah ada, bukan folder baru)
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

**Fase 8 — Native Power-up** 🔧 SCOPE DIKUNCI, BELUM DIKERJAKAN

Urutan pengerjaan (prioritas Damar):

1. **Preview PPT**
   Buka `.pptx`, render tiap slide, swipe next/prev. **Preview doang
   — tidak ada edit** sama sekali di iterasi ini. Fondasi dari nol
   (belum ada modul terkait di project). Kendala utama: belum ada
   package Flutter yang matang untuk parsing `.pptx` (format ZIP+XML)
   — kemungkinan besar perlu parsing XML manual, resiko lebih tinggi
   dari yang kelihatan sekilas.

2. **Compress native**
   - Approach: **Apache Commons Compress + XZ Java**, lewat JNI/
     Kotlin via `NativeBridge` (pola sama seperti fitur native lain
     yang sudah ada) — **BUKAN** libarchive/FFI, supaya tidak perlu
     cross-compile native `.so` per-ABI dan tetap ringan di CI &
     ukuran APK.
   - Compress (bikin arsip baru): **ZIP + 7z**.
   - Extract (buka arsip orang lain): **ZIP + 7z + RAR + tar/tar.gz**
     (RAR extract-nya butuh library Kotlin pure-Java terpisah, belum
     dipilih — RAR encoder proprietary sehingga compress-ke-RAR
     TIDAK masuk scope, sesuai lazimnya file manager lain).
   - Level kompresi 7z: **satu level default (normal)**, tidak ada
     opsi atur level di iterasi ini — konsisten dengan compress ZIP
     yang sudah ada sekarang.
   - Task type baru: kemungkinan `TaskType.compressNative` /
     eksekusi tetap lewat Task Queue yang sudah ada, bukan jalur baru.

3. **Edit PDF**
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
| APK size | `minifyEnabled` + `shrinkResources` + ProGuard aktif; split-per-ABI WAJIB lewat flag CLI `flutter build apk --split-per-abi` di workflow, bukan `splits{abi{}}` manual di `build.gradle` (konflik dengan abiFilters otomatis Flutter Gradle Plugin versi baru) |
| Workflow build | Develop di Termux (Android), build APK via GitHub Actions (Flutter 3.29.3) — mengikuti pola project TaniLog |
