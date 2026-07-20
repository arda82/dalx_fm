// features/explorer_ui/app_drawer.dart
//
// Sidebar drawer DalX sesuai desain final:
// Layar Awal, Internal Storage, SD Card, USB OTG, Favorites,
// Task Queue, Bersihkan Cache (aksi langsung), Settings, About.
//
// Fase 1.5: SD Card & USB OTG aktif — query lewat storageAccessProvider
// (core/storage_access), cari volume yang cocok lewat findByHint().
// Favorites, Settings menyusul di fase berikutnya sesuai roadmap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage_access/storage_access.dart';
import '../storage_overview/storage_overview_screen.dart';
import '../task_queue/task_queue_screen.dart';
import 'explorer_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerTile(
                    icon: Icons.dashboard_outlined,
                    label: 'Layar Awal',
                    active: true,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StorageOverviewScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.smartphone_outlined,
                    label: 'Internal Storage',
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
                    label: 'SD Card',
                    onTap: () => _openExternalStorage(
                      context,
                      ref,
                      hint: 'sd',
                      label: 'SD Card',
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.usb_outlined,
                    label: 'USB OTG',
                    onTap: () => _openExternalStorage(
                      context,
                      ref,
                      hint: 'usb',
                      label: 'USB OTG',
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.star_outline,
                    label: 'Favorites',
                    disabled: true, // aktif di Fase 2
                  ),
                  _DrawerTile(
                    icon: Icons.download_outlined,
                    label: 'Task Queue',
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
                    label: 'Bersihkan Cache',
                    disabled: true, // aktif di Fase 7
                  ),
                  const Divider(height: 1),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    disabled: true, // aktif di Fase 7
                  ),
                  _DrawerTile(
                    icon: Icons.info_outline,
                    label: 'About',
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
        SnackBar(content: Text('Tidak ada $label terpasang')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: match.path)),
    );
  }

  Widget _buildHeader() {
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
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DalX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Explore · Find · Manage', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
