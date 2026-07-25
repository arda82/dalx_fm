package com.dalx.app

import android.app.Activity
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.media.MediaScannerConnection
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import com.github.junrar.Junrar
import com.tom_roush.pdfbox.pdmodel.PDDocument
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executor
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile

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

        // Dimensi maksimum sisi terpanjang thumbnail (px). Cukup buat
        // Grid/List View DalX (tile terbesar ~40-44px logis, tapi
        // disimpan lebih besar dari itu supaya masih tajam di device
        // resolusi tinggi/density besar).
        private const val THUMBNAIL_MAX_DIMENSION = 200
        private const val THUMBNAIL_JPEG_QUALITY = 80
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
                "generateThumbnail" -> {
                    // Async: jalan di background thread, result dipanggil
                    // dari sana (lihat generateThumbnailAsync) — decode
                    // bitmap/frame video bisa berat dan TIDAK boleh
                    // blocking platform thread.
                    generateThumbnailAsync(
                        call.argument<String>("path")!!,
                        (call.argument<Number>("modifiedAtMillis") ?: 0).toLong(),
                        call.argument<Boolean>("isVideo") ?: false,
                        result
                    )
                }
                "compress7z" -> {
                    @Suppress("UNCHECKED_CAST")
                    compress7zAsync(
                        call.argument<String>("taskId")!!,
                        call.argument<List<String>>("sourcePaths") as List<String>,
                        call.argument<String>("destinationPath")!!,
                        result
                    )
                }
                "extract7z" -> {
                    extract7zAsync(
                        call.argument<String>("taskId")!!,
                        call.argument<String>("sourcePath")!!,
                        call.argument<String>("destinationDir")!!,
                        result
                    )
                }
                "extractRar" -> {
                    extractRarAsync(
                        call.argument<String>("taskId")!!,
                        call.argument<String>("sourcePath")!!,
                        call.argument<String>("destinationDir")!!,
                        result
                    )
                }
                "rotatePdf" -> {
                    rotatePdfAsync(
                        call.argument<String>("sourcePath")!!,
                        call.argument<String>("destinationPath")!!,
                        (call.argument<Number>("degrees") ?: 90).toInt(),
                        result
                    )
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

    // ---------------- Thumbnail Generation (kekurangan pra-Fase 8) ----------------

    private val thumbnailCacheDir: File by lazy {
        File(activity.cacheDir, "thumbnails").apply { if (!exists()) mkdirs() }
    }

    /**
     * Dipanggil dari onMethodCall — generate/ambil-dari-cache thumbnail
     * di background thread lalu balikin hasilnya lewat [result] di UI
     * thread. Decode bitmap ukuran penuh (terutama foto kamera modern,
     * bisa puluhan MB) atau extract frame video TIDAK boleh dilakukan
     * di platform thread — bisa bikin UI freeze/jank kalau dipanggil
     * bertubi-tubi pas user scroll cepat di Grid View.
     */
    private fun generateThumbnailAsync(
        path: String,
        modifiedAtMillis: Long,
        isVideo: Boolean,
        result: MethodChannel.Result
    ) {
        Thread {
            val thumbPath = try {
                generateThumbnail(path, modifiedAtMillis, isVideo)
            } catch (e: Exception) {
                null
            }
            activity.runOnUiThread {
                if (thumbPath != null) {
                    result.success(thumbPath)
                } else {
                    result.error("THUMBNAIL_FAILED", "Gagal generate thumbnail untuk $path", null)
                }
            }
        }.start()
    }

    /**
     * Idempotent: cek dulu apakah thumbnail untuk [path]+[modifiedAtMillis]
     * ini sudah pernah di-generate & masih ada di cache disk — kalau
     * ada, langsung balikin path-nya tanpa decode ulang. Cache key
     * dari hash MD5 "path|modifiedAtMillis", jadi otomatis "invalid"
     * sendiri kalau file aslinya berubah (timestamp beda -> key beda
     * -> generate ulang), tanpa perlu tracking manual dari Dart.
     */
    private fun generateThumbnail(path: String, modifiedAtMillis: Long, isVideo: Boolean): String? {
        val cacheKey = md5Hex("$path|$modifiedAtMillis")
        val cacheFile = File(thumbnailCacheDir, "$cacheKey.jpg")
        if (cacheFile.exists()) return cacheFile.absolutePath

        val bitmap = (if (isVideo) decodeVideoFrame(path) else decodeSampledBitmap(path))
            ?: return null

        try {
            FileOutputStream(cacheFile).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_JPEG_QUALITY, out)
            }
        } finally {
            bitmap.recycle()
        }
        return cacheFile.absolutePath
    }

    /** Ambil 1 frame dari video pakai MediaMetadataRetriever. */
    private fun decodeVideoFrame(path: String): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.getFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * Decode gambar dengan inSampleSize (downscale SAAT decode, bukan
     * decode resolusi penuh baru di-resize) — penting untuk foto
     * kamera modern yang bisa puluhan megapixel, supaya tidak
     * OutOfMemoryError.
     */
    private fun decodeSampledBitmap(path: String): Bitmap? {
        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOptions)
        if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

        var sampleSize = 1
        var width = boundsOptions.outWidth
        var height = boundsOptions.outHeight
        while (width / 2 >= THUMBNAIL_MAX_DIMENSION && height / 2 >= THUMBNAIL_MAX_DIMENSION) {
            width /= 2
            height /= 2
            sampleSize *= 2
        }

        val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        return BitmapFactory.decodeFile(path, decodeOptions)
    }

    private fun md5Hex(input: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(input.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    // ---------------- Compress Native: 7z & RAR (Fase 8 Pilar #2) ----------------
    // SENGAJA cuma nangani 7z (compress+extract) & RAR (extract) — ZIP
    // dan tar/tar.gz TETAP pure Dart (package:archive sudah cukup,
    // lihat ARCHITECTURE.md bagian 7.2 Pilar #2, revisi scope). Semua
    // di sini jalan di background thread (bukan platform thread) &
    // lapor progress lewat EventChannel "com.dalx.app/archive_stream"
    // (attachArchiveEventSink) — BUKAN cuma lewat result callback di
    // akhir, supaya Task Queue Dart bisa update progress bar
    // real-time selama proses berjalan, bukan lompat 0% -> 100%.
    //
    // [taskId] dikirim dari Dart (task.id dari DalXTask) supaya kalau
    // suatu saat ada >1 operasi archive native jalan "bersamaan" (di
    // luar scope sekarang, Task Queue jalan sekuensial), event
    // progress tetap bisa dibedakan sumbernya di sisi Dart.

    private var archiveEventSink: EventChannel.EventSink? = null

    /** Dipanggil MainActivity dari onListen/onCancel EventChannel archive_stream. */
    fun attachArchiveEventSink(sink: EventChannel.EventSink?) {
        archiveEventSink = sink
    }

    private fun emitArchiveProgress(taskId: String, progress: Double) {
        activity.runOnUiThread {
            archiveEventSink?.success(mapOf("taskId" to taskId, "progress" to progress))
        }
    }

    private fun compress7zAsync(
        taskId: String,
        sourcePaths: List<String>,
        destinationPath: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                compress7z(taskId, sourcePaths, destinationPath)
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("COMPRESS_7Z_FAILED", e.message, null) }
            }
        }.start()
    }

    private data class ArchiveEntrySource(val file: File, val entryName: String)

    private fun compress7z(taskId: String, sourcePaths: List<String>, destinationPath: String) {
        // Kumpulkan dulu SEMUA entry (file + folder, rekursif) yang mau
        // dimasukkan, biar tau total buat hitung progress — pola sama
        // dengan _runCompress di task_queue.dart (Dart, versi ZIP).
        val entries = mutableListOf<ArchiveEntrySource>()
        fun collect(file: File, entryName: String) {
            entries.add(ArchiveEntrySource(file, entryName))
            if (file.isDirectory) {
                file.listFiles()?.forEach { child -> collect(child, "$entryName/${child.name}") }
            }
        }
        for (sourcePath in sourcePaths) {
            val file = File(sourcePath)
            collect(file, file.name)
        }

        SevenZOutputFile(File(destinationPath)).use { output ->
            val total = entries.size.coerceAtLeast(1)
            entries.forEachIndexed { i, entry ->
                val archiveEntry = output.createArchiveEntry(entry.file, entry.entryName)
                output.putArchiveEntry(archiveEntry)
                if (entry.file.isFile) {
                    output.write(entry.file.readBytes())
                }
                output.closeArchiveEntry()
                emitArchiveProgress(taskId, (i + 1).toDouble() / total)
            }
        }
    }

    private fun extract7zAsync(
        taskId: String,
        sourcePath: String,
        destinationDir: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                extract7z(taskId, sourcePath, destinationDir)
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("EXTRACT_7Z_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun extract7z(taskId: String, sourcePath: String, destinationDir: String) {
        File(destinationDir).mkdirs()
        SevenZFile(File(sourcePath)).use { sevenZFile ->
            val total = sevenZFile.entries.count().coerceAtLeast(1)
            var index = 0
            val buffer = ByteArray(8192)
            var entry = sevenZFile.nextEntry
            while (entry != null) {
                val outFile = File(destinationDir, entry.name)
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { out ->
                        var read: Int
                        while (sevenZFile.read(buffer).also { read = it } > 0) {
                            out.write(buffer, 0, read)
                        }
                    }
                }
                index++
                emitArchiveProgress(taskId, index.toDouble() / total)
                entry = sevenZFile.nextEntry
            }
        }
    }

    private fun extractRarAsync(
        taskId: String,
        sourcePath: String,
        destinationDir: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                File(destinationDir).mkdirs()
                // Junrar.extract() TIDAK kasih progress per-file granular
                // — trade-off yang DISADARI, bukan kelupaan. API junrar
                // low-level (Archive + FileHeader) buat progress custom
                // cukup rapuh/beda-beda antar versi rilis, resikonya
                // lebih besar dari manfaat "progress halus" buat fitur
                // yang sifatnya best-effort. Cukup 2 titik: mulai & selesai.
                emitArchiveProgress(taskId, 0.0)
                Junrar.extract(File(sourcePath), File(destinationDir))
                emitArchiveProgress(taskId, 1.0)
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("EXTRACT_RAR_FAILED", e.message, null) }
            }
        }.start()
    }

    // ---------------- Edit PDF: Rotate (Fase 8 Pilar #3) ----------------
    // PdfBox-Android — manipulasi struktur PDF asli (cuma ubah
    // dictionary /Rotate per halaman), BUKAN render ulang jadi gambar,
    // jadi teks tetap tajam & bisa di-search. Operasi ini RINGAN
    // (tidak decode/encode ulang isi konten halaman), jadi TIDAK pakai
    // progress granular kayak compress/extract 7z — cukup coarse
    // (result callback doang, tanpa EventChannel).

    private fun rotatePdfAsync(
        sourcePath: String,
        destinationPath: String,
        degrees: Int,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                rotatePdf(sourcePath, destinationPath, degrees)
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("ROTATE_PDF_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun rotatePdf(sourcePath: String, destinationPath: String, degrees: Int) {
        PDDocument.load(File(sourcePath)).use { document ->
            for (page in document.pages) {
                // Rotasi PDF itu KUMULATIF & harus kelipatan 90 (spec
                // PDF) — tambahkan ke rotasi existing (kalau halaman
                // sebelumnya sudah punya /Rotate dari sononya), bukan
                // di-set absolut, supaya rotate berulang kali tetap
                // konsisten hasilnya.
                val newRotation = ((page.rotation + degrees) % 360 + 360) % 360
                page.rotation = newRotation
            }
            document.save(destinationPath)
        }
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

    /**
     * Kapasitas storage di [path] mana pun (SD Card/USB OTG, bukan
     * cuma Internal) — dipakai Storage Overview via getStorageCapacity.
     *
     * [totalBytes] SENGAJA diambil dari StorageStatsManager (sama
     * alasan/bug dengan getStorageInfo Internal Storage di
     * MainActivity.kt — StatFs.blockCountLong menghitung ~10% lebih
     * kecil dari kapasitas nominal chip, beda dari yang ditampilkan
     * Settings Android/CX File Manager). StorageManager.getUuidForPath
     * (API 26+, aman di minSdk 30) yang cari tau UUID storage volume
     * dari sebuah path — kerja untuk path mana pun yang ter-mount,
     * termasuk SD Card & USB OTG, tidak cuma primary storage.
     * [freeBytes] tetap dari StatFs (representasi ruang kosong wajar).
     */
    private fun getStorageCapacity(path: String): Map<String, Long> {
        val stat = StatFs(path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong

        val totalBytes = try {
            val storageManager = activity.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            val storageStatsManager =
                activity.getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
            val uuid = storageManager.getUuidForPath(File(path))
            storageStatsManager.getTotalBytes(uuid)
        } catch (e: Exception) {
            // Fallback StatFs mentah kalau getUuidForPath/StorageStatsManager
            // gagal (mis. path aneh yang tidak dikenali sistem) — daripada
            // Storage Overview error total buat volume itu.
            stat.blockCountLong * stat.blockSizeLong
        }

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
