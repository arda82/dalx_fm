// core/settings/app_settings.dart
//
// Pengaturan aplikasi yang persist lintas sesi (SharedPreferences).
// Untuk sekarang baru Root Mode — dipakai ExplorerScreen buat nentuin
// perilaku tombol back begitu history folder habis (lihat catatan di
// explorer_screen.dart). Bagian Settings lengkap (Theme, Language,
// Explorer defaults, dll — ARCHITECTURE.md bagian 6) tetap Fase 7;
// modul ini sengaja diisolasi kecil supaya gampang digabung nanti,
// bukan mendahului Fase 7 secara penuh.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rootModeKey = 'dalx_root_mode';

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