package dev.ihtd.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pickerResult: MethodChannel.Result? = null
    private val documents = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val updates = UpdateBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.ihtd.app/updates")
            .setMethodCallHandler(updates::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.ihtd.app/documents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "environment" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(mapOf("appVersion" to info.versionName,
                            "build" to info.longVersionCode, "androidApi" to Build.VERSION.SDK_INT,
                            "androidVersion" to Build.VERSION.RELEASE))
                    }
                    "open", "create" -> {
                        if (pickerResult != null) {
                            result.error("busy", "A document picker is already open", null)
                        } else {
                            val create = call.method == "create"
                            val intent = Intent(if (create) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType(if (create) "application/octet-stream" else "*/*")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            if (create) intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                            pickerResult = result
                            try { startActivityForResult(intent, 4101) }
                            catch (e: Exception) {
                                pickerResult = null
                                result.error("picker", e.message, null)
                            }
                        }
                    }
                    "pending", "localHash" -> documents.execute {
                        try {
                            val digest = hash(File(requireNotNull(call.argument<String>("path"))).readBytes())
                            val value: Any = if (call.method == "localHash") digest else digest != call.argument<String>("hash")
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("local_failed", "Private file could not be read", null) }
                        }
                    }
                    "read", "write", "inspect" -> documents.execute {
                        try {
                            val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                            require(uri.scheme == "content") { "Expected a document-provider URI" }
                            val value: Any = if (call.method == "inspect") {
                                metadata(uri) + mapOf("hash" to hash(readDocument(uri)))
                            } else if (call.method == "read") {
                                val remote = readDocument(uri)
                                mapOf("bytes" to remote, "hash" to hash(remote))
                            } else {
                                val local = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                                require(local.path.startsWith(filesDir.parentFile!!.canonicalPath + "/")) {
                                    "Only private working files can be published"
                                }
                                val bytes = try { local.readBytes() } catch (_: Exception) {
                                    throw DocumentWriter.Failure("local_failed")
                                }
                                val expectedName = call.argument<String>("name")
                                if (expectedName != null && metadata(uri)["name"] != expectedName) {
                                    throw DocumentWriter.Failure("renamed")
                                }
                                DocumentWriter.publish(bytes, requireNotNull(call.argument<String>("hash")), { readDocument(uri) }) { output ->
                                    if (expectedName != null && metadata(uri)["name"] != expectedName) {
                                        throw DocumentWriter.Failure("renamed")
                                    }
                                    contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                                        stream.write(output)
                                        stream.flush()
                                    } ?: error("The document provider refused write access")
                                }
                            }
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            val code = (e as? DocumentWriter.Failure)?.code ?: "unavailable"
                            runOnUiThread { result.error(code, "Document operation failed: $code", null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readDocument(uri: Uri): ByteArray =
        contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("The document provider refused read access")

    private fun hash(bytes: ByteArray) = DocumentWriter.hash(bytes)

    private fun metadata(uri: Uri): Map<String, Any?> {
        val fields = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED, DocumentsContract.Document.COLUMN_FLAGS)
        // Not all providers support optional document columns.
        val cursor = try { contentResolver.query(uri, fields, null, null, null) }
            catch (_: Exception) { contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null) }
        cursor?.use {
            if (!it.moveToFirst()) error("Document unavailable")
            fun value(column: String): Any? {
                val index = it.getColumnIndex(column)
                if (index < 0 || it.isNull(index)) return null
                return if (column == OpenableColumns.DISPLAY_NAME) it.getString(index) else it.getLong(index)
            }
            return mapOf("name" to value(OpenableColumns.DISPLAY_NAME), "size" to value(OpenableColumns.SIZE),
                "modified" to value(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
                "flags" to value(DocumentsContract.Document.COLUMN_FLAGS))
        }
        error("Document metadata unavailable")
    }

    @Deprecated("Android activity result callback used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4101) return
        val result = pickerResult ?: return
        pickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            result.success(metadata(uri) + mapOf("uri" to uri.toString()))
        } catch (e: Exception) {
            result.error("permission", "Persistent document access is required", null)
        }
    }
}
