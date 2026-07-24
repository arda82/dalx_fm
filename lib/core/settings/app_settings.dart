// core/settings/app_settings.dart
//
// Pengaturan aplikasi yang persist lintas sesi (SharedPreferences).
// Fase 7 — isi lengkap sesuai ARCHITECTURE.md bagian 6: Theme,
// Language, Explorer defaults (Default View/Sort/Hidden/Font Size/
// Layar Awal), plus Root Mode yang sudah ada dari Fase 1.5.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_strings.dart';

const _rootModeKey = 'dalx_root_mode';
const _themeModeKey = 'dalx_theme_mode';
const _localeKey = 'dalx_locale';
const _defaultViewKey = 'dalx_default_view'; // 'list' | 'grid'
const _defaultSortKey = 'dalx_default_sort'; // 'name' | 'date' | 'size'
const _defaultHiddenKey = 'dalx_default_hidden'; // bool
const _fontScaleKey = 'dalx_font_scale'; // double
const _homePathKey = 'dalx_home_path'; // String? (null = default Storage Overview)

class RootModeNotifier extends StateNotifier<bool> {
  RootModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_rootModeKey) ?? false;
  }

  /// User yang menentukan sendiri lewat toggle di Settings — DalX
  /// TIDAK mencoba mendeteksi root otomatis (heuristik su binary/build
  /// tags tidak reliable di semua device, sesuai keputusan Damar).
  Future<void> setRootMode(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rootModeKey, value);
  }
}

final rootModeProvider = StateNotifierProvider<RootModeNotifier, bool>((ref) {
  return RootModeNotifier();
});

// ---------------- Theme (Dark/Light/Ikuti Sistem) ----------------

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModeKey);
    state = switch (saved) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

// ---------------- Language (Indonesia / English) ----------------

class LocaleNotifier extends StateNotifier<AppLocale> {
  LocaleNotifier() : super(AppLocale.id) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_localeKey) == 'en' ? AppLocale.en : AppLocale.id;
  }

  Future<void> setLocale(AppLocale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale == AppLocale.en ? 'en' : 'id');
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLocale>((ref) {
  return LocaleNotifier();
});

// ---------------- Font Size (skala teks Explorer) ----------------
//
// Diterapkan lewat MediaQuery/TextScaler yang membungkus body
// ExplorerScreen SAJA (lihat explorer_screen.dart) — sesuai desain
// final "Font Size" ditaruh di bawah section Explorer, bukan
// pengaturan skala teks seluruh app.

class FontScaleNotifier extends StateNotifier<double> {
  FontScaleNotifier() : super(1.0) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble(_fontScaleKey) ?? 1.0;
  }

  Future<void> setFontScale(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, scale);
  }
}

final fontScaleProvider = StateNotifierProvider<FontScaleNotifier, double>((ref) {
  return FontScaleNotifier();
});

// ---------------- Explorer Defaults (Default View/Sort/Hidden) ----------------
//
// Primitif polos (String/bool) SENGAJA dipakai di sini, BUKAN
// ViewMode/SortMode dari explorer_state.dart — core/ tidak boleh
// depend ke features/ (arah dependency-nya kebalik, lihat
// ARCHITECTURE.md bagian 3). explorer_state.dart yang menerjemahkan
// primitif ini ke enum-nya sendiri saat inisialisasi.

class ExplorerDefaults {
  final String defaultView; // 'list' | 'grid'
  final String defaultSort; // 'name' | 'date' | 'size'
  final bool defaultHidden;

  const ExplorerDefaults({
    this.defaultView = 'list',
    this.defaultSort = 'name',
    this.defaultHidden = false,
  });

  ExplorerDefaults copyWith({String? defaultView, String? defaultSort, bool? defaultHidden}) {
    return ExplorerDefaults(
      defaultView: defaultView ?? this.defaultView,
      defaultSort: defaultSort ?? this.defaultSort,
      defaultHidden: defaultHidden ?? this.defaultHidden,
    );
  }
}

class ExplorerDefaultsNotifier extends StateNotifier<ExplorerDefaults> {
  ExplorerDefaultsNotifier() : super(const ExplorerDefaults()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ExplorerDefaults(
      defaultView: prefs.getString(_defaultViewKey) ?? 'list',
      defaultSort: prefs.getString(_defaultSortKey) ?? 'name',
      defaultHidden: prefs.getBool(_defaultHiddenKey) ?? false,
    );
  }

  Future<void> setDefaultView(String view) async {
    state = state.copyWith(defaultView: view);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultViewKey, view);
  }

  Future<void> setDefaultSort(String sort) async {
    state = state.copyWith(defaultSort: sort);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultSortKey, sort);
  }

  Future<void> setDefaultHidden(bool value) async {
    state = state.copyWith(defaultHidden: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultHiddenKey, value);
  }
}

final explorerDefaultsProvider = StateNotifierProvider<ExplorerDefaultsNotifier, ExplorerDefaults>((ref) {
  return ExplorerDefaultsNotifier();
});

// ---------------- Layar Awal (Home Path) ----------------
//
// null = default (StorageOverviewScreen, perilaku lama). Non-null =
// user mengarahkan Layar Awal ke folder tertentu lewat folder picker
// di Settings — app_drawer.dart & explorer_screen.dart (logic
// kembali ke Layar Awal pas back-navigation) baca ini buat tau harus
// buka StorageOverviewScreen atau ExplorerScreen(rootPath: path).

class HomePathNotifier extends StateNotifier<String?> {
  HomePathNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_homePathKey);
  }

  Future<void> setHomePath(String? path) async {
    state = path;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_homePathKey);
    } else {
      await prefs.setString(_homePathKey, path);
    }
  }
}

final homePathProvider = StateNotifierProvider<HomePathNotifier, String?>((ref) {
  return HomePathNotifier();
});