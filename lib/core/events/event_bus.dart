// core/events/event_bus.dart
//
// Event bus DalX — satu-satunya jalur komunikasi antar modul.
// Modul yang MEMICU event: panggil eventBus.fire(SomeEvent(...)).
// Modul yang MENDENGARKAN: dengarkan eventBus.stream, filter tipe
// event yang relevan dengan extension .whereEventType<T>() di bawah.
//
// Lihat ARCHITECTURE.md bagian 3 untuk aturan lengkapnya.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'event_catalog.dart';

class DalXEventBus {
  final _controller = StreamController<DalXEvent>.broadcast();

  /// Stream yang didengarkan modul lain. Gunakan .whereEventType<T>()
  /// untuk filter event tertentu, contoh:
  ///
  ///   eventBus.stream.whereEventType<FolderOpened>().listen((event) {
  ///     print('Folder dibuka: ${event.path}');
  ///   });
  Stream<DalXEvent> get stream => _controller.stream;

  /// Memicu event baru ke seluruh pendengar.
  void fire(DalXEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

/// Provider Riverpod untuk event bus — satu instance dipakai bersama
/// di seluruh app (bukan per-modul), supaya semua modul benar-benar
/// "dengar" sumber yang sama.
final eventBusProvider = Provider<DalXEventBus>((ref) {
  final bus = DalXEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// Extension untuk filter event bertipe tertentu dari stream.
///
/// Catatan: Dart TIDAK menyediakan Stream.whereType() bawaan (beda
/// dengan Iterable.whereType() yang memang ada di dart:core) — jadi
/// DalX menyediakan versi sendiri di sini, dipakai di seluruh modul
/// yang mendengarkan event supaya kodenya tetap ringkas:
///
///   eventBus.stream.whereEventType<FolderOpened>().listen(...)
extension DalXEventStreamFilter on Stream<DalXEvent> {
  Stream<T> whereEventType<T extends DalXEvent>() {
    return where((event) => event is T).cast<T>();
  }
}
