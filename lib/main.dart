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
import 'features/storage_overview/storage_overview_screen.dart';

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
    final isDark = brightness == Brightness.dark;

    // ColorScheme DITULIS MANUAL, bukan ColorScheme.fromSeed(). Alasan:
    // fromSeed menghasilkan "tonal palette" ala Material 3 — banyak
    // varian warna turunan dari aksen yang kontrasnya nanggung (surface
    // container, surface tint, dst), bertentangan sama filosofi
    // "Function First, Color Last" / monochrome-first DalX (satu aksen
    // solid #0A84FF, sisanya abu-abu/hitam/putih tegas). Nilai di
    // bawah dipilih biar kontras teks-vs-background jelas di kedua
    // mode, bukan diserahkan ke algoritma tonal Material 3.
    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: dalxAccent,
            onPrimary: Colors.white,
            secondary: dalxAccent,
            onSecondary: Colors.white,
            surface: Color(0xFF161616),
            onSurface: Color(0xFFF2F2F2),
            surfaceContainerHighest: Color(0xFF232323),
            onSurfaceVariant: Color(0xFFC7C7C7),
            outline: Color(0xFF3A3A3A),
            error: Color(0xFFFF6B6B),
          )
        : const ColorScheme.light(
            primary: dalxAccent,
            onPrimary: Colors.white,
            secondary: dalxAccent,
            onSecondary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1A1A1A),
            surfaceContainerHighest: Color(0xFFF0F0F0),
            onSurfaceVariant: Color(0xFF55555A),
            outline: Color(0xFFDADADA),
            error: Color(0xFFD32F2F),
          );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFAFAFA),
      fontFamily: 'Poppins',
      // Font default Poppins Regular (w400) kelihatan tipis di layar
      // kecil — dinaikkan ke w500 (Medium) buat body text & w600
      // (SemiBold) buat judul, tanpa perlu ganti-ganti FontWeight
      // manual di tiap Text() satu-satu di seluruh app.
      textTheme: baseTextTheme.copyWith(
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: baseTextTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? dalxAccent : null,
        ),
      ),
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
class _RouteAfterPermission extends ConsumerStatefulWidget {
  final IntentBridge intentBridge;
  const _RouteAfterPermission({required this.intentBridge});

  @override
  ConsumerState<_RouteAfterPermission> createState() => _RouteAfterPermissionState();
}

class _RouteAfterPermissionState extends ConsumerState<_RouteAfterPermission> {
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

    // Launch normal (user tap icon app, bukan lewat Share/Open With/
    // Document Picker app lain) — pakai "Layar Awal" dari Settings.
    // Sebelumnya baris ini hardcode ExplorerScreen(Internal Storage),
    // beda sama default yang ditulis di Settings ("Storage Overview
    // (default)") — user lihat langsung bedanya, sekarang disamakan:
    // homePath null = StorageOverviewScreen, non-null = folder pilihan
    // user.
    if (intent == null || intent.action == IncomingIntentAction.none) {
      final homePath = ref.watch(homePathProvider);
      return homePath == null
          ? const StorageOverviewScreen()
          : ExplorerScreen(rootPath: homePath);
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

    final homePath = ref.watch(homePathProvider);
    return homePath == null
        ? const StorageOverviewScreen()
        : ExplorerScreen(rootPath: homePath);
  }
}
