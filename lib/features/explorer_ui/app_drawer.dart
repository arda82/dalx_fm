// features/explorer_ui/app_drawer.dart
//
// Sidebar drawer DalX sesuai desain final:
// Layar Awal, Internal Storage, SD Card, USB OTG, Favorites,
// Task Queue, Bersihkan Cache (aksi langsung), Settings, About.
//
// Fase 1.5: SD Card & USB OTG aktif — query lewat storageAccessProvider
// (core/storage_access), cari volume yang cocok lewat findByHint().
// Fase 2: Favorites aktif — lewat favoritesProvider.
// Fase 7: Settings lengkap (Theme/Language/Explorer defaults/dll).
// Layar Awal sekarang baca homePathProvider — null = StorageOverview-
// Screen (default), non-null = ExplorerScreen(rootPath: itu), user
// atur lewat Settings > Layar Awal. Bersihkan Cache aktif, pakai
// CacheManager (core/cache/cache_manager.dart) — hitung ukuran dulu,
// minta konfirmasi, baru hapus.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/localization/app_strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage_access/storage_access.dart';
import '../favorites/favorites_screen.dart';
import '../settings/settings_screen.dart';
import '../storage_overview/storage_overview_screen.dart';
import '../task_queue/task_queue_screen.dart';
import 'explorer_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final homePath = ref.watch(homePathProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(strings),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerTile(
                    icon: Icons.dashboard_outlined,
                    label: strings.drawerHome,
                    active: true,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => homePath == null
                              ? const StorageOverviewScreen()
                              : ExplorerScreen(rootPath: homePath),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.smartphone_outlined,
                    label: strings.drawerInternalStorage,
                    onTap: () {
                      Navigator.pop(context);
                      // rootPath Internal Storage ditentukan di main.dart
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExplorerScreen(
                            rootPath: '/storage/emulated/0',
                          ),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.sd_card_outlined,
                    label: strings.drawerSdCard,
                    onTap: () => _openExternalStorage(
                      context,
                      ref,
                      hint: 'sd',
                      label: strings.drawerSdCard,
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.usb_outlined,
                    label: strings.drawerUsbOtg,
                    onTap: () => _openExternalStorage(
                      context,
                      ref,
                      hint: 'usb',
                      label: strings.drawerUsbOtg,
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.star_outline,
                    label: strings.drawerFavorites,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.download_outlined,
                    label: strings.drawerTaskQueue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TaskQueueScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.cleaning_services_outlined,
                    label: strings.drawerClearCache,
                    onTap: () => _handleClearCache(context, strings),
                  ),
                  const Divider(height: 1),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    label: strings.drawerSettings,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.info_outline,
                    label: strings.drawerAbout,
                    disabled: true,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'v0.0.1 · MIT License',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bersihkan Cache (Fase 7): hitung ukuran cache dulu (bukan
  // langsung hapus tanpa konfirmasi — walau "aksi langsung" di
  // ARCHITECTURE.md, konfirmasi tetap masuk akal buat aksi yang
  // menghapus data, sekecil apa pun dampaknya). Kalau cache kosong,
  // langsung kasih tau tanpa dialog konfirmasi (nggak ada gunanya).
  Future<void> _handleClearCache(BuildContext context, AppStrings strings) async {
    Navigator.pop(context); // tutup drawer dulu
    final cacheManager = CacheManager();
    final sizeBytes = await cacheManager.getCacheSize();

    if (!context.mounted) return;

    if (sizeBytes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.cacheEmpty)),
      );
      return;
    }

    final sizeLabel = CacheManager.formatBytes(sizeBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.cacheClearConfirmTitle),
        content: Text(strings.cacheClearConfirmBody(sizeLabel)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.drawerClearCache),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final freedBytes = await cacheManager.clearCache();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.cacheClearedBody(CacheManager.formatBytes(freedBytes)))),
    );
  }

  // Fase 1.5: query volume SD Card/USB OTG lewat storageAccessProvider,
  // cari yang labelnya cocok [hint] ("sd"/"usb"). Ketemu → tutup
  // drawer, masuk Explorer. Gak ketemu → tutup drawer, kasih tau
  // lewat snackbar (bukan silent fail).
  Future<void> _openExternalStorage(
    BuildContext context,
    WidgetRef ref, {
    required String hint,
    required String label,
  }) async {
    final storageAccess = ref.read(storageAccessProvider);
    final volumes = await storageAccess.queryVolumes();

    final match = storageAccess.findByHint(volumes, hint);

    if (!context.mounted) return;
    Navigator.pop(context); // tutup drawer

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).notMounted(label))),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: match.path)),
    );
  }

  Widget _buildHeader(AppStrings strings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A84FF), Color(0xFF00C6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: const Text(
              'D',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DalX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(strings.drawerTagline, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback? onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    this.active = false,
    this.disabled = false,
    this.onTap,
  });

  static const dalxAccent = Color(0xFF0A84FF);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: active ? dalxAccent : (disabled ? Colors.grey.shade400 : null),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: active ? dalxAccent : (disabled ? Colors.grey.shade400 : null),
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      onTap: disabled ? null : onTap,
    );
  }
}