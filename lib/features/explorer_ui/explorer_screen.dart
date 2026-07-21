// features/explorer_ui/explorer_screen.dart
//
// Layar Explorer Sub-Fase 0b + Fase 2 (Explorer Polish), mengikuti
// desain mockup yang disetujui:
// - Toolbar normal: Hamburger, Judul, Search, titik-tiga (dropdown:
//   New Folder, New File, Hidden Files toggle, List/Grid)
// - Action mode toolbar (saat multi-select): Trash, Copy, Cut,
//   Duplicate, Rename, titik-tiga (Share, File Info, Favorite)
// - Long-press / tap saat sudah select mode untuk multi-select
// - Grid View sebagai alternatif List View (Fase 2)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/file_item.dart';
import '../favorites/favorites_service.dart';
import '../file_engine/file_engine.dart';
import '../task_queue/task_queue_screen.dart';
import 'app_drawer.dart';
import 'explorer_state.dart';

const dalxAccent = Color(0xFF0A84FF);

class ExplorerScreen extends ConsumerWidget {
  final String rootPath;

  const ExplorerScreen({super.key, required this.rootPath});

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
        } else {
          Navigator.of(context).maybePop();
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
            Expanded(child: _buildFileList(explorerState, notifier)),
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
    final favorites = ref.watch(favoritesProvider);
    final allFavorited = state.selectedPaths.isNotEmpty &&
        state.selectedPaths.every(favorites.contains);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: notifier.exitSelectMode,
      ),
      title: Text('${state.selectedPaths.length} dipilih'),
      actions: [
        // Urutan sesuai mockup: Trash, Copy, Cut, Duplicate, Rename, titik-tiga
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
          icon: const Icon(Icons.content_copy_outlined),
          tooltip: 'Duplicate',
          onPressed: () => notifier.duplicateSelected(),
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: state.selectedPaths.length == 1
              ? () => _showRenameDialog(context, notifier, state.selectedPaths.first)
              : null,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'share') {
              // Share sheet — menyusul Fase 1 (Android Integration)
            } else if (value == 'info') {
              // File Info bottom sheet — menyusul di iterasi berikutnya 0b
            } else if (value == 'favorite') {
              ref.read(favoritesProvider.notifier).toggleMultiple(state.selectedPaths.toList());
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'share', child: Text('Share')),
            const PopupMenuItem(value: 'info', child: Text('File Info')),
            PopupMenuItem(
              value: 'favorite',
              child: Text(allFavorited ? 'Hapus Favorit' : 'Tambah Favorit'),
            ),
          ],
        ),
      ],
    );
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

  // ---------------- File List (List View / Grid View) ----------------

  Widget _buildFileList(ExplorerState state, ExplorerNotifier notifier) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: dalxAccent));
    }
    if (state.errorMessage != null) {
      return Center(child: Text('Terjadi kesalahan: ${state.errorMessage}'));
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('Folder ini kosong'));
    }

    if (state.viewMode == ViewMode.grid) {
      return RefreshIndicator(
        color: dalxAccent,
        onRefresh: notifier.refresh,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.85,
          ),
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final item = state.items[index];
            final isSelected = state.selectedPaths.contains(item.path);
            return _FileGridTile(
              item: item,
              isSelected: isSelected,
              isSelectMode: state.isSelectMode,
              onTap: () {
                if (state.isSelectMode) {
                  notifier.toggleSelection(item.path);
                } else if (item.isFolder) {
                  notifier.openFolder(item.path);
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
              }
              // Membuka file (bukan folder) menyusul saat viewer/editor
              // sudah ada di fase-fase berikutnya.
            },
            onLongPress: () {
              if (!state.isSelectMode) notifier.enterSelectMode(item.path);
            },
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
        PopupMenuItem(
          value: 'toggle_view',
          child: _MenuRow(
            icon: state.viewMode == ViewMode.grid ? Icons.grid_view : Icons.view_list,
            label: state.viewMode == ViewMode.grid ? 'Tampilan List' : 'Tampilan Grid',
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
        final name = await _promptName(context, 'File Baru', 'Nama file (mis. catatan.txt)');
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.isFolder ? Icons.folder : _iconForExtension(item.extension),
                  size: 40,
                  color: item.isFolder ? dalxAccent : Colors.grey,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (isSelectMode)
              Positioned(
                top: 2,
                right: 2,
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: isSelected ? dalxAccent : Colors.grey,
                ),
              ),
          ],
        ),
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
}