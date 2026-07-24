// features/settings/settings_screen.dart
//
// Settings lengkap sesuai ARCHITECTURE.md bagian 6:
// - Tampilan Aplikasi: Theme, Language
// - Explorer: Default View, Default Sort, Hidden File Default, Font
//   Size, Layar Awal (path picker) — plus Root Mode (Fase 1.5, pindah
//   ke sini dari versi minimal sebelumnya)
// - Tentang: Version info

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_strings.dart';
import '../../core/settings/app_settings.dart';
import '../explorer_ui/folder_picker_screen.dart';

const _dalxAccent = Color(0xFF0A84FF);
const _internalStorageRoot = '/storage/emulated/0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final rootMode = ref.watch(rootModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final explorerDefaults = ref.watch(explorerDefaultsProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final homePath = ref.watch(homePathProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        children: [
          _SectionHeader(title: strings.settingsSectionAppearance),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(strings.settingsTheme),
            subtitle: Text(_themeModeLabel(strings, themeMode)),
            onTap: () => _showThemeSheet(context, ref, strings, themeMode),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(strings.settingsLanguage),
            subtitle: Text(locale == AppLocale.en ? strings.settingsLanguageEn : strings.settingsLanguageId),
            onTap: () => _showLanguageSheet(context, ref, strings, locale),
          ),
          const Divider(height: 24),
          _SectionHeader(title: strings.settingsSectionExplorer),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: Text(strings.settingsDefaultView),
            subtitle: Text(explorerDefaults.defaultView == 'grid' ? strings.gridView : strings.listView),
            onTap: () => _showDefaultViewSheet(context, ref, strings, explorerDefaults.defaultView),
          ),
          ListTile(
            leading: const Icon(Icons.sort_outlined),
            title: Text(strings.settingsDefaultSort),
            subtitle: Text(_sortLabel(strings, explorerDefaults.defaultSort)),
            onTap: () => _showDefaultSortSheet(context, ref, strings, explorerDefaults.defaultSort),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(strings.settingsHiddenDefault),
            subtitle: Text(explorerDefaults.defaultHidden ? strings.settingsHiddenDefaultOn : strings.settingsHiddenDefaultOff),
            value: explorerDefaults.defaultHidden,
            activeColor: _dalxAccent,
            onChanged: (value) => ref.read(explorerDefaultsProvider.notifier).setDefaultHidden(value),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_outlined),
            title: Text(strings.settingsFontSize),
            subtitle: Text(_fontScaleLabel(strings, fontScale)),
            onTap: () => _showFontSizeSheet(context, ref, strings, fontScale),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: Text(strings.settingsHomePath),
            subtitle: Text(homePath ?? strings.settingsHomePathDefault),
            onTap: () => _handleHomePathTap(context, ref, homePath),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(strings.settingsRootMode),
            subtitle: Text(
              rootMode ? strings.settingsRootModeOnDesc : strings.settingsRootModeOffDesc,
              style: const TextStyle(fontSize: 12),
            ),
            value: rootMode,
            activeColor: _dalxAccent,
            onChanged: (value) => ref.read(rootModeProvider.notifier).setRootMode(value),
          ),
          const Divider(height: 24),
          _SectionHeader(title: strings.settingsSectionAbout),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.settingsAppVersion),
            subtitle: const Text('DalX v0.0.1'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(strings.settingsLicense),
            subtitle: const Text('MIT License'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _themeModeLabel(AppStrings s, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return s.settingsThemeDark;
      case ThemeMode.light:
        return s.settingsThemeLight;
      case ThemeMode.system:
        return s.settingsThemeSystem;
    }
  }

  String _sortLabel(AppStrings s, String sort) {
    switch (sort) {
      case 'date':
        return s.sortByDate;
      case 'size':
        return s.sortBySize;
      default:
        return s.sortByName;
    }
  }

  String _fontScaleLabel(AppStrings s, double scale) {
    if (scale <= 0.9) return s.settingsFontSizeSmall;
    if (scale <= 1.05) return s.settingsFontSizeNormal;
    if (scale <= 1.2) return s.settingsFontSizeLarge;
    return s.settingsFontSizeExtraLarge;
  }

  void _showThemeSheet(BuildContext context, WidgetRef ref, AppStrings s, ThemeMode current) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadioTile(
              label: s.settingsThemeDark,
              selected: current == ThemeMode.dark,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsThemeLight,
              selected: current == ThemeMode.light,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsThemeSystem,
              selected: current == ThemeMode.system,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref, AppStrings s, AppLocale current) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadioTile(
              label: s.settingsLanguageId,
              selected: current == AppLocale.id,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(AppLocale.id);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsLanguageEn,
              selected: current == AppLocale.en,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(AppLocale.en);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDefaultViewSheet(BuildContext context, WidgetRef ref, AppStrings s, String current) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadioTile(
              label: s.listView,
              selected: current == 'list',
              onTap: () {
                ref.read(explorerDefaultsProvider.notifier).setDefaultView('list');
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.gridView,
              selected: current == 'grid',
              onTap: () {
                ref.read(explorerDefaultsProvider.notifier).setDefaultView('grid');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDefaultSortSheet(BuildContext context, WidgetRef ref, AppStrings s, String current) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadioTile(
              label: s.sortByName,
              selected: current == 'name',
              onTap: () {
                ref.read(explorerDefaultsProvider.notifier).setDefaultSort('name');
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.sortByDate,
              selected: current == 'date',
              onTap: () {
                ref.read(explorerDefaultsProvider.notifier).setDefaultSort('date');
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.sortBySize,
              selected: current == 'size',
              onTap: () {
                ref.read(explorerDefaultsProvider.notifier).setDefaultSort('size');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFontSizeSheet(BuildContext context, WidgetRef ref, AppStrings s, double current) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadioTile(
              label: s.settingsFontSizeSmall,
              selected: current <= 0.9,
              onTap: () {
                ref.read(fontScaleProvider.notifier).setFontScale(0.85);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsFontSizeNormal,
              selected: current > 0.9 && current <= 1.05,
              onTap: () {
                ref.read(fontScaleProvider.notifier).setFontScale(1.0);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsFontSizeLarge,
              selected: current > 1.05 && current <= 1.2,
              onTap: () {
                ref.read(fontScaleProvider.notifier).setFontScale(1.15);
                Navigator.pop(context);
              },
            ),
            _RadioTile(
              label: s.settingsFontSizeExtraLarge,
              selected: current > 1.2,
              onTap: () {
                ref.read(fontScaleProvider.notifier).setFontScale(1.3);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleHomePathTap(BuildContext context, WidgetRef ref, String? currentHomePath) async {
    final strings = AppStrings.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined, color: _dalxAccent),
              title: Text(strings.settingsHomePathChoose),
              onTap: () => Navigator.pop(context, 'choose'),
            ),
            if (currentHomePath != null)
              ListTile(
                leading: const Icon(Icons.restart_alt, color: _dalxAccent),
                title: Text(strings.settingsHomePathReset),
                onTap: () => Navigator.pop(context, 'reset'),
              ),
          ],
        ),
      ),
    );

    if (choice == 'reset') {
      await ref.read(homePathProvider.notifier).setHomePath(null);
    } else if (choice == 'choose') {
      if (!context.mounted) return;
      final picked = await showFolderPicker(
        context,
        ref,
        initialPath: _internalStorageRoot,
        title: strings.settingsHomePath,
      );
      if (picked != null) {
        await ref.read(homePathProvider.notifier).setHomePath(picked);
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _dalxAccent),
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: selected ? const Icon(Icons.check, color: _dalxAccent) : null,
      onTap: onTap,
    );
  }
}
