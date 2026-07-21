// features/storage_overview/storage_overview_screen.dart
//
// Layar "Home" / Layar Awal default — overview Internal Storage, SD
// Card, USB OTG, dan RAM, sesuai mockup yang disetujui. Data storage
// & RAM diambil lewat DeviceInfoManager (platform channel native),
// bukan hardcode.
//
// Fase 1.5: SD Card & USB OTG sekarang aktif — dideteksi lewat
// core/storage_access (StorageManager, real-time). Kalau gak ada
// device removable ke-mount, kartu tetap tampil redup "Tidak
// terpasang" seperti sebelumnya. Persentase dihitung otomatis dari
// angka byte asli, bukan diketik manual — supaya progress bar dan
// teks selalu sinkron.
//
// RAM real-time: Internal Storage/SD Card/USB OTG di-fetch SEKALI
// (kapasitasnya nggak berubah tiap detik), tapi RAM di-refresh
// berkala lewat Timer.periodic — sebelumnya RAM ikut ke-snapshot
// cuma sekali bareng data lain lewat FutureBuilder, jadi kelihatan
// "dummy"/diam walau device beneran pakai/lepas RAM real-time.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/device_info/device_info_manager.dart';
import '../../core/native_bridge/native_bridge.dart';
import '../../core/storage_access/storage_access.dart';
import '../explorer_ui/app_drawer.dart';
import '../explorer_ui/explorer_screen.dart';

const _dalxAccent = Color(0xFF0A84FF);

// Jendela waktu untuk pola "tekan sekali lagi untuk keluar" — tekan
// back kedua harus terjadi dalam rentang ini, kalau tidak dianggap
// tekan pertama yang baru lagi.
const _exitPressWindow = Duration(seconds: 2);

// Interval refresh RAM. 2 detik cukup responsif buat kelihatan
// "hidup" tanpa terlalu sering manggil platform channel.
const _ramRefreshInterval = Duration(seconds: 2);

class StorageOverviewScreen extends ConsumerStatefulWidget {
  const StorageOverviewScreen({super.key});

  @override
  ConsumerState<StorageOverviewScreen> createState() => _StorageOverviewScreenState();
}

class _StorageOverviewScreenState extends ConsumerState<StorageOverviewScreen> {
  DateTime? _lastBackPress;

  _OverviewData? _data;
  RamInfo? _ram;
  Timer? _ramTimer;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _ramTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final data = await _loadAll();
      if (!mounted) return;
      setState(() {
        _data = data;
        _ram = data.ram;
        _loadError = null;
      });
      _startRamPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  void _startRamPolling() {
    _ramTimer?.cancel();
    _ramTimer = Timer.periodic(_ramRefreshInterval, (_) => _refreshRam());
  }

  Future<void> _refreshRam() async {
    if (!mounted) return;
    try {
      final manager = ref.read(deviceInfoManagerProvider);
      final ram = await manager.getRamInfo();
      if (!mounted) return;
      setState(() => _ram = ram);
    } catch (_) {
      // Gagal satu kali polling RAM — diamkan aja, coba lagi di
      // siklus berikutnya. Jangan bikin seluruh layar error cuma
      // gara-gara satu polling meleset.
    }
  }

  // StorageOverviewScreen adalah root Navigator (halaman pertama saat
  // app dibuka, lihat main.dart) — jadi ini satu-satunya tempat yang
  // perlu pola "tekan dua kali untuk keluar". Layar lain (Explorer,
  // Task Queue, dll) di-push di atas ini, jadi back mereka otomatis
  // kembali ke sini lebih dulu sebelum sempat memicu exit.
  void _handleBackPress() {
    final now = DateTime.now();
    final isSecondPress = _lastBackPress != null && now.difference(_lastBackPress!) < _exitPressWindow;

    if (isSecondPress) {
      SystemNavigator.pop();
    } else {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: _exitPressWindow,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
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
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadError != null) {
      return Center(child: Text('Terjadi kesalahan: $_loadError'));
    }
    final data = _data;
    if (data == null) {
      return const Center(child: CircularProgressIndicator(color: _dalxAccent));
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _StorageCard(
          icon: Icons.smartphone_outlined,
          label: 'Internal Storage',
          info: data.storage,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ExplorerScreen(
                rootPath: '/storage/emulated/0',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildExternalCard(
          context,
          hint: 'sd',
          fallbackIcon: Icons.sd_card_outlined,
          fallbackLabel: 'SD Card',
          volumes: data.removableVolumes,
          capacities: data.volumeCapacities,
          storageAccess: data.storageAccess,
        ),
        const SizedBox(height: 12),
        _buildExternalCard(
          context,
          hint: 'usb',
          fallbackIcon: Icons.usb_outlined,
          fallbackLabel: 'USB OTG',
          volumes: data.removableVolumes,
          capacities: data.volumeCapacities,
          storageAccess: data.storageAccess,
        ),
        const SizedBox(height: 12),
        // RAM dipisah dari `data` — ini yang di-refresh berkala lewat
        // _ram, bukan snapshot statis dari _loadAll.
        _RamCard(info: _ram ?? data.ram),
      ],
    );
  }

  Future<_OverviewData> _loadAll() async {
    final manager = ref.read(deviceInfoManagerProvider);
    final nativeBridge = ref.read(nativeBridgeProvider);
    final storageAccess = ref.read(storageAccessProvider);

    final storage = await manager.getStorageInfo();
    final ram = await manager.getRamInfo();
    final volumes = await storageAccess.queryVolumes();
    final removable = storageAccess.removableVolumes(volumes);

    final capacities = <String, Map<String, int>>{};
    for (final v in removable) {
      capacities[v.path] = await nativeBridge.getStorageCapacity(v.path);
    }

    return _OverviewData(
      storage: storage,
      ram: ram,
      removableVolumes: removable,
      volumeCapacities: capacities,
      storageAccess: storageAccess,
    );
  }

  // Cari volume yang cocok [hint] ("sd"/"usb"), render kartu aktif
  // kalau ketemu (pakai kapasitas yang sudah di-fetch di _loadAll),
  // atau kartu redup "Tidak terpasang" kalau tidak.
  Widget _buildExternalCard(
    BuildContext context, {
    required String hint,
    required IconData fallbackIcon,
    required String fallbackLabel,
    required List<StorageVolumeInfo> volumes,
    required Map<String, Map<String, int>> capacities,
    required StorageAccess storageAccess,
  }) {
    final match = storageAccess.findByHint(volumes, hint);
    if (match == null) {
      return _DisabledStorageCard(icon: fallbackIcon, label: fallbackLabel);
    }
    final capacity = capacities[match.path];
    if (capacity == null) {
      return _DisabledStorageCard(icon: fallbackIcon, label: fallbackLabel);
    }
    return _ExternalStorageCard(
      icon: fallbackIcon,
      label: match.label,
      path: match.path,
      totalBytes: capacity['totalBytes'] ?? 0,
      freeBytes: capacity['freeBytes'] ?? 0,
    );
  }
}

class _OverviewData {
  final StorageInfo storage;
  final RamInfo ram;
  final List<StorageVolumeInfo> removableVolumes;
  final Map<String, Map<String, int>> volumeCapacities;
  final StorageAccess storageAccess;

  const _OverviewData({
    required this.storage,
    required this.ram,
    required this.removableVolumes,
    required this.volumeCapacities,
    required this.storageAccess,
  });
}

class _StorageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final StorageInfo info;
  final VoidCallback? onTap;

  const _StorageCard({required this.icon, required this.label, required this.info, this.onTap});

  @override
  Widget build(BuildContext context) {
    final usedGB = info.usedBytes / (1024 * 1024 * 1024);
    final totalGB = info.totalBytes / (1024 * 1024 * 1024);
    final percent = (info.usedFraction * 1000).round() / 10; // 1 desimal

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
    ), // Container
    ); // InkWell
  }
}

// Fase 1.5: kartu SD Card/USB OTG aktif — sama persis visualnya
// dengan _StorageCard (Internal Storage), tapi terima bytes mentah
// langsung (bukan StorageInfo, karena StorageInfo dari
// device_info_manager cuma untuk Internal Storage) dan navigasi ke
// path volume yang bersangkutan.
class _ExternalStorageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;

  const _ExternalStorageCard({
    required this.icon,
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
  });

  @override
  Widget build(BuildContext context) {
    final usedBytes = totalBytes - freeBytes;
    final usedFraction = totalBytes > 0 ? usedBytes / totalBytes : 0.0;
    final usedGB = usedBytes / (1024 * 1024 * 1024);
    final totalGB = totalBytes / (1024 * 1024 * 1024);
    final percent = (usedFraction * 1000).round() / 10;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ExplorerScreen(rootPath: path)),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                value: usedFraction,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: _dalxAccent,
              ),
            ),
          ],
        ),
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