// features/media_scanner/media_scanner_listener.dart
//
// Listener event-driven: begitu FileCreated/FileMoved/FileCopied
// muncul dan filenya termasuk tipe media (gambar/video/audio),
// trigger MediaScannerConnection lewat NativeBridge supaya file itu
// langsung muncul di galeri/app musik tanpa nunggu Android scan
// berkala sendiri.
//
// Modul ini TIDAK dipanggil manual dari mana pun — cukup di-watch
// sekali (lihat mediaScannerListenerProvider di main.dart) supaya
// listener-nya aktif selama app hidup. Sesuai aturan Event System,
// modul ini gak pernah manggil file_engine/task_queue langsung.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/events/event_bus.dart';
import '../../core/events/event_catalog.dart';
import '../../core/native_bridge/native_bridge.dart';

const _mediaExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic',
  'mp4', 'mkv', 'mov', 'avi', 'webm',
  'mp3', 'wav', 'ogg', 'flac', 'm4a',
};

class MediaScannerListener {
  final DalXEventBus _eventBus;
  final NativeBridge _nativeBridge;

  MediaScannerListener(this._eventBus, this._nativeBridge) {
    _eventBus.stream.whereEventType<FileCreated>().listen((event) {
      if (!event.isFolder) _scanIfMedia(event.path);
    });
    _eventBus.stream.whereEventType<FileMoved>().listen((event) {
      _nativeBridge.scanMedia(event.destinationPath);
    });
    _eventBus.stream.whereEventType<FileCopied>().listen((event) {
      _nativeBridge.scanMedia(event.destinationPath);
    });
  }

  void _scanIfMedia(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    if (_mediaExtensions.contains(ext)) {
      _nativeBridge.scanMedia(path);
    }
  }
}

final mediaScannerListenerProvider = Provider<MediaScannerListener>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  final nativeBridge = ref.watch(nativeBridgeProvider);
  return MediaScannerListener(eventBus, nativeBridge);
});
