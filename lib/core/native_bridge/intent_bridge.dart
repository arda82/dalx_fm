// core/native_bridge/intent_bridge.dart
//
// Menangkap intent yang membuka/menghampiri DalX dari luar:
// - Saat startup (ACTION_SEND dari share sheet app lain, ACTION_VIEW
//   dari "Open With DalX", ACTION_GET_CONTENT dari Document Picker)
// - Saat app sudah berjalan (onNewIntent di MainActivity.kt, lewat
//   EventChannel "com.dalx.app/intent_stream")
//
// Modul lain (main.dart) dengar lewat provider di sini, TIDAK perlu
// tahu detail MethodChannel/EventChannel.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'native_bridge.dart';

enum IncomingIntentAction { send, view, getContent, none }

class IncomingIntent {
  final IncomingIntentAction action;
  final List<String> paths;

  const IncomingIntent(this.action, this.paths);

  factory IncomingIntent.fromMap(Map<dynamic, dynamic> map) {
    final action = switch (map['action']) {
      'send' => IncomingIntentAction.send,
      'view' => IncomingIntentAction.view,
      'get_content' => IncomingIntentAction.getContent,
      _ => IncomingIntentAction.none,
    };
    final paths = (map['paths'] as List?)?.cast<String>() ?? const [];
    return IncomingIntent(action, paths);
  }
}

class IntentBridge {
  static const _eventChannel = EventChannel('com.dalx.app/intent_stream');
  final NativeBridge _nativeBridge;

  IntentBridge(this._nativeBridge);

  /// Baca intent yang membuka DalX saat startup. Panggil SEKALI di
  /// main.dart sebelum masuk ke Explorer.
  Future<IncomingIntent> getInitialIntent() async {
    final map = await _nativeBridge.getLaunchIntentData();
    return IncomingIntent.fromMap(map);
  }

  /// Stream intent baru yang masuk selagi DalX sudah berjalan
  /// (mis. user share file lagi tanpa nutup DalX dulu).
  Stream<IncomingIntent> get incomingIntents {
    return _eventChannel.receiveBroadcastStream().map(
          (event) => IncomingIntent.fromMap(event as Map<dynamic, dynamic>),
        );
  }
}

final intentBridgeProvider = Provider<IntentBridge>((ref) {
  final nativeBridge = ref.watch(nativeBridgeProvider);
  return IntentBridge(nativeBridge);
});
