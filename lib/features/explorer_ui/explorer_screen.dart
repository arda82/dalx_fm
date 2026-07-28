// features/explorer_ui/explorer_screen.dart
//
// Layar Explorer Sub-Fase 0b + Fase 1 (Share, File Info, Open With,
// Install APK, pickMode — Document Picker) + Fase 2 (Explorer Polish:
// Grid View, Favorites, Duplicate, New File) + Fase 3 (Media Viewer:
// Image Viewer & Video Viewer) + Fase 4 (Code Editor) + Root Mode
// (back-button behavior khusus).
//
// --- pickMode ---
// pickMode = true dipakai saat DalX dibuka lewat intent
// ACTION_GET_CONTENT (app lain minta DalX jadi file picker-nya):
// - Tap FILE -> kembalikan path ke app pemanggil lewat
//   NativeBridge.returnPickedFile, lalu tutup DalX.
// - Tap FOLDER -> navigasi biasa (buka isi folder).
// - Semua aksi ubah filesystem (New Folder/File, Delete, Rename,
//   Copy/Cut/Paste, Duplicate, multi-select) DIMATIKAN — picker cuma
//   untuk memilih, bukan mengelola file. Root Mode/Layar Awal juga
//   tidak berlaku di pickMode (back = pop/exit biasa).
//
// --- Root Mode (core/settings/app_settings.dart) ---
// Toggle manual di Settings, default OFF (DalX tidak mendeteksi root
// otomatis). Berlaku begitu history navigasi di ExplorerScreen ini
// habis (canGoBack false) — titik ini sama saja baik masuk dari
// drawer "Internal Storage" maupun dari card di Layar Awal:
// - OFF -> back langsung ke Layar Awal (StorageOverviewScreen),
//   pakai pushAndRemoveUntil biar bersih dari back-stack lama,
//   konsisten dari jalur masuk manapun.
// - ON  -> back naik ke folder induk ASLI filesystem (di luar
//   history), terus sampai mentok "/" (lihat FileEngine.goToParent).
//   Setelah di "/", back berikutnya baru pop/exit biasa.
//
// --- Tap File (non-pickMode) ---
// Urutan cek di _handleFileTap, dari paling spesifik ke paling umum:
// - file gambar (jpg/jpeg/png/gif/webp/bmp) -> ImageViewerScreen
//   (media_viewer, Fase 3), dibawa juga daftar gambar sefolder biar
//   bisa swipe kiri/kanan tanpa keluar-masuk viewer.
// - file video (mp4/mkv/webm/3gp/mov/avi) -> VideoViewerScreen
//   (media_viewer, Fase 3).
// - file .pdf -> PdfViewerScreen (doc_viewer, Fase 6) — basic
//   scroll + pinch zoom aja, bukan editor.
// - file .xlsx -> XlsxEditorScreen (doc_viewer, Fase 6) — grid
//   editable penuh lewat pluto_grid, baca/tulis via package excel.
// - file kode (dart/py/java/kt/c/cpp/js/ts/json/yaml/xml/html/css/
//   md/sh/sql/go/rs/swift/php/rb) -> CodeEditorScreen (code_editor,
//   Fase 4).
// - file .apk -> cek izin install, trigger installer sistem.
// - file lain -> Open With (chooser Android).
//
// --- Folder Android/data & Android/obb ---
// Dibatasi total oleh Android non-root, ditampilkan lewat notice
// informatif (bukan "Folder ini kosong" polos) — lihat
// _isRestrictedAndroidFolder/_buildRestrictedNotice.

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/localization/app_strings.dart';
import '../../core/models/file_item.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../../core/settings/app_settings.dart';
import '../code_editor/code_editor_screen.dart';
import '../doc_viewer/pdf_viewer_screen.dart';
import '../doc_viewer/xlsx_editor_screen.dart';
import '../favorites/favorites_service.dart';
import '../file_engine/file_engine.dart';
import '../media_viewer/image_viewer_screen.dart';
import '../media_viewer/audio_player_screen.dart';
import '../media_viewer/video_viewer_screen.dart';
import '../ppt_viewer/ppt_viewer_screen.dart';
import '../db_viewer/db_viewer_screen.dart';
import '../archive/zip_explorer_screen.dart';
import '../storage_overview/storage_overview_screen.dart';
import '../task_queue/task.dart';
import '../task_queue/task_queue.dart';
import '../task_queue/task_queue_screen.dart';
import 'app_drawer.dart';
import 'explorer_state.dart';
import 'file_info_sheet.dart';
import 'folder_picker_screen.dart';
import 'thumbnail_tile.dart';

const dalxAccent = Color(0xFF0A84FF);

class ExplorerScreen extends ConsumerWidget {
  final String rootPath;

  /// True kalau layar ini dibuka dalam mode Document Picker (Fase 1).
  /// Lihat catatan di atas file untuk perilaku lengkapnya.
  final bool pickMode;

  const ExplorerScreen({
    super.key,
    required this.rootPath,
    this.pickMode = false,
  });

  void _handlePopOrExit(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Aktifin listener CacheCleared -> clearThumbnailMemoryCache()
    // (lihat thumbnail_tile.dart). Cuma perlu di-watch, tidak dipakai
    // nilainya (Provider<void>).
    ref.watch(thumbnailCacheClearListenerProvider);

    final explorerState = ref.watch(explorerProvider(rootPath));
    final notifier = ref.read(explorerProvider(rootPath).notifier);

    if (explorerState.currentPath == null && !explorerState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.openFolder(rootPath);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (explorerState.isSelectMode) {
          notifier.exitSelectMode();
          return;
        }
        if (notifier.canGoBack) {
          notifier.goBack();
          return;
        }

        // Di pickMode, tidak ada konsep Layar Awal/Root Mode — cukup
        // pop/exit biasa begitu history habis.
        if (pickMode) {
          _handlePopOrExit(context);
          return;
        }

        // History navigasi ExplorerScreen ini sudah habis (titik ini
        // sama persis baik masuk dari drawer "Internal Storage"
        // maupun dari card di Layar Awal) — sekarang tergantung Root
        // Mode.
        final isRootMode = ref.read(rootModeProvider);
        if (isRootMode) {
          if (!notifier.atFilesystemRoot) {
            notifier.goToParent();
          } else {
            _handlePopOrExit(context);
          }
          return;
        }

        // Non-root: selalu balik ke Layar Awal. pushAndRemoveUntil
        // membersihkan seluruh back-stack, biar hasilnya konsisten
        // dari jalur masuk manapun — bukan cuma pop satu level yang
        // bisa mendarat di tempat berbeda tergantung cara masuknya.
        // homePathProvider: null = StorageOverviewScreen (default),
        // non-null = user udah arahkan Layar Awal ke folder tertentu
        // lewat Settings.
        final homePath = ref.read(homePathProvider);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => homePath == null
                ? const StorageOverviewScreen()
                : ExplorerScreen(rootPath: homePath),
          ),
          (route) => false,
        );
      },
      child: Scaffold(
        appBar: (explorerState.isSelectMode && !pickMode)
            ? _buildActionModeToolbar(context, ref, explorerState, notifier)
            : _buildNormalToolbar(context, ref, explorerState, notifier),
        drawer: pickMode ? null : const AppDrawer(),
        body: Column(
          children: [
            if (!explorerState.isSelectMode || pickMode) _buildBreadcrumb(explorerState),
            if (!explorerState.isSelectMode || pickMode) const Divider(height: 1),
            Expanded(
              child: MediaQuery(
                // Fase 7: Font Size — cuma bungkus daftar file, bukan
                // seluruh Scaffold (AppBar/dialog tetap ukuran normal),
                // sesuai desain "Font Size" di bawah section Explorer.
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
                ),
                child: _buildFileList(context, ref, explorerState, notifier),
              ),
            ),
            if (!pickMode && notifier.hasPendingPaste)
              _buildClipboardBar(context, ref, notifier),
          ],
        ),
      ),
    );
  }

  // ---------------- Toolbar Normal ----------------

  PreferredSizeWidget _buildNormalToolbar(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    ExplorerNotifier notifier,
  ) {
    final folderName = state.currentPath?.split('/').last ?? '';
    final strings = AppStrings.of(context);
    return AppBar(
      leading: pickMode
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _handlePopOrExit(context),
            )
          : Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
      title: Text(pickMode
          ? strings.pickFileTitle
          : (folderName.isEmpty ? strings.appName : folderName)),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showSearch(context, ref, state, notifier),
        ),
        _MoreMenuButton(notifier: notifier, state: state, pickMode: pickMode),
      ],
    );
  }

  void _showSearch(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    ExplorerNotifier notifier,
  ) {
    showSearch(
      context: context,
      delegate: _FileSearchDelegate(
        items: state.items,
        notifier: notifier,
        pickMode: pickMode,
        onPicked: (path) => _returnPickedFile(context, ref, path),
      ),
    );
  }

  // ---------------- Action Mode Toolbar (nonaktif total di pickMode) ----------------

  PreferredSizeWidget _buildActionModeToolbar(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    ExplorerNotifier notifier,
  ) {
    final favorites = ref.watch(favoritesProvider);
    final allFavorited = state.selectedPaths.isNotEmpty &&
        state.selectedPaths.every(favorites.contains);

    // Open With cuma masuk akal kalau tepat 1 item terpilih dan itu
    // file (bukan folder) — sama seperti File Info. Ditaruh di More
    // supaya tetap bisa dipakai di SD Card/USB OTG, karena tap-langsung
    // untuk buka app di luar (Fase 1) kadang tidak otomatis muncul di
    // storage eksternal.
    FileItem? singleSelectedItem;
    if (state.selectedPaths.length == 1) {
      for (final item in state.items) {
        if (item.path == state.selectedPaths.first) {
          singleSelectedItem = item;
          break;
        }
      }
    }
    final canOpenWith = singleSelectedItem != null && !singleSelectedItem.isFolder;
    // Extract cuma masuk akal kalau tepat 1 item terpilih dan itu
    // file .zip. Compress selalu boleh selama ada item terpilih
    // (apa pun tipenya, termasuk campuran file & folder).
    final canExtract = singleSelectedItem != null && singleSelectedItem.isArchive;
    final strings = AppStrings.of(context);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: notifier.exitSelectMode,
      ),
      title: Text(strings.selectedCount(state.selectedPaths.length)),
      actions: [
        // Urutan sesuai mockup: Trash, Copy, Cut, Rename, titik-tiga.
        // (Duplicate dihapus dari sini — bikin dua icon "copy" mirip
        // berdampingan dan membingungkan; Copy+Paste di folder yang
        // sama sudah cukup buat kebutuhan duplikat.)
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(context, notifier, state),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined),
          onPressed: notifier.copySelected,
        ),
        IconButton(
          icon: const Icon(Icons.content_cut),
          onPressed: notifier.cutSelected,
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: state.selectedPaths.length == 1
              ? () => _showRenameDialog(context, notifier, state.selectedPaths.first)
              : null,
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _handleActionMenuSelected(context, ref, value, state),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'share', child: Text(strings.share)),
            PopupMenuItem(value: 'info', child: Text(strings.fileInfo)),
            if (canOpenWith)
              PopupMenuItem(value: 'open_with', child: Text(strings.openWith)),
            PopupMenuItem(value: 'compress', child: Text(strings.compress)),
            if (canExtract)
              PopupMenuItem(value: 'extract', child: Text(strings.extract)),
            PopupMenuItem(
              value: 'favorite',
              child: Text(allFavorited ? strings.removeFromFavorites : strings.addToFavorites),
            ),
          ],
        ),
      ],
    );
  }

  // Fase 1: Share Sheet via share_plus (single & multi-file), File
  // Info (cuma saat tepat 1 item terpilih), dan Favorite (Fase 2,
  // bisa multi-select).
  Future<void> _handleActionMenuSelected(
    BuildContext context,
    WidgetRef ref,
    String value,
    ExplorerState state,
  ) async {
    if (value == 'share') {
      final paths = state.selectedPaths.toList();
      if (paths.isEmpty) return;
      try {
        await Share.shareXFiles(paths.map((p) => XFile(p)).toList());
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).shareFailed(e.toString()))),
        );
      }
    } else if (value == 'info') {
      if (state.selectedPaths.length != 1) return;
      final selectedPath = state.selectedPaths.first;
      final item = state.items.firstWhere(
        (i) => i.path == selectedPath,
        orElse: () => throw StateError('Item tidak ditemukan: $selectedPath'),
      );
      if (!context.mounted) return;
      await showFileInfoSheet(context, item);
    } else if (value == 'favorite') {
      ref.read(favoritesProvider.notifier).toggleMultiple(state.selectedPaths.toList());
    } else if (value == 'open_with') {
      if (state.selectedPaths.length != 1) return;
      final path = state.selectedPaths.first;
      final nativeBridge = ref.read(nativeBridgeProvider);
      try {
        await nativeBridge.openWith(path, mimeType: NativeBridge.mimeTypeFor(path));
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).openWithFailed(e.toString()))),
        );
      }
    } else if (value == 'compress') {
      final notifier = ref.read(explorerProvider(rootPath).notifier);
      final paths = state.selectedPaths.toList();
      if (paths.isEmpty) return;
      final suggestedName = paths.length == 1
          ? paths.first.split('/').last
          : 'Archive';
      final result = await _showCompressNameDialog(context, suggestedName);
      if (result == null || result.$1.trim().isEmpty) return;
      await notifier.compressSelected(result.$1.trim(), format: result.$2);
    } else if (value == 'extract') {
      if (state.selectedPaths.length != 1) return;
      final zipPath = state.selectedPaths.first;
      await _handleExtract(context, ref, zipPath);
    }
  }

  // ---------------- Tap Archive: Extract vs Buka Dengan Aplikasi Lain ----------------

  /// Dialog yang muncul pas tap file archive (ZIP/7z/RAR/tar) — dua
  /// opsi: Extract (pakai alur DalX yang sudah ada, sama kayak lewat
  /// menu titik-tiga) atau "Buka dengan aplikasi lain" (system chooser
  /// Android ASLI, BUKAN daftar aplikasi versi DalX sendiri — biar
  /// urutan/rekomendasi aplikasinya persis kayak yang OS kasih,
  /// bukan ditebak-tebak DalX).
  Future<void> _showArchiveTapDialog(BuildContext context, WidgetRef ref, FileItem item) async {
    final strings = AppStrings.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'extract'),
            child: Row(
              children: [
                const Icon(Icons.unarchive_outlined, color: dalxAccent),
                const SizedBox(width: 14),
                Text(strings.extract),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'open_with'),
            child: Row(
              children: [
                const Icon(Icons.open_in_new, color: dalxAccent),
                const SizedBox(width: 14),
                Text(strings.openWithOtherApp),
              ],
            ),
          ),
        ],
      ),
    );

    if (choice == 'extract') {
      if (!context.mounted) return;
      await _handleExtract(context, ref, item.path);
    } else if (choice == 'open_with') {
      final nativeBridge = ref.read(nativeBridgeProvider);
      await nativeBridge.openWith(item.path, mimeType: NativeBridge.mimeTypeFor(item.path));
    }
  }

  // ---------------- Fase 5 & Fase 8 Pilar #2: Archive (Compress/Extract) ----------------

  /// Return `(nama file, format)` atau null kalau dibatalkan. Pakai
  /// Dart record (bukan bikin class kecil terpisah) — cuma dipakai
  /// sekali di titik ini, class terpisah kelebihan buat kasus sesimpel
  /// ini.
  Future<(String, ArchiveFormat)?> _showCompressNameDialog(BuildContext context, String suggestedName) {
    final controller = TextEditingController(text: suggestedName);
    final strings = AppStrings.of(context);
    var format = ArchiveFormat.zip;
    return showDialog<(String, ArchiveFormat)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(strings.compress),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: strings.compressDialogZipNameLabel,
                  suffixText: format == ArchiveFormat.sevenZip ? '.7z' : '.zip',
                ),
              ),
              const SizedBox(height: 12),
              // Format selector — Fase 8 Pilar #2. ZIP tetap default
              // (pure Dart, sudah ada sejak Fase 5); 7z jalan lewat
              // native (Commons Compress).
              SegmentedButton<ArchiveFormat>(
                segments: const [
                  ButtonSegment(value: ArchiveFormat.zip, label: Text('ZIP')),
                  ButtonSegment(value: ArchiveFormat.sevenZip, label: Text('7Z')),
                ],
                selected: {format},
                onSelectionChanged: (selection) => setState(() => format = selection.first),
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? Colors.white : null,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? dalxAccent : null,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: dalxAccent),
              onPressed: () => Navigator.pop(context, (controller.text, format)),
              child: Text(strings.compress),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExtract(BuildContext context, WidgetRef ref, String zipPath) async {
    final choice = await _showExtractChoiceDialog(context);
    if (choice == null) return; // dibatalkan lewat X

    final notifier = ref.read(explorerProvider(rootPath).notifier);
    String? destinationDir;

    if (choice == 'here') {
      final currentPath = ref.read(explorerProvider(rootPath)).currentPath;
      destinationDir = currentPath;
    } else if (choice == 'pick') {
      if (!context.mounted) return;
      destinationDir = await showFolderPicker(context, ref, initialPath: rootPath);
    }
    if (destinationDir == null) return; // dibatalkan di folder picker

    final hasConflict = await notifier.checkExtractConflict(zipPath, destinationDir);
    var strategy = ConflictStrategy.renameAuto;
    if (hasConflict) {
      if (!context.mounted) return;
      final zipName = zipPath.split('/').last;
      final baseName = zipName.toLowerCase().endsWith('.zip')
          ? zipName.substring(0, zipName.length - 4)
          : zipName;
      final chosen = await _showConflictDialog(context, [baseName]);
      if (chosen == null) return;
      strategy = chosen;
    }

    await notifier.extractArchive(zipPath, destinationDir, strategy: strategy);
  }

  // Dialog "Extract" dengan tombol X batal di kiri atas judul, dan 2
  // pilihan tujuan: "Di sini" (folder tempat zip berada) atau "Pilih"
  // (folder picker terpisah, lihat folder_picker_screen.dart).
  Future<String?> _showExtractChoiceDialog(BuildContext context) {
    final strings = AppStrings.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            Text(strings.extract),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.unarchive_outlined, color: dalxAccent),
              title: Text(strings.extractDialogHere),
              subtitle: Text(strings.extractDialogHereSubtitle),
              onTap: () => Navigator.pop(context, 'here'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined, color: dalxAccent),
              title: Text(strings.extractDialogPick),
              subtitle: Text(strings.extractDialogPickSubtitle),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
          ],
        ),
      ),
    );
  }

  // Selalu tanya konfirmasi sebelum hapus — ini perilaku BAKU, tidak
  // ada opsi mematikannya di Settings. Lihat ARCHITECTURE.md bagian 6.
  Future<void> _confirmDelete(BuildContext context, ExplorerNotifier notifier, ExplorerState state) async {
    final count = state.selectedPaths.length;
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: Text(strings.deleteConfirmBody(count)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.deleteSelected();
    }
  }

  Future<void> _showRenameDialog(BuildContext context, ExplorerNotifier notifier, String path) async {
    final currentName = path.split('/').last;
    final controller = TextEditingController(text: currentName);
    final strings = AppStrings.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.renameDialogTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await notifier.renameItem(path, newName);
    }
  }

  // ---------------- Breadcrumb ----------------

  Widget _buildBreadcrumb(ExplorerState state) {
    final path = state.currentPath;
    if (path == null) return const SizedBox(height: 36);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 14),
        ),
        itemBuilder: (context, index) {
          final isLast = index == segments.length - 1;
          return Center(
            child: Text(
              segments[index],
              style: TextStyle(
                fontSize: 12,
                color: isLast ? null : dalxAccent,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- Clipboard Bar (bawah layar) ----------------
  //
  // Muncul selama ada item copy/cut yang belum di-paste. Cuma 2
  // tombol: Batal (buang clipboard, tidak jadi apa-apa) dan Tempel
  // (paste ke folder yang sedang dibuka — lewat cek konflik nama
  // dulu kalau perlu).

  Widget _buildClipboardBar(BuildContext context, WidgetRef ref, ExplorerNotifier notifier) {
    final strings = AppStrings.of(context);
    return SafeArea(
      top: false,
      child: Container(
        color: dalxAccent.withOpacity(0.10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: _ClipboardBarButton(
                icon: Icons.close,
                label: strings.clipboardCancel,
                onTap: notifier.cancelPendingPaste,
              ),
            ),
            Container(width: 1, height: 36, color: dalxAccent.withOpacity(0.25)),
            Expanded(
              child: _ClipboardBarButton(
                icon: Icons.content_paste,
                label: strings.clipboardPaste,
                color: dalxAccent,
                onTap: () => _handlePasteWithConflictCheck(context, notifier),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Cek dulu apakah ada nama yang bentrok di folder tujuan. Kalau
  // ada, tanya user mau Lewati/Timpa/Ganti Nama Otomatis lewat
  // dialog. Kalau user membatalkan dialog itu, paste dibatalkan
  // total (clipboard TETAP ada, supaya bisa dicoba lagi/paste di
  // folder lain).
  Future<void> _handlePasteWithConflictCheck(BuildContext context, ExplorerNotifier notifier) async {
    final conflicts = await notifier.checkPasteConflicts();

    var strategy = ConflictStrategy.renameAuto;
    if (conflicts.isNotEmpty) {
      if (!context.mounted) return;
      final chosen = await _showConflictDialog(context, conflicts);
      if (chosen == null) return; // dibatalkan, clipboard tetap ada
      strategy = chosen;
    }

    await notifier.pasteHere(strategy: strategy);
  }

  Future<ConflictStrategy?> _showConflictDialog(BuildContext context, List<String> conflictNames) {
    final strings = AppStrings.of(context);
    final preview = conflictNames.length <= 3
        ? conflictNames.join(', ')
        : '${conflictNames.take(3).join(', ')}, ${strings.conflictAndMore(conflictNames.length - 3)}';

    return showDialog<ConflictStrategy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.conflictDialogTitle),
        content: Text(strings.conflictDialogBody(conflictNames.length, preview)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictStrategy.skip),
            child: Text(strings.conflictSkip),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictStrategy.overwrite),
            child: Text(strings.conflictOverwrite),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictStrategy.renameAuto),
            child: Text(strings.conflictRenameAuto),
          ),
        ],
      ),
    );
  }

  // ---------------- Kirim file terpilih ke app pemanggil (pickMode) ----------------

  Future<void> _returnPickedFile(BuildContext context, WidgetRef ref, String path) async {
    try {
      await ref.read(nativeBridgeProvider).returnPickedFile(path);
      if (context.mounted) _handlePopOrExit(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).sendFileFailed(e.toString()))),
        );
      }
    }
  }

  // ---------------- Tap File non-pickMode ----------------
  //
  // Urutan cek: gambar -> ImageViewerScreen, video -> VideoViewerScreen
  // (Fase 3), kode -> CodeEditorScreen (Fase 4), baru kalau bukan
  // ketiganya lanjut ke jalur lama Fase 1 (Install APK / Open With).
  // Perlu ExplorerState di sini (bukan cuma path) supaya
  // ImageViewerScreen bisa dibawakan daftar gambar sefolder buat
  // swipe kiri/kanan.

  Future<void> _handleFileTap(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    FileItem item,
  ) async {
    if (item.isImage) {
      final images = state.items.where((i) => i.isImage).toList();
      final initialIndex = images.indexWhere((i) => i.path == item.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(
            images: images,
            initialIndex: initialIndex < 0 ? 0 : initialIndex,
          ),
        ),
      );
      return;
    }

    if (item.isVideo) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoViewerScreen(path: item.path)),
      );
      return;
    }

    if (item.isAudio) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AudioPlayerScreen(path: item.path)),
      );
      return;
    }

    if (item.isPdf) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(path: item.path)),
      );
      return;
    }

    if (item.isSpreadsheet) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => XlsxEditorScreen(path: item.path)),
      );
      return;
    }

    if (item.isPpt) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PptViewerScreen(path: item.path)),
      );
      return;
    }

    if (item.isDatabase) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DbViewerScreen(path: item.path)),
      );
      return;
    }

    if (item.isCodeFile) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CodeEditorScreen(path: item.path)),
      );
      return;
    }

    if (item.isArchive && item.extension.toLowerCase() == 'zip') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ZipExplorerScreen(path: item.path)),
      );
      return;
    }

    if (item.isArchive) {
      // Format archive selain ZIP (7z/RAR/tar/dst) — virtual browsing
      // cuma dibikin buat ZIP (lihat diskusi scope), sisanya tetap
      // lewat dialog Extract/Buka-dengan-aplikasi-lain ini.
      await _showArchiveTapDialog(context, ref, item);
      return;
    }

    final nativeBridge = ref.read(nativeBridgeProvider);

    if (item.path.toLowerCase().endsWith('.apk')) {
      final canInstall = await nativeBridge.canInstallPackages();
      if (!canInstall) {
        if (!context.mounted) return;
        final strings = AppStrings.of(context);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.installPermissionTitle),
            content: Text(strings.installPermissionBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.openSettingsButton)),
            ],
          ),
        );
        if (proceed == true) await nativeBridge.requestInstallPermission();
        return;
      }
      await nativeBridge.installApk(item.path);
      return;
    }

    await nativeBridge.openWith(item.path, mimeType: NativeBridge.mimeTypeFor(item.path));
  }

  // ---------------- Folder Android/data & Android/obb (dibatasi sistem) ----------------

  bool _isRestrictedAndroidFolder(String? path) {
    if (path == null) return false;
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/Android/data') || normalized.contains('/Android/obb');
  }

  Widget _buildRestrictedNotice(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              strings.restrictedFolderTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              strings.restrictedFolderBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- File List (List View / Grid View) ----------------

  Widget _buildFileList(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    ExplorerNotifier notifier,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: dalxAccent));
    }
    if (state.errorMessage != null) {
      return Center(child: Text(AppStrings.of(context).errorOccurred(state.errorMessage!)));
    }
    if (state.items.isEmpty) {
      if (_isRestrictedAndroidFolder(state.currentPath)) {
        return _buildRestrictedNotice(context);
      }
      return Center(child: Text(AppStrings.of(context).emptyFolder));
    }

    // Non-pickMode: tap file (bukan folder) -> Image/Video Viewer
    // (Fase 3), Code Editor (Fase 4), atau Open With/Install APK
    // (Fase 1) lewat _handleFileTap.
    // pickMode: tap file -> kembalikan ke app pemanggil. Tap folder
    // selalu navigasi biasa. Long-press/multi-select dimatikan total
    // di pickMode.
    void handleTap(FileItem item) {
      if (pickMode) {
        if (item.isFolder) {
          notifier.openFolder(item.path);
        } else {
          _returnPickedFile(context, ref, item.path);
        }
        return;
      }
      if (state.isSelectMode) {
        notifier.toggleSelection(item.path);
      } else if (item.isFolder) {
        notifier.openFolder(item.path);
      } else {
        _handleFileTap(context, ref, state, item);
      }
    }

    void handleLongPress(FileItem item) {
      if (pickMode) return; // multi-select dimatikan di pickMode
      if (!state.isSelectMode) notifier.enterSelectMode(item.path);
    }

    if (state.viewMode == ViewMode.grid) {
      return RefreshIndicator(
        color: dalxAccent,
        onRefresh: notifier.refresh,
        child: GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            // Disesuaikan biar cukup ruang buat icon 52px + font 13px
            // (ukuran dibesarkan biar setara CX File Manager) tanpa
            // overflow — dulu 0.78 pas buat icon 32px/font 10px.
            childAspectRatio: 0.68,
            mainAxisSpacing: 4,
            crossAxisSpacing: 2,
          ),
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final item = state.items[index];
            final isSelected = state.selectedPaths.contains(item.path);
            return _FileGridTile(
              item: item,
              isSelected: isSelected,
              isSelectMode: !pickMode && state.isSelectMode,
              onTap: () => handleTap(item),
              onLongPress: () => handleLongPress(item),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      color: dalxAccent,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final item = state.items[index];
          final isSelected = state.selectedPaths.contains(item.path);
          return _FileListTile(
            item: item,
            isSelected: isSelected,
            isSelectMode: !pickMode && state.isSelectMode,
            onTap: () => handleTap(item),
            onLongPress: () => handleLongPress(item),
          );
        },
      ),
    );
  }
}

// ---------------- Dropdown Menu Titik Tiga ----------------

class _MoreMenuButton extends StatelessWidget {
  final ExplorerNotifier notifier;
  final ExplorerState state;
  final bool pickMode;

  const _MoreMenuButton({required this.notifier, required this.state, this.pickMode = false});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PopupMenuButton<String>(
      onSelected: (value) => _handleSelected(context, value),
      itemBuilder: (context) => [
        // New Folder/New File cuma masuk akal saat mengelola file,
        // bukan saat memilih file untuk app lain.
        if (!pickMode) ...[
          PopupMenuItem(value: 'new_folder', child: _MenuRow(icon: Icons.create_new_folder_outlined, label: strings.newFolder)),
          PopupMenuItem(value: 'new_file', child: _MenuRow(icon: Icons.note_add_outlined, label: strings.newFile)),
        ],
        PopupMenuItem(
          value: 'toggle_hidden',
          child: _MenuRow(
            icon: Icons.visibility_off_outlined,
            label: state.showHidden ? strings.hideHiddenFiles : strings.showHiddenFiles,
            active: state.showHidden,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_view',
          child: _MenuRow(
            icon: state.viewMode == ViewMode.grid ? Icons.grid_view : Icons.view_list,
            label: state.viewMode == ViewMode.grid ? strings.listView : strings.gridView,
          ),
        ),
        if (!pickMode)
          PopupMenuItem(value: 'sort', child: _MenuRow(icon: Icons.sort, label: strings.sort)),
      ],
    );
  }

  Future<void> _handleSelected(BuildContext context, String value) async {
    final strings = AppStrings.of(context);
    switch (value) {
      case 'new_folder':
        final name = await _promptName(context, strings.newFolder, strings.newFolderNameHint);
        if (name != null && name.isNotEmpty) await notifier.createFolder(name);
        break;
      case 'new_file':
        final name = await _promptName(context, strings.newFile, strings.newFileNameHint);
        if (name != null && name.isNotEmpty) await notifier.createFile(name);
        break;
      case 'toggle_hidden':
        notifier.toggleShowHidden();
        break;
      case 'toggle_view':
        notifier.toggleViewMode();
        break;
      case 'sort':
        _showSortMenu(context);
        break;
    }
  }

  Future<String?> _promptName(BuildContext context, String title, String hint) {
    final controller = TextEditingController();
    final strings = AppStrings.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(strings.create)),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    final strings = AppStrings.of(context);
    final currentSort = state.sortMode;
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(strings.sortByName),
            trailing: currentSort == SortMode.name ? const Icon(Icons.check, color: dalxAccent) : null,
            onTap: () { notifier.setSortMode(SortMode.name); Navigator.pop(context); },
          ),
          ListTile(
            title: Text(strings.sortByDateNewest),
            trailing: currentSort == SortMode.dateNewest ? const Icon(Icons.check, color: dalxAccent) : null,
            onTap: () { notifier.setSortMode(SortMode.dateNewest); Navigator.pop(context); },
          ),
          ListTile(
            title: Text(strings.sortByDateOldest),
            trailing: currentSort == SortMode.dateOldest ? const Icon(Icons.check, color: dalxAccent) : null,
            onTap: () { notifier.setSortMode(SortMode.dateOldest); Navigator.pop(context); },
          ),
          ListTile(
            title: Text(strings.sortBySize),
            trailing: currentSort == SortMode.size ? const Icon(Icons.check, color: dalxAccent) : null,
            onTap: () { notifier.setSortMode(SortMode.size); Navigator.pop(context); },
          ),
        ],
      ),
    );
  }
}

// Tombol icon+label di clipboard bar bawah — dibuat lebih besar
// (dibanding IconButton toolbar biasa) supaya gampang di-tap dan
// jelas apa fungsinya tanpa perlu tooltip.
class _ClipboardBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ClipboardBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _MenuRow({required this.icon, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: active ? dalxAccent : null),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: active ? dalxAccent : null)),
      ],
    );
  }
}

// ---------------- Search Delegate ----------------

class _FileSearchDelegate extends SearchDelegate<void> {
  final List<FileItem> items;
  final ExplorerNotifier notifier;
  final bool pickMode;
  final void Function(String path)? onPicked;

  _FileSearchDelegate({
    required this.items,
    required this.notifier,
    this.pickMode = false,
    this.onPicked,
  });

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = items.where((i) => i.name.toLowerCase().contains(query.toLowerCase())).toList();
    if (results.isEmpty) return Center(child: Text(AppStrings.of(context).noResults));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: Icon(item.isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
              color: item.isFolder ? dalxAccent : Colors.grey),
          title: Text(item.name),
          onTap: () {
            if (pickMode && !item.isFolder) {
              close(context, null);
              onPicked?.call(item.path);
              return;
            }
            close(context, null);
            if (item.isFolder) notifier.openFolder(item.path);
          },
        );
      },
    );
  }
}

// ---------------- File List Tile (List View) ----------------

class _FileListTile extends StatelessWidget {
  final FileItem item;
  final bool isSelected;
  final bool isSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileListTile({
    required this.item,
    required this.isSelected,
    required this.isSelectMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isSelected ? dalxAccent.withOpacity(0.12) : null,
      child: ListTile(
        // dense + visualDensity: baris jadi lebih rapat (sebelumnya
        // kelonggaran vertikal terlalu jauh, terutama kelihatan pas
        // banyak folder berturut-turut).
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        // Fix utama alignment: SEBELUMNYA subtitle folder diisi
        // Text('') (string kosong) — itu tetap dihitung ListTile
        // sebagai baris subtitle yang ada (cuma kosong doang), bukan
        // "nggak ada subtitle". Efeknya ListTile dianggap 2-baris dan
        // ikon leading ikut naik ke atas (top-aligned), bukan center
        // sejajar teks. Sekarang null beneran kalau folder -> ListTile
        // jadi 1-baris murni, ikon otomatis center.
        subtitle: item.isFolder ? null : Text(_formatSize(item.sizeBytes)),
        // Jaga-jaga tambahan: paksa center eksplisit biar konsisten
        // di kombinasi 1-baris (folder) maupun 2-baris (file+ukuran).
        titleAlignment: ListTileTitleAlignment.center,
        leading: isSelectMode
            ? Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? dalxAccent : Colors.grey,
              )
            : (item.isThumbnailable
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: DalxThumbnail(
                        item: item,
                        fallback: Icon(_iconForFile(item), color: Colors.grey),
                      ),
                    ),
                  )
                : Icon(
                    item.isFolder ? Icons.folder : _iconForFile(item),
                    color: item.isFolder ? dalxAccent : Colors.grey,
                  )),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Dinaikkan lagi ke w600 — theme global sudah dinaikkan ke
          // w500 (Fase 7 kemarin), tapi khusus daftar file yang jadi
          // konten utama Explorer, dibuat lebih tebal lagi biar jelas
          // terbaca sebagai nama file, bukan teks sekunder.
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  /// Kekurangan yang ditemukan Damar: dulu banyak tipe file (mp3,
  /// apk, db, txt, json, yaml, md, iml, dst) jatuh ke icon fallback
  /// yang SAMA (Icons.insert_drive_file_outlined) — cuma image/doc/
  /// archive/code(sempit) yang beda. Sekarang reuse getter FileItem
  /// yang sudah ada (isImage/isVideo/isAudio/isPdf/dst, sudah dipakai
  /// juga buat routing tap) supaya icon SELALU konsisten sama
  /// perilaku tap-nya, tidak ada 2 sumber kebenaran yang bisa
  /// ke-drift kayak sebelumnya (docExts di sini dulu beda daftar
  /// sama _pdfExts/_spreadsheetExts di file_item.dart).
  IconData _iconForFile(FileItem item) {
    // Sub-kategori tambahan buat "code-ish" files yang secara
    // PERILAKU semua buka di Code Editor (isCodeFile), tapi secara
    // ICON dibedain lebih detail (biar txt/json/markdown kelihatan
    // beda, bukan cuma "kode" generik semua).
    const markdownExts = {'md', 'markdown'};
    const dataConfigExts = {'json', 'yaml', 'yml', 'xml', 'gradle'};
    const plainTextExts = {'txt', 'log', 'ini', 'cfg', 'properties', 'env'};
    // Format lama/tidak didukung DalX tapi tetap lazim ditemuin user
    // (Word .doc/.docx, Excel lama .xls, .csv) — dikasih icon yang
    // masuk akal walau tap-nya tetap jatuh ke Open With biasa.
    const wordExts = {'doc', 'docx'};
    const legacySpreadsheetExts = {'xls', 'csv'};

    if (item.isImage) return Icons.image_outlined;
    if (item.isVideo) return Icons.movie_outlined;
    if (item.isAudio) return Icons.audiotrack_outlined;
    if (item.isApk) return Icons.android;
    if (item.isPdf) return Icons.picture_as_pdf_outlined;
    if (item.isSpreadsheet || legacySpreadsheetExts.contains(item.extension)) return Icons.grid_on_outlined;
    if (item.isPpt) return Icons.slideshow_outlined;
    if (item.isArchive) return Icons.folder_zip_outlined;
    if (item.isDatabase) return Icons.storage_outlined;
    if (wordExts.contains(item.extension)) return Icons.description_outlined;
    if (markdownExts.contains(item.extension)) return Icons.article_outlined;
    if (dataConfigExts.contains(item.extension)) return Icons.data_object_outlined;
    if (plainTextExts.contains(item.extension)) return Icons.text_snippet_outlined;
    if (item.isCodeFile) return Icons.code;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ---------------- File Grid Tile (Grid View — Fase 2) ----------------

class _FileGridTile extends StatelessWidget {
  final FileItem item;
  final bool isSelected;
  final bool isSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FileGridTile({
    required this.item,
    required this.isSelected,
    required this.isSelectMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? dalxAccent.withOpacity(0.12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Column(
              // START (bukan center) + tinggi teks direserve tetap di
              // bawah — biar posisi icon SELALU sama persis di semua
              // cell, nggak peduli nama filenya 1 baris atau 2 baris.
              // Sebelumnya pakai `center`: nama file pendek (1 baris)
              // vs panjang (2 baris) punya tinggi konten beda, jadi
              // icon ikut kegeser naik-turun antar cell -> kelihatan
              // "berantakan" walau urutan filenya sebenarnya sudah
              // benar (lihat diskusi perbandingan dengan CX FM).
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: item.isThumbnailable
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: DalxThumbnail(
                            item: item,
                            fallback: Center(
                              child: Icon(_iconForFile(item), size: 52, color: Colors.grey),
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            item.isFolder ? Icons.folder : _iconForFile(item),
                            size: 52,
                            color: item.isFolder ? dalxAccent : Colors.grey,
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                // Tinggi direserve TETAP (cukup buat 2 baris) supaya
                // nama file 1 baris tidak bikin cell itu "lebih
                // pendek" dari cell tetangga yang 2 baris.
                SizedBox(
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.15),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            if (isSelectMode)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 14,
                  color: isSelected ? dalxAccent : Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Sama persis logic-nya sama _FileListTile._iconForFile — lihat
  /// komentar lengkap di sana. Duplikasi kecil ini konsisten sama
  /// pola yang sudah ada (2 private class beda buat List/Grid Tile,
  /// masing-masing punya method sendiri) daripada dipaksa 1 fungsi
  /// top-level bareng (butuh refactor lebih besar buat manfaat kecil).
  IconData _iconForFile(FileItem item) {
    const markdownExts = {'md', 'markdown'};
    const dataConfigExts = {'json', 'yaml', 'yml', 'xml', 'gradle'};
    const plainTextExts = {'txt', 'log', 'ini', 'cfg', 'properties', 'env'};
    const wordExts = {'doc', 'docx'};
    const legacySpreadsheetExts = {'xls', 'csv'};

    if (item.isImage) return Icons.image_outlined;
    if (item.isVideo) return Icons.movie_outlined;
    if (item.isAudio) return Icons.audiotrack_outlined;
    if (item.isApk) return Icons.android;
    if (item.isPdf) return Icons.picture_as_pdf_outlined;
    if (item.isSpreadsheet || legacySpreadsheetExts.contains(item.extension)) return Icons.grid_on_outlined;
    if (item.isPpt) return Icons.slideshow_outlined;
    if (item.isArchive) return Icons.folder_zip_outlined;
    if (item.isDatabase) return Icons.storage_outlined;
    if (wordExts.contains(item.extension)) return Icons.description_outlined;
    if (markdownExts.contains(item.extension)) return Icons.article_outlined;
    if (dataConfigExts.contains(item.extension)) return Icons.data_object_outlined;
    if (plainTextExts.contains(item.extension)) return Icons.text_snippet_outlined;
    if (item.isCodeFile) return Icons.code;
    return Icons.insert_drive_file_outlined;
  }
}
