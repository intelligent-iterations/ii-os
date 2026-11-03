package org.example.iios

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ii_os/local_document",
        ).setMethodCallHandler { call, result ->
            if (call.method != "readIdentity") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uriText = call.argument<String>("uri")
            val maxBytes = call.argument<Number>("maxBytes")?.toLong()
            if (uriText.isNullOrBlank() || maxBytes == null ||
                maxBytes <= 0 || maxBytes > 512L * 1024L * 1024L
            ) {
                result.error("invalid-arguments", "A bounded document URI is required.", null)
                return@setMethodCallHandler
            }
            val uri = Uri.parse(uriText)
            if (uri.scheme != "content") {
                result.error("invalid-uri", "Only content document URIs are supported.", null)
                return@setMethodCallHandler
            }
            thread(name = "ii-os-local-document-identity") {
                try {
                    val identity = readIdentity(uri, maxBytes)
                    runOnUiThread { result.success(identity) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error(
                            "document-read-failed",
                            error.message ?: "Unable to read the selected document.",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun readIdentity(uri: Uri, maxBytes: Long): Map<String, Any> {
        val digest = MessageDigest.getInstance("SHA-256")
        val prefix = ByteArray(8)
        var prefixLength = 0
        var size = 0L
        contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                size += count
                require(size <= maxBytes) { "Selected document exceeds the read limit." }
                digest.update(buffer, 0, count)
                if (prefixLength < prefix.size) {
                    val copied = minOf(count, prefix.size - prefixLength)
                    buffer.copyInto(prefix, prefixLength, 0, copied)
                    prefixLength += copied
                }
            }
        } ?: error("Unable to open the selected document.")
        require(prefixLength == prefix.size) { "Selected document is too small." }
        val signature = prefix.copyOfRange(4, 8).toHex()
        return mapOf(
            "sha256" to digest.digest().toHex(),
            "sizeBytes" to size,
            "signatureHex" to signature,
        )
    }

    private fun ByteArray.toHex(): String =
        joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }
}
