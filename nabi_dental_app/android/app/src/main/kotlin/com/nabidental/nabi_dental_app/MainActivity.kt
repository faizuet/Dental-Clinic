package com.nabidental.nabi_dental_app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "nabi.files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val filename = call.argument<String>("filename")
                        ?: throw IllegalArgumentException("filename is required")
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: throw IllegalArgumentException("bytes are required")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    result.success(saveToDownloads(filename, bytes, mime))
                } catch (error: Exception) {
                    result.error("save_failed", error.message, null)
                }
            }
    }

    private fun saveToDownloads(filename: String, bytes: ByteArray, mime: String): String {
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            writeMediaStoreDownload(filename, bytes, mime)
        } else {
            writeLegacyDownload(filename, bytes)
        }
        openUri(uri, mime)
        return uri.toString()
    }

    private fun writeMediaStoreDownload(filename: String, bytes: ByteArray, mime: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the Downloads file.")
        contentResolver.openOutputStream(uri).use { stream ->
            stream ?: throw IllegalStateException("Could not write the Downloads file.")
            stream.write(bytes)
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
        return uri
    }

    private fun writeLegacyDownload(filename: String, bytes: ByteArray): Uri {
        val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!directory.exists()) {
            directory.mkdirs()
        }
        val file = File(directory, filename)
        file.writeBytes(bytes)
        return Uri.fromFile(file)
    }

    private fun openUri(uri: Uri, mime: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Open report"))
        } catch (_: Exception) {
            // File is still in Downloads if no viewer is installed.
        }
    }
}
