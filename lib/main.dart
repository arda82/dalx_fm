// main.dart
//
// Eksekutor DalX. Tanggung jawabnya: setup Riverpod, tema, permission
// gate, lalu arahkan ke Explorer — kalau DalX dibuka lewat intent
// eksternal (Open With, Share, Document Picker), arahkan sesuai itu.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/localization/app_strings.dart';
import 'core/permissions/permission_manager.dart';
import 'core/native_bridge/intent_bridge.dart';
import 'core/native_bridge/native_bridge.dart';
import 'core/settings/app_settings.dart';
import 'features/explorer_ui/explorer_screen.dart';
import 'features/media_scanner/media_scanner_listener.dart';

void main() {
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

const _internalStorageRoot = '/storage/emulated/0';

class DalXApp extends ConsumerWidget {
  const DalXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'DalX',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      locale: Locale(locale == AppLocale.en ? 'en' : 'id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _PermissionGate(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    const dalxAccent = Color(0xFF0A84FF);
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: dalxAccent, brightness: brightness),
      fontFamily: 'Poppins',
    );
  }
}

class _PermissionGate extends ConsumerStatefulWidget {
  const _PermissionGate();

  @override
  ConsumerState<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<_PermissionGate> {
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isGranted) {
      // Aktifkan Media Scanner listener sekali di sini — dia dengar
      // event lewat event bus selama app hidup (lihat
      // media_scanner_listener.dart).
      ref.watch(mediaScannerListenerProvider);
      return _RouteAfterPermission(intentBridge: ref.watch(intentBridgeProvider));
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
              Text(
                AppStrings.of(context).permissionTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(context).permissionBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _requestPermission,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0A84FF)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(AppStrings.of(context).permissionGrantButton),
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
                    AppStrings.of(context).permissionErrorDetail(_errorMessage!),
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

/// Baca intent awal (kalau DalX dibuka dari Open With/Share/Document
/// Picker), lalu arahkan ke Explorer dengan konfigurasi yang sesuai.
class _RouteAfterPermission extends StatefulWidget {
  final IntentBridge intentBridge;
  const _RouteAfterPermission({required this.intentBridge});

  @override
  State<_RouteAfterPermission> createState() => _RouteAfterPermissionState();
}

class _RouteAfterPermissionState extends State<_RouteAfterPermission> {
  bool _isResolving = true;
  IncomingIntent? _intent;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final intent = await widget.intentBridge.getInitialIntent();
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _isResolving = false;
      });
    } catch (e) {
      debugPrint('Gagal baca initial intent: $e');
      if (!mounted) return;
      setState(() => _isResolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isResolving) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final intent = _intent;
    if (intent == null || intent.action == IncomingIntentAction.none) {
      return const ExplorerScreen(rootPath: _internalStorageRoot);
    }

    if (intent.action == IncomingIntentAction.getContent) {
      return const ExplorerScreen(rootPath: _internalStorageRoot, pickMode: true);
    }

    if (intent.paths.isNotEmpty) {
      final firstPath = intent.paths.first;
      final parentPath = firstPath.contains('/')
          ? firstPath.substring(0, firstPath.lastIndexOf('/'))
          : _internalStorageRoot;
      return ExplorerScreen(rootPath: parentPath);
    }

    return const ExplorerScreen(rootPath: _internalStorageRoot);
  }
}
