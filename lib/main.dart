// main.dart
//
// Eksekutor DalX. Tanggung jawabnya cuma: setup Riverpod, tentukan
// tema, dan arahkan ke halaman pertama (cek permission dulu, baru
// Explorer). Logic sesungguhnya ada di features/ masing-masing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/permissions/permission_manager.dart';
import 'features/explorer_ui/explorer_screen.dart';

void main() {
  runApp(const ProviderScope(child: DalXApp()));
}

// Root Internal Storage Android standar. Untuk Sub-Fase 0a ini masih
// hardcoded; jadi bagian dari Settings > Layar Awal begitu Sub-Fase
// 0b/Fase 7 berjalan.
const _internalStorageRoot = '/storage/emulated/0';

class DalXApp extends StatelessWidget {
  const DalXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DalX',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _PermissionGate(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    const dalxAccent = Color(0xFF0A84FF);
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: dalxAccent,
        brightness: brightness,
      ),
      fontFamily: 'Poppins', // aset font ditambahkan saat siap
    );
  }
}

/// Cek & minta izin storage sebelum masuk ke Explorer. Ini "pintu
/// masuk" app — tanpa izin ini, DalX tidak bisa berfungsi sama
/// sekali (lihat daftar fitur core: akses & r/w hidden files).
class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  final _permissionManager = PermissionManager();
  bool _isChecking = true;
  bool _isGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await _permissionManager.hasStorageAccess();
    setState(() {
      _isGranted = granted;
      _isChecking = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _isChecking = true);
    final granted = await _permissionManager.requestStorageAccess();
    setState(() {
      _isGranted = granted;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isGranted) {
      return const ExplorerScreen(rootPath: _internalStorageRoot);
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 64, color: Color(0xFF0A84FF)),
              const SizedBox(height: 16),
              const Text(
                'DalX butuh izin akses penyimpanan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Untuk mengelola semua file kamu, termasuk file '
                'tersembunyi, DalX perlu izin akses penyimpanan penuh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _requestPermission,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0A84FF),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('Berikan Izin'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
