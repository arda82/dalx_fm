package com.dalx.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.media.MediaScannerConnection
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executor

/**
 * NativeBridge — semua operasi Android native Fase 1 (Open With,
 * Install/Uninstall APK, Media Scanner, resolusi Intent masuk untuk
 * Document Picker/Intent Handler) dan Fase 1.5 (deteksi Storage
 * Volume — SD Card & USB OTG). MainActivity.kt cuma jadi router
 * tipis ke class ini, mengikuti pola pemisahan seperti
 * device_info_manager.
 */
class NativeBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.dalx.app/native_bridge"
        private const val AUTHORITY = "com.dalx.app.fileprovider"
    }

    private var storageEventSink: EventChannel.EventSink? = null
    private var storageVolumeCallback: StorageManager.StorageVolumeCallback? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openWith" -> {
                    openWith(call.argument<String>("path")!!, call.argument<String>("mimeType") ?: "*/*")
                    result.success(null)
                }
                "canInstallPackages" -> result.success(canInstallPackages())
                "requestInstallPermission" -> {
                    requestInstallPermission()
                    result.success(null)
                }
                "installApk" -> {
                    installApk(call.argument<String>("path")!!)
                    result.success(null)
                }
                "uninstallApk" -> {
                    uninstallApk(call.argument<String>("packageName")!!)
                    result.success(null)
                }
                "scanMedia" -> {
                    scanMedia(call.argument<String>("path")!!)
                    result.success(null)
                }
                "returnPickedFile" -> {
                    returnPickedFile(call.argument<String>("path")!!)
                    result.success(null)
                }
                "getLaunchIntentData" -> result.success(resolveIntentToMap(activity.intent))
                "getStorageVolumes" -> result.success(getStorageVolumesList())
                "getStorageCapacity" -> {
                    result.success(getStorageCapacity(call.argument<String>("path")!!))
                }
                "listDirectoryNative" -> {
                    result.success(listDirectoryNative(call.argument<String>("path")!!))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("NATIVE_BRIDGE_ERROR", e.message, null)
        }
    }

    // ---------------- Open With ----------------

    private fun openWith(path: String, mimeType: String) {
        val uri = FileProvider.getUriForFile(activity, AUTHORITY, File(path))
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(Intent.createChooser(intent, null))
    }

    // ---------------- Install / Uninstall APK ----------------

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else true
    }

    private fun requestInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
            )
        }
    }

    private fun installApk(path: String) {
        val uri = FileProvider.getUriForFile(activity, AUTHORITY, File(path))
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    private fun uninstallApk(packageName: String) {
        activity.startActivity(
            Intent(Intent.ACTION_DELETE).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    // ---------------- Media Scanner ----------------

    private fun scanMedia(path: String) {
        MediaScannerConnection.scanFile(activity, arrayOf(path), null, null)
    }

    // ---------------- Document Picker: DalX jadi picker ----------------

    private fun returnPickedFile(path: String) {
        val uri = FileProvider.getUriForFile(activity, AUTHORITY, File(path))
        val resultIntent = Intent().apply {
            data = uri
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.setResult(Activity.RESULT_OK, resultIntent)
        activity.finish()
    }

    /**
     * Fallback listing direktori pakai java.io.File biasa (BUKAN
     * dart:io). Dipakai file_engine.dart saat dart:io Directory.list()
     * gagal total buka sebuah folder — ini bug yang sudah dikonfirmasi
     * tim Flutter sendiri (flutter/flutter#108232, duplikat dari
     * #40504): dart:io Directory.listSync() melempar "Permission
     * denied, errno=13" khusus di Android/data & Android/obb, WALAU
     * MANAGE_EXTERNAL_STORAGE aktif. java.io.File TIDAK kena bug yang
     * sama — ini juga kenapa file manager native seperti Amaze/CX File
     * Manager bisa browse folder itu lancar sementara app berbasis
     * dart:io murni gagal.
     *
     * Item yang gagal dibaca detailnya (mis. permission per-item)
     * di-skip satu-satu, bukan gagalin seluruh listing — sama seperti
     * penanganan di sisi Dart.
     */
    private fun listDirectoryNative(path: String): List<Map<String, Any?>> {
        val dir = File(path)
        val children = dir.listFiles() ?: return emptyList()
        val result = mutableListOf<Map<String, Any?>>()
        for (child in children) {
            try {
                result.add(
                    mapOf(
                        "name" to child.name,
                        "path" to child.absolutePath,
                        "isDirectory" to child.isDirectory,
                        "sizeBytes" to (if (child.isFile) child.length() else 0L),
                        "modifiedAt" to child.lastModified()
                    )
                )
            } catch (e: Exception) {
                continue
            }
        }
        return result
    }

    // ---------------- Intent Handler: resolusi intent masuk ----------------

    /**
     * Dipanggil dari MainActivity (initial intent saat launch, atau
     * onNewIntent saat app sudah berjalan). Untuk ACTION_SEND/
     * SEND_MULTIPLE, URI yang masuk dari app lain biasanya content://
     * (bukan path asli) — jadi di-copy ke cache dir DalX dulu supaya
     * file_engine bisa baca dengan dart:io biasa.
     */
    fun resolveIntentToMap(intent: Intent?): Map<String, Any> {
        if (intent == null) return mapOf("action" to "none", "paths" to emptyList<String>())

        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                mapOf("action" to "send", "paths" to listOfNotNull(uri?.let { copyContentUriToCache(it) }))
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                mapOf("action" to "send", "paths" to (uris?.mapNotNull { copyContentUriToCache(it) } ?: emptyList()))
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                val path = uri?.let { if (it.scheme == "file") it.path else copyContentUriToCache(it) }
                mapOf("action" to "view", "paths" to listOfNotNull(path))
            }
            Intent.ACTION_GET_CONTENT -> mapOf("action" to "get_content", "paths" to emptyList<String>())
            else -> mapOf("action" to "none", "paths" to emptyList<String>())
        }
    }

    /**
     * Salin isi content:// URI ke cache dir DalX, pertahankan nama
     * file asli lewat OpenableColumns kalau bisa. Perlu karena app
     * pengirim (WhatsApp, Gmail, dll) jarang kasih path asli.
     */
    private fun copyContentUriToCache(uri: Uri): String? {
        return try {
            val resolver = activity.contentResolver
            var displayName = "shared_${System.currentTimeMillis()}"
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (cursor.moveToFirst() && nameIndex >= 0) displayName = cursor.getString(nameIndex)
            }
            val outFile = File(activity.cacheDir, displayName)
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            }
            outFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    // ---------------- Fase 1.5: Storage Volume Detection ----------------

    /**
     * Enumerasi semua storage volume yang di-mount sistem (Internal,
     * SD Card, USB OTG) lewat StorageManager.storageVolumes — API ini
     * jalan langsung tanpa BroadcastReceiver/manifest intent-filter
     * legacy karena minSdk DalX sudah 30 (StorageVolume.directory &
     * getDescription baru stabil dari API 30 ke atas).
     *
     * DalX TIDAK punya cara pasti membedakan "SD Card" vs "USB OTG"
     * murni dari API sistem (keduanya sama-sama muncul sebagai
     * removable volume) — pembedaan dilakukan di sisi Dart
     * (core/storage_access) lewat pencocokan kata kunci di [label].
     */
    private fun getStorageVolumesList(): List<Map<String, Any?>> {
        val storageManager = activity.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        return storageManager.storageVolumes.mapNotNull { volume ->
            val dir = volume.directory ?: return@mapNotNull null
            mapOf(
                "path" to dir.absolutePath,
                "label" to (volume.getDescription(activity) ?: "Storage"),
                "isRemovable" to volume.isRemovable,
                "isPrimary" to volume.isPrimary,
                "state" to volume.state
            )
        }
    }

    /** Kapasitas storage di [path] mana pun (bukan cuma Internal) — dipakai
     * buat SD Card/USB OTG di Storage Overview, lewat StatFs generik. */
    private fun getStorageCapacity(path: String): Map<String, Long> {
        val stat = StatFs(path)
        val totalBytes = stat.blockCountLong * stat.blockSizeLong
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
        return mapOf("totalBytes" to totalBytes, "freeBytes" to freeBytes)
    }

    /**
     * Dipanggil dari MainActivity setelah EventChannel storage_stream
     * di-listen dari Dart (onListen) / berhenti (onCancel). Begitu ada
     * listener aktif, DalX daftar ke StorageManager buat dikabarin
     * real-time tiap ada volume mount/unmount (colok/cabut SD
     * Card/USB OTG) — bukan polling manual.
     */
    fun attachStorageEventSink(sink: EventChannel.EventSink?) {
        storageEventSink = sink
        val storageManager = activity.getSystemService(Context.STORAGE_SERVICE) as StorageManager

        if (sink != null) {
            val executor = Executor { command -> activity.runOnUiThread(command) }
            val callback = object : StorageManager.StorageVolumeCallback() {
                override fun onStateChanged(volume: StorageVolume) {
                    storageEventSink?.success(getStorageVolumesList())
                }
            }
            storageManager.registerStorageVolumeCallback(executor, callback)
            storageVolumeCallback = callback
        } else {
            storageVolumeCallback?.let { storageManager.unregisterStorageVolumeCallback(it) }
            storageVolumeCallback = null
        }
    }
}
