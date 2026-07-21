// features/explorer_ui/explorer_screen.dart
//
// Layar Explorer Sub-Fase 0b, mengikuti desain mockup yang disetujui:
// - Toolbar normal: Hamburger, Judul, Search, titik-tiga (dropdown:
//   New Folder, New File, Hidden Files toggle, List/Grid — Grid
//   sendiri baru aktif di Fase 2, placeholder dulu di sini)
// - Action mode toolbar (saat multi-select): Trash, Copy, Cut,
//   Rename, titik-tiga (Share, File Info)
// - Long-press / tap saat sudah select mode untuk multi-select
//
// Fase 1: Share (action mode titik-tiga) aktif pakai share_plus.
// Tap file (bukan folder) sekarang aktif juga: Open With, Install
// APK (deteksi .apk), atau kembalikan file ke app pemanggil kalau
// DalX dibuka dalam pickMode (Document Picker). Lihat _handleFileTap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/file_item.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../file_engine/file_engine.dart';
import '../task_queue/task_queue_screen.dart';
import 'app_drawer.dart';
import 'explorer_state.dart';
import 'file_info_sheet.dart';

const dalxAccent = Color(0xFF0A84FF);

class ExplorerScreen extends ConsumerWidget {
  final String rootPath;
  final bool pickMode;

  const ExplorerScreen({super.key, required this.rootPath, this.pickMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explorerState = ref.watch(explorerProvider);
    final notifier = ref.read(explorerProvider.notifier);

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
        } else if (notifier.canGoBack) {
          notifier.goBack();
        } else if (Navigator.of(context).canPop()) {
          // Masih ada route lain di atas ExplorerScreen ini (mis. dibuka
          // dari drawer "Internal Storage" di atas Storage Overview) —
          // pop route itu, bukan maybePop() yang percuma karena
          // canPop:false bikin dia diam saja (root cause ANR "back
          // macet total" waktu sudah di folder terluar).
          Navigator.of(context).pop();
        } else {
          // ExplorerScreen ini adalah root (mis. dibuka langsung dari
          // main.dart tanpa route di atasnya) — keluar app, bukan
          // dibiarkan diam yang bikin sistem anggap app hang.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: explorerState.isSelectMode
            ? _buildActionModeToolbar(context, ref, explorerState, notifier)
            : _buildNormalToolbar(context, ref, explorerState, notifier),
        drawer: const AppDrawer(),
        body: Column(
          children: [
            if (!explorerState.isSelectMode) _buildBreadcrumb(explorerState),
            if (!explorerState.isSelectMode) const Divider(height: 1),
            if (notifier.hasPendingPaste) _buildPasteBar(notifier),
            Expanded(child: _buildFileList(context, ref, explorerState, notifier)),
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
    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Text(folderName.isEmpty ? 'DalX' : folderName),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showSearch(context, state, notifier),
        ),
        _MoreMenuButton(notifier: notifier, state: state),
      ],
    );
  }

  void _showSearch(BuildContext context, ExplorerState state, ExplorerNotifier notifier) {
    showSearch(
      context: context,
      delegate: _FileSearchDelegate(items: state.items, notifier: notifier),
    );
  }

  // ---------------- Action Mode Toolbar ----------------

  PreferredSizeWidget _buildActionModeToolbar(
    BuildContext context,
    WidgetRef ref,
    ExplorerState state,
    ExplorerNotifier notifier,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: notifier.exitSelectMode,
      ),
      title: Text('${state.selectedPaths.length} dipilih'),
      actions: [
        // Urutan sesuai mockup: Trash, Copy, Cut, Rename, titik-tiga
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(context, notifier, state),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined),
          onPressed: () {
            notifier.copySelected();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item disalin. Buka folder tujuan lalu Paste.')),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.content_cut),
          onPressed: () {
            notifier.cutSelected();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item dipotong. Buka folder tujuan lalu Paste.')),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: state.selectedPaths.length == 1
              ? () => _showRenameDialog(context, notifier, state.selectedPaths.first)
              : null,
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _handleActionMenuSelected(context, value, state),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'info', child: Text('File Info')),
          ],
        ),
      ],
    );
  }

  // Fase 1: Share Sheet via share_plus. Mendukung single & multi-file
  // (semua item yang sedang terpilih di action mode).
  Future<void> _handleActionMenuSelected(
    BuildContext context,
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
          SnackBar(content: Text('Gagal membuka Share: $e')),
        );
      }
    } else if (value == 'info') {
      // File Info hanya berlaku saat tepat 1 item terpilih.
      if (state.selectedPaths.length != 1) return;
      final selectedPath = state.selectedPaths.first;
      final item = state.items.firstWhere(
        (i) => i.path == selectedPath,
        orElse: () => throw StateError('Item tidak ditemukan: $selectedPath'),
      );
      if (!context.mounted) return;
      await showFileInfoSheet(context, item);
    }
  }

  // Selalu tanya konfirmasi sebelum hapus — ini perilaku BAKU, tidak
  // ada opsi mematikannya di Settings. Lihat ARCHITECTURE.md bagian 6.
  Future<void> _confirmDelete(BuildContext context, ExplorerNotifier notifier, ExplorerState state) async {
    final count = state.selectedPaths.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus item?'),
        content: Text('$count item akan dihapus. Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
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
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Simpan'),
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

  // ---------------- Paste Bar ----------------

  Widget _buildPasteBar(ExplorerNotifier notifier) {
    return Container(
      color: dalxAccent.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.content_paste, size: 16, color: dalxAccent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Ada item siap ditempel di sini', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: notifier.pasteHere,
            child: const Text('Paste'),
          ),
        ],
      ),
    );
  }

  // ---------------- File List ----------------

  Widget _buildFileList(BuildContext context, WidgetRef ref, ExplorerState state, ExplorerNotifier notifier) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: dalxAccent));
    }
    if (state.errorMessage != null) {
      return Center(child: Text('Terjadi kesalahan: ${state.errorMessage}'));
    }
    if (state.items.isEmpty) {
      if (_isRestrictedAndroidFolder(state.currentPath)) {
        return _buildRestrictedNotice(context);
      }
      return const Center(child: Text('Folder ini kosong'));
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
            isSelectMode: state.isSelectMode,
            onTap: () {
              if (state.isSelectMode) {
                notifier.toggleSelection(item.path);
              } else if (item.isFolder) {
                notifier.openFolder(item.path);
              } else {
                _handleFileTap(context, ref, item.path);
              }
            },
            onLongPress: () {
              if (!state.isSelectMode) notifier.enterSelectMode(item.path);
            },
          );
        },
      ),
    );
  }

  // Fase 1: tap file (bukan folder). Tiga jalur:
  // - pickMode (DalX dipanggil sebagai Document Picker) → kembalikan
  //   file terpilih ke app pemanggil lalu tutup DalX
  // - file .apk → cek izin install, lalu trigger installer sistem
  // - file lain → Open With (chooser Android biasa)
  Future<void> _handleFileTap(BuildContext context, WidgetRef ref, String path) async {
    final nativeBridge = ref.read(nativeBridgeProvider);

    if (pickMode) {
      await nativeBridge.returnPickedFile(path);
      return;
    }

    if (path.toLowerCase().endsWith('.apk')) {
      final canInstall = await nativeBridge.canInstallPackages();
      if (!canInstall) {
        if (!context.mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Izin diperlukan'),
            content: const Text('DalX butuh izin install app dari sumber tidak dikenal.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buka Settings')),
            ],
          ),
        );
        if (proceed == true) await nativeBridge.requestInstallPermission();
        return;
      }
      await nativeBridge.installApk(path);
      return;
    }

    await nativeBridge.openWith(path, mimeType: NativeBridge.mimeTypeFor(path));
  }

  // Deteksi apakah [path] adalah Android/data atau Android/obb (atau
  // subfolder di dalamnya) — folder yang isinya dibatasi total oleh
  // Android sejak versi 11, TIDAK bisa diakses app manapun tanpa root
  // (dikonfirmasi lewat riset: bahkan Amaze/CX File Manager/MiXplorer,
  // yang native Java bukan Flutter, mentok di batasan yang sama begitu
  // masuk lebih dalam — nama folder yang mereka tampilkan di permukaan
  // itu disintesis dari daftar app ter-install, bukan hasil baca
  // direktori beneran).
  bool _isRestrictedAndroidFolder(String? path) {
    if (path == null) return false;
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/Android/data') || normalized.contains('/Android/obb');
  }

  Widget _buildRestrictedNotice(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Isi folder ini dibatasi sistem Android',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sejak Android 11, tidak ada aplikasi (termasuk file '
              'manager lain) yang bisa membuka isi folder ini tanpa '
              'akses root. Ini bukan masalah pada DalX.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Dropdown Menu Titik Tiga ----------------

class _MoreMenuButton extends StatelessWidget {
  final ExplorerNotifier notifier;
  final ExplorerState state;

  const _MoreMenuButton({required this.notifier, required this.state});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) => _handleSelected(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'new_folder', child: _MenuRow(icon: Icons.create_new_folder_outlined, label: 'Folder Baru')),
        const PopupMenuItem(value: 'new_file', child: _MenuRow(icon: Icons.note_add_outlined, label: 'File Baru')),
        PopupMenuItem(
          value: 'toggle_hidden',
          child: _MenuRow(
            icon: Icons.visibility_off_outlined,
            label: state.showHidden ? 'Sembunyikan Tersembunyi' : 'Tampilkan Tersembunyi',
            active: state.showHidden,
          ),
        ),
        const PopupMenuItem(value: 'sort', child: _MenuRow(icon: Icons.sort, label: 'Urutkan')),
      ],
    );
  }

  Future<void> _handleSelected(BuildContext context, String value) async {
    switch (value) {
      case 'new_folder':
        final name = await _promptName(context, 'Folder Baru', 'Nama folder');
        if (name != null && name.isNotEmpty) await notifier.createFolder(name);
        break;
      case 'new_file':
        // Pembuatan file kosong — opsional sesuai daftar fitur core,
        // implementasi penuh menyusul bersama code_editor (Fase 4)
        // supaya file baru bisa langsung dibuka untuk diedit.
        break;
      case 'toggle_hidden':
        notifier.toggleShowHidden();
        break;
      case 'sort':
        _showSortMenu(context);
        break;
    }
  }

  Future<String?> _promptName(BuildContext context, String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Buat')),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: const Text('Nama'), onTap: () { notifier.setSortMode(SortMode.name); Navigator.pop(context); }),
          ListTile(title: const Text('Tanggal'), onTap: () { notifier.setSortMode(SortMode.date); Navigator.pop(context); }),
          ListTile(title: const Text('Ukuran'), onTap: () { notifier.setSortMode(SortMode.size); Navigator.pop(context); }),
        ],
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

  _FileSearchDelegate({required this.items, required this.notifier});

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
    if (results.isEmpty) return const Center(child: Text('Tidak ada hasil'));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: Icon(item.isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
              color: item.isFolder ? dalxAccent : Colors.grey),
          title: Text(item.name),
          onTap: () {
            close(context, null);
            if (item.isFolder) notifier.openFolder(item.path);
          },
        );
      },
    );
  }
}

// ---------------- File List Tile ----------------

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
        leading: isSelectMode
            ? Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? dalxAccent : Colors.grey,
              )
            : Icon(
                item.isFolder ? Icons.folder : _iconForExtension(item.extension),
                color: item.isFolder ? dalxAccent : Colors.grey,
              ),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.isFolder ? '' : _formatSize(item.sizeBytes)),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  IconData _iconForExtension(String ext) {
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    const docExts = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
    const archiveExts = {'zip', 'rar', '7z', 'tar', 'gz'};
    const codeExts = {'dart', 'py', 'java', 'c', 'cpp', 'js', 'ts'};

    if (imageExts.contains(ext)) return Icons.image_outlined;
    if (docExts.contains(ext)) return Icons.description_outlined;
    if (archiveExts.contains(ext)) return Icons.folder_zip_outlined;
    if (codeExts.contains(ext)) return Icons.code;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}