// core/storage_access/storage_access.dart
//
// Fase 1.5. Wrapper StorageManager (lewat NativeBridge) — sesuai
// ARCHITECTURE.md, ini SATU-SATUNYA modul yang boleh memicu event
// StorageMounted. Modul lain (drawer, storage_overview) TIDAK boleh
// panggil NativeBridge.getStorageVolumes()/storageVolumeChanges
// langsung — selalu lewat sini.
//
// DalX tidak punya kepastian mutlak dari API sistem apakah suatu
// volume removable itu "SD Card" atau "USB OTG" (keduanya sama-sama
// muncul sebagai removable volume) — jadi pembedaannya di sini,
// lewat pencocokan kata kunci di label yang dikasih sistem (mis. "SD
// card", "USB Drive"). Kalau labelnya ambigu, volume tetap bisa
// dibrowse lewat Storage Overview, cuma gak ke-assign ke slot
// drawer manapun.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../events/event_bus.dart';
import '../events/event_catalog.dart';
import '../native_bridge/native_bridge.dart';

class StorageAccess {
  final DalXEventBus _eventBus;
  final NativeBridge _nativeBridge;

  StorageAccess(this._eventBus, this._nativeBridge) {
    // Dengar real-time — nyala tiap kali SD Card/USB OTG dicolok atau
    // dicabut selagi app hidup, bukan cuma pas layar dibuka.
    _nativeBridge.storageVolumeChanges.listen(_handleVolumesUpdate);
  }

  /// Query sekali, dipanggil manual (mis. Storage Overview/drawer
  /// saat dibuka) buat dapetin state terkini tanpa nunggu perubahan.
  Future<List<StorageVolumeInfo>> queryVolumes() async {
    final volumes = await _nativeBridge.getStorageVolumes();
    _handleVolumesUpdate(volumes);
    return volumes;
  }

  void _handleVolumesUpdate(List<StorageVolumeInfo> volumes) {
    for (final v in volumes) {
      if (!v.isPrimary && v.state == 'mounted') {
        _eventBus.fire(StorageMounted(v.path, v.label));
      }
    }
  }

  /// Cari volume removable pertama yang labelnya cocok [hint] (mis.
  /// "sd" atau "usb"), dipakai drawer buat routing tap ke folder yang
  /// benar. Null kalau gak ada yang cocok/gak ada device terpasang.
  StorageVolumeInfo? findByHint(List<StorageVolumeInfo> volumes, String hint) {
    for (final v in volumes) {
      if (v.isPrimary) continue;
      if (v.state != 'mounted') continue;
      if (v.label.toLowerCase().contains(hint.toLowerCase())) return v;
    }
    return null;
  }

  /// Semua volume removable yang lagi ke-mount, dipakai Storage
  /// Overview buat nampilin kartu dinamis (bisa 0, 1, atau lebih).
  List<StorageVolumeInfo> removableVolumes(List<StorageVolumeInfo> volumes) {
    return volumes.where((v) => !v.isPrimary && v.state == 'mounted').toList();
  }
}

final storageAccessProvider = Provider<StorageAccess>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  final nativeBridge = ref.watch(nativeBridgeProvider);
  return StorageAccess(eventBus, nativeBridge);
});
