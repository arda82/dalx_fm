# DalX

File manager Android modern, ringan, dan powerful. Explore · Find · Manage.

## Status

**Sub-Fase 0a — Kerangka Hidup** (lihat ARCHITECTURE.md bagian 7)

Sudah ada:
- Event System dasar (`FolderOpened`, `StorageMounted`)
- Permission Manager (MANAGE_EXTERNAL_STORAGE)
- File Engine: Open Folder, Back, Refresh
- Explorer UI: List View, Breadcrumb, Drawer (sebagian item masih
  nonaktif, menyusul di sub-fase berikutnya)

Belum ada (sengaja, lihat roadmap):
- Copy/Move/Delete/Rename — Sub-Fase 0b
- Search, Sort, Multi-selection — Sub-Fase 0b
- Grid View, Favorites — Fase 2
- SD Card/USB OTG aktif — Sub-Fase 0b/Fase 8

## Menjalankan di Termux

```bash
flutter pub get
flutter run
```

Untuk build APK release:

```bash
flutter build apk --release
```

## Dokumen Acuan

- `ARCHITECTURE.md` — arsitektur lengkap, aturan komunikasi antar
  modul, roadmap sub-fase, keputusan teknis. Baca ini duluan kalau
  lupa kenapa sesuatu didesain begini.
- `lib/core/events/event_catalog.dart` — katalog semua event yang
  beredar antar modul.

## Struktur

```
lib/
├── main.dart
├── core/         ← Event System, Permission, SAF, model bersama
└── features/     ← satu folder per fitur (file_engine, explorer_ui, dst)
```

Aturan wajib: modul di `features/` dilarang saling panggil langsung,
semua komunikasi lewat Event System di `core/events`. Detail dan
alasannya ada di ARCHITECTURE.md bagian 3.
