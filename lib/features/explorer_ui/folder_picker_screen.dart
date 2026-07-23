// features/explorer_ui/folder_picker_screen.dart
//
// Layar folder picker khusus buat Extract ("Pilih" folder tujuan) —
// Fase 5 (Archive). SENGAJA dibuat sebagai layar mandiri, BUKAN
// numpang ke ExplorerScreen biasa. Alasannya: fileEngineProvider
// adalah .family keyed by rootPath (lihat catatan panjang di
// file_engine.dart soal bug "SD Card kebuka isinya Internal
// Storage") — kalau folder picker ini reuse instance FileEngine yang
// sama dengan ExplorerScreen utama yang sedang terbuka (rootPath
// sama), navigasi di picker akan ikut mengubah history/currentPath
// punya Explorer utama juga, dan sebaliknya. Jadi di sini FileEngine
// dibuat baru & independen, cuma buat sesi memilih folder, dibuang
// begitu layar ini ditutup.
//
// Cuma menampilkan FOLDER (file disembunyikan — bukan tujuan yang
// valid buat "Pilih Folder Tujuan"). Tap folder = masuk ke dalamnya.
// Tombol "Pilih Folder Ini" di bawah selalu mengacu ke folder yang
// SEDANG dibuka saat ini.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/models/file_item.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../file_engine/file_engine.dart';
import 'explorer_screen.dart' show dalxAccent;

/// Buka folder picker, return path folder yang dipilih user (null
/// kalau dibatalkan). [initialPath] = titik awal browsing (biasanya
/// root storage yang sama dengan Explorer yang sedang aktif).
Future<String?> showFolderPicker(
  BuildContext context,
  WidgetRef ref, {
  required String initialPath,
  String title = 'Pilih Folder Tujuan',
}) {
  final eventBus = ref.read(eventBusProvider);
  final nativeBridge = ref.read(nativeBridgeProvider);
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => FolderPickerScreen(
        initialPath: initialPath,
        title: title,
        fileEngine: FileEngine(eventBus, nativeBridge),
      ),
    ),
  );
}

class FolderPickerScreen extends StatefulWidget {
  final String initialPath;
  final String title;
  final FileEngine fileEngine;

  const FolderPickerScreen({
    super.key,
    required this.initialPath,
    required this.title,
    required this.fileEngine,
  });

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  List<FileItem> _folders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _open(widget.initialPath);
  }

  Future<void> _open(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final items = await widget.fileEngine.openFolder(path);
      setState(() {
        _folders = items.where((i) => i.isFolder).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _goBackInternal() async {
    if (!widget.fileEngine.canGoBack) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final items = await widget.fileEngine.goBack();
      setState(() {
        _folders = items.where((i) => i.isFolder).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = widget.fileEngine.currentPath ?? widget.initialPath;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (widget.fileEngine.canGoBack) {
          _goBackInternal();
        } else {
          Navigator.of(context).pop(); // batal, tidak ada folder dipilih
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                currentPath,
                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: dalxAccent),
                onPressed: () => Navigator.of(context).pop(currentPath),
                icon: const Icon(Icons.check),
                label: const Text('Pilih Folder Ini'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text('Gagal membaca folder: $_errorMessage'));
    }
    if (_folders.isEmpty) {
      return const Center(
        child: Text('Tidak ada sub-folder di sini', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          leading: const Icon(Icons.folder, color: dalxAccent),
          title: Text(folder.name),
          onTap: () => _open(folder.path),
        );
      },
    );
  }
}
