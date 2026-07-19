// features/storage_overview/storage_overview_screen.dart
//
// Layar "Home" / Layar Awal default — overview Internal Storage, SD
// Card, USB OTG, dan RAM, sesuai mockup yang disetujui. Data storage
// & RAM diambil lewat DeviceInfoManager (platform channel native),
// bukan hardcode.
//
// Sub-Fase 0b: SD Card dan USB OTG masih ditampilkan redup/nonaktif
// (belum ada deteksi mount device eksternal — itu StorageMounted
// event, menyusul di Fase 1/8). Persentase dihitung otomatis dari
// angka byte asli, bukan diketik manual — supaya progress bar dan
// teks selalu sinkron.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/device_info/device_info_manager.dart';
import '../explorer_ui/app_drawer.dart';

const _dalxAccent = Color(0xFF0A84FF);

class StorageOverviewScreen extends ConsumerWidget {
  const StorageOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Storage'),
      ),
      drawer: const AppDrawer(),
      body: FutureBuilder(
        future: _loadAll(ref),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: _dalxAccent));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _StorageCard(
                icon: Icons.smartphone_outlined,
                label: 'Internal Storage',
                info: data.storage,
              ),
              const SizedBox(height: 12),
              const _DisabledStorageCard(icon: Icons.sd_card_outlined, label: 'SD Card'),
              const SizedBox(height: 12),
              const _DisabledStorageCard(icon: Icons.usb_outlined, label: 'USB OTG', subtitle: 'Tidak terpasang'),
              const SizedBox(height: 12),
              _RamCard(info: data.ram),
            ],
          );
        },
      ),
    );
  }

  Future<_OverviewData> _loadAll(WidgetRef ref) async {
    final manager = ref.read(deviceInfoManagerProvider);
    final storage = await manager.getStorageInfo();
    final ram = await manager.getRamInfo();
    return _OverviewData(storage: storage, ram: ram);
  }
}

class _OverviewData {
  final StorageInfo storage;
  final RamInfo ram;
  const _OverviewData({required this.storage, required this.ram});
}

class _StorageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final StorageInfo info;

  const _StorageCard({required this.icon, required this.label, required this.info});

  @override
  Widget build(BuildContext context) {
    final usedGB = info.usedBytes / (1024 * 1024 * 1024);
    final totalGB = info.totalBytes / (1024 * 1024 * 1024);
    final percent = (info.usedFraction * 1000).round() / 10; // 1 desimal

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _dalxAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: _dalxAccent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    Text(
                      '${usedGB.toStringAsFixed(1)} GB ($percent%) dari ${totalGB.toStringAsFixed(1)} GB',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: info.usedFraction,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: _dalxAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RamCard extends StatelessWidget {
  final RamInfo info;
  const _RamCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final usedGB = info.usedBytes / (1024 * 1024 * 1024);
    final totalGB = info.totalBytes / (1024 * 1024 * 1024);
    final percent = (info.usedFraction * 1000).round() / 10;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RAM', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          const SizedBox(height: 6),
          Text(
            '${usedGB.toStringAsFixed(1)} GB ($percent%) dari ${totalGB.toStringAsFixed(1)} GB',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: info.usedFraction,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisabledStorageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _DisabledStorageCard({required this.icon, required this.label, this.subtitle = 'Tidak terpasang'});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _dalxAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: _dalxAccent, size: 19),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
