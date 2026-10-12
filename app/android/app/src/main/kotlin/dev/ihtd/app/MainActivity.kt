package dev.ihtd.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.ihtd.app/documents")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    "pending" -> documents.execute {
                        try {
                            val pending = hash(File(requireNotNull(call.argument<String>("path"))).readBytes()) != call.argument<String>("hash")
                            runOnUiThread { result.success(pending) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("document", e.message, null) }
                        }
                    }
                    "read", "write" -> documents.execute {
                        try {
                            val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                            require(uri.scheme == "content") { "Expected a document-provider URI" }
                            val value: Any = if (call.method == "read") {
                                val remote = readDocument(uri)
                                mapOf("bytes" to remote, "hash" to hash(remote))
                            } else {
                                val local = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                                require(local.path.startsWith(filesDir.parentFile!!.canonicalPath + "/")) {
                                    "Only private working files can be published"
                                }
                                val bytes = local.readBytes()
                                DocumentWriter.publish(bytes, requireNotNull(call.argument<String>("hash")), { readDocument(uri) }) { output ->
                                    contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                                        stream.write(output)
                                        stream.flush()
                                    } ?: error("The document provider refused write access")
                                }
                            }
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("document", e.message, null) }
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
            var name = "Collection.ihtd"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) name = it.getString(0)
            }
            result.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (e: Exception) {
            result.error("permission", "Persistent document access is required: ${e.message}", null)
        }
    }
}
