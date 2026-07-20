package com.dalx.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// MainActivity — jembatan antara sistem Android dan Flutter engine.
// Ini file WAJIB ada untuk app Flutter apa pun karena
// AndroidManifest.xml mereferensikan android:name=".MainActivity"
// sebagai entry point saat app diluncurkan. Tanpa file ini, sistem
// Android tidak menemukan class Activity yang direferensikan dan
// app crash instan saat dibuka.
//
// Channel yang hidup di sini:
// - "com.dalx.app/device_info" (Sub-Fase 0a) — StatFs (storage) &
//   ActivityManager (RAM). dart:io tidak punya akses langsung ke
//   API ini, jadi dijembatani manual, bukan pakai package pihak
//   ketiga (banyak package storage-info di pub.dev kurang terpelihara).
// - NativeBridge.CHANNEL "com.dalx.app/native_bridge" (Fase 1) —
//   Open With, Install/Uninstall APK, Media Scanner, Document
//   Picker. Logic-nya di NativeBridge.kt, MainActivity cuma jadi
//   router tipis ke situ.
// - "com.dalx.app/intent_stream" (Fase 1) — EventChannel buat kirim
//   intent baru ke Dart saat app SUDAH berjalan (onNewIntent), mis.
//   user share file lagi ke DalX tanpa nutup app dulu.
class MainActivity : FlutterActivity() {
    private val deviceInfoChannelName = "com.dalx.app/device_info"

    private lateinit var nativeBridge: NativeBridge
    private var intentEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---------------- device_info (Sub-Fase 0a) ----------------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceInfoChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageInfo" -> result.success(getStorageInfo())
                    "getRamInfo" -> result.success(getRamInfo())
                    else -> result.notImplemented()
                }
            }

        // ---------------- native_bridge (Fase 1) ----------------
        nativeBridge = NativeBridge(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeBridge.CHANNEL
        ).setMethodCallHandler(nativeBridge)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dalx.app/intent_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                intentEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                intentEventSink = null
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::nativeBridge.isInitialized) {
            intentEventSink?.success(nativeBridge.resolveIntentToMap(intent))
        }
    }

    /**
     * Baca kapasitas Internal Storage lewat StatFs. Mengembalikan
     * total & free dalam bytes (Long) — perhitungan used dan
     * persentase dilakukan di sisi Dart supaya logic-nya satu tempat.
     */
    private fun getStorageInfo(): Map<String, Long> {
        val path = Environment.getExternalStorageDirectory()
        val stat = StatFs(path.path)
        val totalBytes = stat.blockCountLong * stat.blockSizeLong
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
        return mapOf(
            "totalBytes" to totalBytes,
            "freeBytes" to freeBytes
        )
    }

    /**
     * Baca info RAM lewat ActivityManager.MemoryInfo. Mengembalikan
     * total & available dalam bytes (Long).
     */
    private fun getRamInfo(): Map<String, Long> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return mapOf(
            "totalBytes" to memoryInfo.totalMem,
            "availableBytes" to memoryInfo.availMem
        )
    }
}
