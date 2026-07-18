// main.dart
//
// Eksekutor DalX. Tanggung jawabnya cuma: setup Riverpod, tentukan
// tema, dan arahkan ke halaman pertama (cek permission dulu, baru
// Explorer). Logic sesungguhnya ada di features/ masing-masing.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/permissions/permission_manager.dart';
import 'features/explorer_ui/explorer_screen.dart';

void main() {
  // Jaring pengaman crash global — Sub-Fase 0a belum punya Error
  // Logging (itu baru masuk Fase 7), tapi ini minimal mencegah app
  // mati diam-diam tanpa jejak sama sekali kalau ada exception
  // tak terduga di luar yang sudah ditangani lokal.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError tertangkap: ${details.exception}');
  };

  runZonedGuarded(() {
    runApp(const ProviderScope(child: DalXApp()));
  }, (error, stackTrace) {
    debugPrint('Error tak tertangkap: $error\n$stackTrace');
  });
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    // Dibungkus try-catch: kalau permission_handler melempar exception
    // (mis. plugin belum ter-register dengan benar di sisi native),
    // app akan menampilkan pesan error alih-alih crash diam-diam
    // tanpa keterangan sama sekali.
    try {
      final granted = await _permissionManager.hasStorageAccess();
      if (!mounted) return;
      setState(() {
        _isGranted = granted;
        _isChecking = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error saat cek permission: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });
    try {
      final granted = await _permissionManager.requestStorageAccess();
      if (!mounted) return;
      setState(() {
        _isGranted = granted;
        _isChecking = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error saat minta permission: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _errorMessage = e.toString();
      });
    }
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
              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Detail error: $_errorMessage',
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
