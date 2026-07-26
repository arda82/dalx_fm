package com.dalx.app

import android.app.ActivityManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
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
// - "com.dalx.app/storage_stream" (Fase 1.5) — EventChannel real-time
//   buat kabarin Dart tiap ada SD Card/USB OTG dicolok atau dicabut,
//   pakai StorageManager.registerStorageVolumeCallback (API 30+,
//   sesuai minSdk DalX) — bukan BroadcastReceiver legacy.
// - "com.dalx.app/archive_stream" (Fase 8 Pilar #2) — EventChannel
//   progress real-time buat compress/extract 7z & extract RAR
//   (native, lihat NativeBridge.kt) — dipakai selama operasi native
//   berjalan di background thread, supaya progress bar Task Queue
//   Dart nggak cuma lompat 0% -> 100%.
class MainActivity : FlutterActivity() {
    private val deviceInfoChannelName = "com.dalx.app/device_info"

    private lateinit var nativeBridge: NativeBridge
    private var intentEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // WAJIB dipanggil sebelum PdfBox-Android dipakai sama sekali
        // (lihat NativeBridge.kt rotatePdf) — load font resource
        // bawaan PdfBox dari assets. Fase 8 Pilar #3.
        PDFBoxResourceLoader.init(applicationContext)

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

        // ---------------- storage_stream (Fase 1.5) ----------------
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dalx.app/storage_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                nativeBridge.attachStorageEventSink(events)
            }
            override fun onCancel(arguments: Any?) {
                nativeBridge.attachStorageEventSink(null)
            }
        })

        // ---------------- archive_stream (Fase 8 Pilar #2) ----------------
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dalx.app/archive_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                nativeBridge.attachArchiveEventSink(events)
            }
            override fun onCancel(arguments: Any?) {
                nativeBridge.attachArchiveEventSink(null)
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
     * Baca kapasitas Internal Storage. [freeBytes] tetap dari StatFs
     * (representasi ruang kosong yang akurat & wajar). [totalBytes]
     * SENGAJA diambil dari StorageStatsManager.getTotalBytes(), BUKAN
     * StatFs.blockCountLong — StatFs cuma menghitung block yang benar-
     * benar ada di partisi data (biasanya ~10% lebih kecil dari
     * kapasitas nominal chip, karena overhead sistem/wear-leveling
     * tidak masuk hitungan block filesystem biasa), sedangkan
     * StorageStatsManager mengembalikan kapasitas "resmi" yang sama
     * dengan yang ditampilkan Settings Android & file manager lain
     * (CX, dll). Ditemukan lewat perbandingan langsung: StatFs sempat
     * menunjukkan 106.7 GB pada device 128 GB, sementara Settings &
     * CX kompak menunjukkan 128 GB.
     *
     * Mengembalikan total & free dalam bytes (Long) — perhitungan
     * used dan persentase dilakukan di sisi Dart supaya logic-nya
     * satu tempat.
     */
    private fun getStorageInfo(): Map<String, Long> {
        val path = Environment.getExternalStorageDirectory()
        val stat = StatFs(path.path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong

        val totalBytes = try {
            val storageStatsManager = getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
            storageStatsManager.getTotalBytes(StorageManager.UUID_DEFAULT)
        } catch (e: Exception) {
            // Fallback kalau StorageStatsManager gagal (seharusnya
            // tidak terjadi di API 30+, tapi jaga-jaga daripada
            // storage overview error total).
            stat.blockCountLong * stat.blockSizeLong
        }

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
