package com.dalx.app

import android.app.ActivityManager
import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// MainActivity — jembatan antara sistem Android dan Flutter engine.
// Ini file WAJIB ada untuk app Flutter apa pun karena
// AndroidManifest.xml mereferensikan android:name=".MainActivity"
// sebagai entry point saat app diluncurkan. Tanpa file ini, sistem
// Android tidak menemukan class Activity yang direferensikan dan
// app crash instan saat dibuka.
//
// Selain itu, class ini juga menjadi tempat platform channel DalX:
// dart:io tidak punya akses langsung ke StatFs (kapasitas storage)
// atau ActivityManager (info RAM) — itu API khusus Android, jadi
// perlu dijembatani dari sini ke kode Dart lewat MethodChannel.
// Dipilih bikin channel sendiri (bukan pakai package pihak ketiga)
// karena banyak package storage-info di pub.dev kurang terpelihara —
// ini konsisten dengan pola yang sudah dipakai untuk Permission
// Manager (SAF, MANAGE_EXTERNAL_STORAGE).
class MainActivity : FlutterActivity() {
    private val channelName = "com.dalx.app/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageInfo" -> result.success(getStorageInfo())
                    "getRamInfo" -> result.success(getRamInfo())
                    else -> result.notImplemented()
                }
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
