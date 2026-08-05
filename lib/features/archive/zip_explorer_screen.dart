// features/archive/zip_explorer_screen.dart
//
// Virtual browsing isi ZIP — TANPA extract ke disk dulu. Baca daftar
// entry ZIP (package:archive, cepat karena central directory ZIP
// emang didesain buat random-access), rekonstruksi jadi struktur
// folder virtual, browsing kayak folder biasa. Copy/Cut cuma nyimpen
// keterangan ke ZipClipboard (core/clipboard) — extract BENERAN baru
// kejadian pas Paste di folder asli (lihat TaskQueue.extractZipEntries).
//
// SCOPE v1 (disepakati Damar):
// - CUMA buat file .zip (bukan 7z/RAR/tar — format itu lewat dialog
//   Extract/Buka-dengan-aplikasi-lain biasa di explorer_screen.dart)
// - List View doang, tidak ada Grid/thumbnail
// - Tap FILE (bukan folder) waktu TIDAK selecting = TIDAK ngapa-ngapain
//   (cuma bisa dipilih lewat tekan lama, sama kayak Explorer asli)
// - ZIP di dalam ZIP (nested) TIDAK didukung — kalau ketemu pas
//   browsing, dikasih tau lewat SnackBar, bukan dibiarin nyoba masuk
// - Tombol "Extract" (ekstrak SEMUA isi) tetap ada di app bar, extract
//   ke folder induk file ZIP-nya langsung (tanpa dialog pilih tujuan
//   — kalau butuh pilih tujuan, tetap bisa lewat menu titik-tiga di
//   Explorer asli tanpa buka screen ini)

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/clipboard/file_clipboard.dart';
import '../../core/clipboard/zip_clipboard.dart';
import '../../core/localization/app_strings.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../task_queue/task_queue.dart';

const _dalxAccent = Color(0xFF0A84FF);

/// Satu entry virtual di dalam ZIP — folder ATAU file. [fullPath]
/// pakai delimiter '/' (internal ZIP), bukan Platform.pathSeparator.
class _ZipEntryNode {
  final String name;
  final String fullPath;
  final bool isFolder;
  final int sizeBytes;

  const _ZipEntryNode({
    required this.name,
    required this.fullPath,
    required this.isFolder,
    required this.sizeBytes,
  });
}

class ZipExplorerScreen extends ConsumerStatefulWidget {
  final String path;
  const ZipExplorerScreen({super.key, required this.path});

  @override
  ConsumerState<ZipExplorerScreen> createState() => _ZipExplorerScreenState();
}

class _ZipExplorerScreenState extends ConsumerState<ZipExplorerScreen> {
  bool _loading = true;
  String? _error;
  Archive? _archive;
  // Key = "virtual directory path" ('' untuk root), value = daftar
  // anak langsung di level itu (folder & file bercampur, folder
  // duluan biar konsisten sama urutan List View Explorer asli).
  Map<String, List<_ZipEntryNode>> _tree = {};
  String _currentVirtualPath = '';
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _loadZip();
  }

  Future<void> _loadZip() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final tree = _buildTree(archive);
      setState(() {
        _archive = archive;
        _tree = tree;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Rekonstruksi struktur folder virtual dari daftar entry ZIP yang
  /// flat (tiap ArchiveFile.name itu path lengkap, mis.
  /// "folder1/sub/file.txt") — termasuk folder yang cuma implisit
  /// (nggak ada entry direktori eksplisit di ZIP-nya, cuma "kebaca"
  /// dari path file di dalamnya).
  Map<String, List<_ZipEntryNode>> _buildTree(Archive archive) {
    final childrenOf = <String, Map<String, _ZipEntryNode>>{};
    childrenOf[''] = {};

    void ensureDir(String dirPath) {
      childrenOf.putIfAbsent(dirPath, () => {});
    }

    for (final file in archive.files) {
      final rawName = file.name.replaceAll('\\', '/');
      final isExplicitDir = rawName.endsWith('/') || !file.isFile;
      final cleanPath = isExplicitDir && rawName.endsWith('/')
          ? rawName.substring(0, rawName.length - 1)
          : rawName;
      if (cleanPath.isEmpty) continue;

      final segments = cleanPath.split('/');

      // Daftarin semua folder perantara (implisit) sepanjang path ini.
      for (var i = 0; i < segments.length - 1; i++) {
        final dirPath = segments.sublist(0, i + 1).join('/');
        final parentPath = segments.sublist(0, i).join('/');
        ensureDir(dirPath);
        childrenOf[parentPath]!.putIfAbsent(
          segments[i],
          () => _ZipEntryNode(name: segments[i], fullPath: dirPath, isFolder: true, sizeBytes: 0),
        );
      }

      final parentPath = segments.sublist(0, segments.length - 1).join('/');
      ensureDir(parentPath);

      if (isExplicitDir) {
        childrenOf[parentPath]!.putIfAbsent(
          segments.last,
          () => _ZipEntryNode(name: segments.last, fullPath: cleanPath, isFolder: true, sizeBytes: 0),
        );
      } else {
        childrenOf[parentPath]![segments.last] = _ZipEntryNode(
          name: segments.last,
          fullPath: cleanPath,
          isFolder: false,
          sizeBytes: file.size,
        );
      }
    }

    return childrenOf.map((k, v) {
      final list = v.values.toList()
        ..sort((a, b) {
          if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1; // folder duluan
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return MapEntry(k, list);
    });
  }

  String get _fileName => widget.path.split('/').last;

  List<String> get _breadcrumbSegments =>
      _currentVirtualPath.isEmpty ? [] : _currentVirtualPath.split('/');

  bool get _isSelecting => _selectedPaths.isNotEmpty;

  /// Navigasi "back" di dalam ZIP — kalau masih di sub-folder, naik
  /// 1 level dulu (BUKAN langsung keluar screen). Baru keluar screen
  /// kalau sudah di root virtual ('').
  bool _handleBackPress() {
    if (_isSelecting) {
      setState(() => _selectedPaths.clear());
      return false;
    }
    if (_currentVirtualPath.isEmpty) return true; // biarkan pop screen
    final segments = _breadcrumbSegments;
    segments.removeLast();
    setState(() => _currentVirtualPath = segments.join('/'));
    return false;
  }

  void _onTapEntry(_ZipEntryNode node) {
    if (_isSelecting) {
      setState(() {
        if (_selectedPaths.contains(node.fullPath)) {
          _selectedPaths.remove(node.fullPath);
        } else {
          _selectedPaths.add(node.fullPath);
        }
      });
      return;
    }
    if (node.isFolder) {
      setState(() => _currentVirtualPath = node.fullPath);
    } else if (node.name.toLowerCase().endsWith('.zip')) {
      // ZIP bersarang — DI LUAR SCOPE v1, kasih tau daripada dibiarin
      // "masuk" tapi rusak/nggak jelas perilakunya.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ZIP di dalam ZIP belum didukung')),
      );
    } else if (node.name.toLowerCase().endsWith('.apk')) {
      // APK sering dibagiin dalam bentuk ZIP — kecualikan dari aturan
      // "tap file = no-op", biar bisa langsung install tanpa extract
      // manual dulu (murah: cuma 1 file, bukan seluruh isi ZIP).
      _installApkFromZip(node);
    }
    // Tap file biasa (bukan .zip/.apk) waktu TIDAK selecting: sengaja
    // tidak ngapa-ngapain, sesuai scope v1.
  }

  void _onLongPressEntry(_ZipEntryNode node) {
    setState(() => _selectedPaths.add(node.fullPath));
  }

  /// Extract 1 file APK ini doang ke cache dir (BUKAN seluruh isi
  /// ZIP), baru lempar ke installer sistem — sama alur cek izin
  /// kayak tap .apk di Explorer biasa. File hasil extract sementara
  /// ini otomatis ikut kesapu "Bersihkan Cache" (sama-sama di cache
  /// dir app).
  Future<void> _installApkFromZip(_ZipEntryNode node) async {
    final nativeBridge = ref.read(nativeBridgeProvider);
    final canInstall = await nativeBridge.canInstallPackages();
    if (!canInstall) {
      if (!mounted) return;
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

    final archive = _archive;
    if (archive == null) return;
    final entry = archive.files.firstWhere(
      (f) => f.name.replaceAll('\\', '/') == node.fullPath,
      orElse: () => throw StateError('Entry tidak ketemu di archive'),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final installDir = Directory('${tempDir.path}/apk_install');
      await installDir.create(recursive: true);
      final tempApkPath = '${installDir.path}/${node.name}';
      await File(tempApkPath).writeAsBytes(entry.content as List<int>);
      await nativeBridge.installApk(tempApkPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal extract APK: $e')),
      );
    }
  }

  void _copySelected({required bool isCut}) {
    ref.read(zipClipboardProvider.notifier).add(
          widget.path,
          _selectedPaths.toList(),
          isCut: isCut,
        );
    // Clipboard file REGULER ikut di-clear — cuma 1 JENIS clipboard
    // aktif dalam satu waktu (dulu cuma satu arah: Copy/Cut di
    // Explorer biasa nge-clear clipboard ZIP, tapi Copy/Cut ZIP di
    // sini TIDAK nge-clear clipboard file biasa — bug kecil, sekalian
    // dibenerin di sini biar simetris dan panel mengambangnya gak
    // pernah numpuk 2 sekaligus).
    ref.read(fileClipboardProvider.notifier).clear();
    final count = _selectedPaths.length;
    setState(() => _selectedPaths.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCut
              ? '$count item ditambahkan ke clipboard (dipindah) — arsip ZIP asli TIDAK berubah'
              : '$count item ditambahkan ke clipboard (disalin)',
        ),
      ),
    );
  }

  Future<void> _extractAll() async {
    final destinationDir = widget.path.substring(0, widget.path.lastIndexOf('/'));
    await ref.read(taskQueueProvider.notifier).extract(widget.path, destinationDir);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Extract dimulai — lihat progress di Task Queue')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_handleBackPress()) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSelecting ? '${_selectedPaths.length} dipilih' : _fileName, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            icon: Icon(_isSelecting ? Icons.close : Icons.arrow_back),
            onPressed: () {
              if (_handleBackPress()) Navigator.of(context).pop();
            },
          ),
          actions: _isSelecting
              ? [
                  IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: () => _copySelected(isCut: false)),
                  IconButton(icon: const Icon(Icons.cut), tooltip: 'Cut', onPressed: () => _copySelected(isCut: true)),
                ]
              : [
                  IconButton(icon: const Icon(Icons.unarchive_outlined), tooltip: 'Extract semua', onPressed: _extractAll),
                ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _dalxAccent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Gagal baca ZIP:\n$_error', textAlign: TextAlign.center),
        ),
      );
    }

    final entries = _tree[_currentVirtualPath] ?? [];

    return Column(
      children: [
        if (_breadcrumbSegments.isNotEmpty) _buildBreadcrumb(),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('Folder kosong'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _buildTile(entries[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb() {
    final segments = _breadcrumbSegments;
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < segments.length; i++)
            GestureDetector(
              onTap: () => setState(() => _currentVirtualPath = segments.sublist(0, i + 1).join('/')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (i > 0) const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    Text(segments[i], style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTile(_ZipEntryNode node) {
    final isSelected = _selectedPaths.contains(node.fullPath);
    return ListTile(
      leading: Icon(
        node.isFolder ? Icons.folder : Icons.insert_drive_file_outlined,
        color: node.isFolder ? _dalxAccent : Colors.grey,
      ),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      subtitle: node.isFolder ? null : Text(_formatSize(node.sizeBytes), style: const TextStyle(fontSize: 11)),
      trailing: _isSelecting
          ? Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? _dalxAccent : Colors.grey)
          : null,
      selected: isSelected,
      selectedTileColor: _dalxAccent.withOpacity(0.08),
      onTap: () => _onTapEntry(node),
      onLongPress: () => _onLongPressEntry(node),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
}
