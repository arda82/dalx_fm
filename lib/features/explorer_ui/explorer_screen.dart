// features/explorer_ui/explorer_screen.dart
//
// Layar Explorer Sub-Fase 0a: List View + Breadcrumb saja.
// Search, Sort, Multi-selection, action mode toolbar, dan menu
// titik-tiga (Folder Baru/File Baru/Hidden Files/Grid View) menyusul
// di Sub-Fase 0b — lihat mockup DalXMockup.jsx untuk desain lengkapnya.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/file_item.dart';
import 'app_drawer.dart';
import 'explorer_state.dart';

// Warna aksen sesuai brand DalX — satu warna solid untuk UI
// fungsional (ARCHITECTURE.md bagian 5). Gradient dua warna cuma
// dipakai di branding/logo, bukan di sini.
const dalxAccent = Color(0xFF0A84FF);

class ExplorerScreen extends ConsumerWidget {
  final String rootPath;

  const ExplorerScreen({super.key, required this.rootPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explorerState = ref.watch(explorerProvider);
    final notifier = ref.read(explorerProvider.notifier);

    // Buka rootPath sekali saat layar pertama kali dibangun dan belum
    // ada folder yang dibuka.
    if (explorerState.currentPath == null && !explorerState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.openFolder(rootPath);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackButton(context, notifier);
      },
      child: Scaffold(
        appBar: _buildToolbar(context, explorerState),
        drawer: const AppDrawer(),
        body: Column(
          children: [
            _buildBreadcrumb(explorerState),
            const Divider(height: 1),
            Expanded(child: _buildFileList(explorerState, notifier)),
          ],
        ),
      ),
    );
  }

  void _handleBackButton(BuildContext context, ExplorerNotifier notifier) {
    if (notifier.canGoBack) {
      notifier.goBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  PreferredSizeWidget _buildToolbar(BuildContext context, ExplorerState state) {
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
        IconButton(icon: const Icon(Icons.search), onPressed: () {
          // Search menyusul di Sub-Fase 0b
        }),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () {
          // Dropdown menu (Folder Baru/File Baru/Hidden/Grid) di 0b
        }),
      ],
    );
  }

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

    return RefreshIndicator(
      color: dalxAccent,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final item = state.items[index];
          return _FileListTile(
            item: item,
            onTap: () {
              if (item.isFolder) notifier.openFolder(item.path);
              // Membuka file (bukan folder) menyusul saat viewer/editor
              // sudah ada di fase-fase berikutnya.
            },
          );
        },
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final FileItem item;
  final VoidCallback onTap;

  const _FileListTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        item.isFolder ? Icons.folder : _iconForExtension(item.extension),
        color: item.isFolder ? dalxAccent : Colors.grey,
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.isFolder ? '' : _formatSize(item.sizeBytes)),
      onTap: onTap,
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
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
