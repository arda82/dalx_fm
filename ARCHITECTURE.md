# DalX — Architecture

Dokumen ini adalah acuan arsitektur DalX. Dibaca ulang tiap kali mulai
sub-fase baru atau lupa alasan di balik sebuah keputusan desain.

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

## 2. Struktur Folder

```
lib/
├── main.dart                    ← eksekutor: setup Riverpod, halaman awal
│
├── core/                        ← hal fundamental lintas fitur
│   ├── events/                  ← Event System (bus + katalog event)
│   ├── permissions/             ← Permission Manager
│   ├── storage_access/          ← SAF wrapper
│   └── models/                  ← model data bersama (FileItem, dll)
│
└── features/                    ← satu folder = satu fitur/menu
    ├── file_engine/
    ├── explorer_ui/
    ├── storage_overview/        ← layar "Home" (default screen)
    ├── task_queue/
    ├── settings/
    ├── code_editor/             (menyusul — Fase 4)
    ├── media_viewer/            (menyusul — Fase 3)
    └── archive/                 (menyusul — Fase 5)
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

## 4. Katalog Event

Daftar lengkap ada di kode: `core/events/event_catalog.dart`. Ringkasan
di sini untuk referensi cepat tanpa buka kode.

| Event | Dipicu saat | Dipakai oleh |
|---|---|---|
| `FolderOpened` | User membuka folder tertentu | explorer_ui, breadcrumb |
| `StorageMounted` | Storage device (SD Card/USB OTG) terpasang | storage_overview, drawer |

Event baru untuk Sub-Fase 0b dan seterusnya (FileDeleted, FileMoved,
FileRenamed, StorageRemoved, dll) akan ditambahkan ke tabel ini begitu
sub-fase terkait mulai dikerjakan — supaya tabel ini selalu jadi
sumber kebenaran terkini, bukan didesain di muka sebelum ada
"pelanggan" nyata.

## 5. Struktur Navigasi (hasil desain UI/UX)

**Sidebar drawer** (dibuka lewat hamburger icon di Toolbar), berisi:
Layar Awal, Internal Storage, SD Card, USB OTG, Favorites, Task Queue,
Bersihkan Cache (aksi langsung), Settings, About.

- **Layar Awal** — path dinamis, default ke layar overview Storage+RAM
  ("Home" secara konsep), bisa diarahkan ke folder lain lewat
  Settings. Ini satu-satunya entri drawer menuju overview tersebut —
  tidak ada entri "Home" terpisah.
- **Bersihkan Cache** — begitu di-tap langsung eksekusi pembersihan,
  bukan submenu/halaman terpisah.
- **Task Queue** — layar tersendiri, diakses dari drawer (bukan lagi
  icon indicator di Toolbar).

**Toolbar Explorer:** Hamburger, Judul Folder, Search, Menu (titik tiga).
Menu titik tiga (dropdown, menempel di bawah tombol, bukan bottom
sheet) berisi: Folder Baru, File Baru, Tampilkan/Sembunyikan File
Tersembunyi, Tampilan List/Grid.

**Action mode toolbar** (saat multi-select aktif), urutan kiri ke kanan:
Trash, Copy, Cut, Rename, titik tiga (berisi Share dan File Info).

**Warna aksen:** satu warna solid `#0A84FF` untuk semua elemen UI
fungsional (tombol, item terpilih, progress bar). Gradient dua warna
(`#0A84FF` → `#00C6FF`) khusus dipakai di branding/logo saja, tidak
pernah di komponen UI fungsional.

## 6. Settings (isi final)

**Tampilan Aplikasi:** Theme, Language
**Explorer:** Default View, Default Sort, Hidden File Default, Font
Size, Layar Awal (path picker)
**Tentang:** Version info, link ke About

Catatan: "Konfirmasi sebelum Hapus" WAJIB aktif secara default dan
tidak muncul di Settings sama sekali — ini perilaku baku di balik
layar, bukan preferensi yang bisa dimatikan atau bahkan dilihat user.

## 7. Roadmap Sub-Fase

**Sub-Fase 0a — Kerangka Hidup** (risiko rendah, baca-only)
- Event System dasar (FolderOpened, StorageMounted)
- Permission Manager, SAF dasar
- File Engine: Open/Close Folder, Back, Refresh
- Explorer UI: List View, Breadcrumb
- Layar Awal / Storage Overview versi minimal (kartu Internal Storage)
- Milestone: app bisa dibuka, browse folder Internal Storage

**Sub-Fase 0b — File Manager Fungsional** (risiko lebih tinggi,
mengubah filesystem)
- File Engine lengkap: Copy, Move, Paste, Rename, Delete, New Folder
- Task Queue (progress, pause, resume, cancel)
- Multi Selection, action mode toolbar, Search, Sort
- Show/Hide Hidden Files
- Storage Overview lengkap (SD Card, USB OTG, RAM)
- File Information lengkap
- Milestone: DalX bisa gantikan file manager bawaan untuk kerja harian

**Fase 1 — Android Integration Lanjutan**
Document Picker, Open With, Share Sheet, Install/Uninstall APK, Media
Scanner, Intent Handler.

**Fase 2 — Explorer Polish**
Grid View, Favorites, Duplicate, New File.

**Fase 3 — Media Viewer**
Preview foto & video.

**Fase 4 — Code Editor**
Baca & edit py/java/c++/dart/dll dengan syntax highlighting.

**Fase 5 — Archive**
Compress/extract ZIP (pure Dart dulu).

**Fase 6 — Doc Viewer**
Baca PDF, baca & tulis XLSX.

**Fase 7 — Settings, Cache, Logging**
Theme, Language, Font Size lengkap; Thumbnail/Folder Cache; Error/Crash
Log.

**Fase 8 — Native Power-up**
Compress kuat (setara 7z) via native lib, edit PDF, edit/preview PPT,
dukungan USB OTG penuh. Approach detail native library masih dibahas
terpisah saat fase ini dimulai.

## 8. Keputusan Teknis

| Aspek | Keputusan |
|---|---|
| Framework | Flutter (Dart) |
| State management | Riverpod (fallback ke Provider kalau terasa ribet) |
| Minimum SDK | Android 11 / SDK 30 |
| Nama app | DalX |
| Package name | `com.dalx.app` (huruf kecil semua) |
| Arsitektur | Modular, komunikasi antar modul hanya lewat Event System |
| Workflow build | Develop di Termux (Android), build APK via GitHub Actions — mengikuti pola project TaniLog |
