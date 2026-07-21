// features/settings/settings_screen.dart
//
// Settings minimal — baru berisi Root Mode. Bagian Settings lengkap
// (Theme, Language, Explorer defaults — ARCHITECTURE.md bagian 6)
// menyusul Fase 7. Root Mode dibuat lebih awal karena dibutuhkan
// untuk perilaku tombol back di Explorer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/app_settings.dart';

const _dalxAccent = Color(0xFF0A84FF);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootMode = ref.watch(rootModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Root Mode'),
            subtitle: Text(
              rootMode
                  ? 'Aktif — di ujung folder, tombol back naik terus sampai filesystem root (/)'
                  : 'Nonaktif — di ujung folder, tombol back kembali ke Layar Awal',
              style: const TextStyle(fontSize: 12),
            ),
            value: rootMode,
            activeColor: _dalxAccent,
            onChanged: (value) => ref.read(rootModeProvider.notifier).setRootMode(value),
          ),
        ],
      ),
    );
  }
}