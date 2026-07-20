package com.dalx.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.media.MediaScannerConnection
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * NativeBridge — semua operasi Android native Fase 1 (Open With,
 * Install/Uninstall APK, Media Scanner, resolusi Intent masuk untuk
 * Document Picker/Intent Handler). MainActivity.kt cuma jadi router
 * tipis ke class ini, mengikuti pola pemisahan seperti
 * device_info_manager.
 */
class NativeBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.dalx.app/native_bridge"
        private const val AUTHORITY = "com.dalx.app.fileprovider"
    }

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
}
