package dev.ihtd.app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** OS access only: shared Flutter policy owns release choice, UI and save guards. */
class UpdateBridge(private val activity: MainActivity) {
    private val worker = Executors.newSingleThreadExecutor()
    private val downloads = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = activity.getSharedPreferences("updates", Context.MODE_PRIVATE)
    private val pending: File get() = File(requireNotNull(activity.getExternalFilesDir(null)), "updates/pending.apk")
    private val verified: File get() = File(activity.filesDir, "updates/verified.apk")
    private val pin = "bea383d80c5134b0bfb8515aaa45afb15a4838540f9006ba3080ad402c7a01f4"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "identity") {
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            result.success(mapOf("version" to info.versionName, "build" to info.longVersionCode,
                "api" to Build.VERSION.SDK_INT,
                "arch" to if (Build.SUPPORTED_ABIS.contains("arm64-v8a")) "arm64" else "unsupported"))
            return
        }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "download" -> { download(call); null }
                    "observe" -> observe()
                    "verify" -> { verify(call); null }
                    "cancel" -> { cancel(); null }
                    "install" -> {
                        verify(call)
                        activity.runOnUiThread {
                            try {
                                if (!activity.packageManager.canRequestPackageInstalls()) {
                                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:${activity.packageName}")))
                                    result.success("permission")
                                } else {
                                    val uri = FileProvider.getUriForFile(activity,
                                        "${activity.packageName}.updates", verified)
                                    activity.startActivity(Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(uri, "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                    result.success("installer")
                                }
                            } catch (_: Exception) { result.error("installer", "System installer unavailable", null) }
                        }
                        return@execute
                    }
                    else -> { activity.runOnUiThread { result.notImplemented() }; return@execute }
                }
                activity.runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                val code = if (call.method == "verify" || call.method == "install") "verification" else "download_failed"
                activity.runOnUiThread { result.error(code, "Update operation failed", null) }
            }
        }
    }
    private fun candidate(call: MethodCall): String {
        val version = requireNotNull(call.argument<String>("version"))
        require(version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")))
        require(call.argument<String>("tag") == "v$version")
        val name = "IHTD-$version-android-arm64.apk"
        require(call.argument<String>("name") == name)
        require(call.argument<String>("platform") == "android")
        require(requireNotNull(call.argument<Number>("size")).toLong() in 1..536870912)
        require(requireNotNull(call.argument<String>("sha256")).matches(Regex("[a-f0-9]{64}")))
        return version
    }
    private fun cancel() {
        val id = prefs.getLong("id", -1)
        if (id >= 0) downloads.remove(id)
        pending.delete(); verified.delete()
        prefs.edit().clear().commit()
    }
    private fun download(call: MethodCall) {
        val version = candidate(call)
        cancel()
        pending.parentFile!!.mkdirs()
        val url = Uri.parse("https://github.com/Plexyer/ihtd/releases/download/v$version/IHTD-$version-android-arm64.apk")
        val request = DownloadManager.Request(url)
            .setTitle("IHTD $version update")
            .setDescription("Downloading update; you can keep using IHTD")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setMimeType("application/octet-stream")
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationUri(Uri.fromFile(pending))
        val id = downloads.enqueue(request)
        check(prefs.edit().putLong("id", id)
            .putLong("size", call.argument<Number>("size")!!.toLong())
            .putString("hash", call.argument<String>("sha256")).commit())
    }
    private fun observe(): Map<String, Any> {
        val id = prefs.getLong("id", -1)
        if (id < 0) return mapOf("state" to "missing", "bytes" to 0L, "total" to 0L)
        downloads.query(DownloadManager.Query().setFilterById(id))?.use { c ->
            if (c.moveToFirst()) {
                val status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val bytes = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val expected = prefs.getLong("size", 0)
                if (bytes > expected || total > expected) { cancel(); error("Unexpected size") }
                return mapOf("state" to when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> "complete"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "downloading"
                }, "bytes" to bytes, "total" to total)
            }
        }
        return mapOf("state" to "missing", "bytes" to 0L, "total" to 0L)
    }
    private fun verify(call: MethodCall) {
        val version = candidate(call)
        val size = call.argument<Number>("size")!!.toLong()
        val hash = call.argument<String>("sha256")!!
        // Copy only from the fixed download location into app-private storage.
        // Verification and installer handoff always operate on that private copy.
        verified.parentFile!!.mkdirs()
        if (!verified.exists() || verified.length() != size || ApkTrust.digest(verified) != hash) {
            require(pending.isFile && pending.length() == size)
            val temporary = File(verified.parentFile, "candidate.tmp")
            pending.inputStream().use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            check(temporary.renameTo(verified))
        }
        ApkTrust.verify(verified, size, hash, pin, Build.VERSION.SDK_INT)
        val pm = activity.packageManager
        val current = pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val archive = requireNotNull(pm.getPackageArchiveInfo(verified.path, PackageManager.GET_SIGNING_CERTIFICATES))
        require(archive.packageName == activity.packageName && archive.versionName == version)
        require(archive.longVersionCode == call.argument<Number>("build")!!.toLong())
        require(archive.longVersionCode > current.longVersionCode)
        require((archive.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE) <= Build.VERSION.SDK_INT)
        val installedSigners = requireNotNull(current.signingInfo).apkContentsSigners
        require(installedSigners.size == 1)
        val installedPin = java.security.MessageDigest.getInstance("SHA-256")
            .digest(installedSigners.single().toByteArray()).joinToString("") { "%02x".format(it) }
        require(installedPin == pin)
        java.util.zip.ZipFile(verified).use { zip ->
            require(zip.getEntry("lib/arm64-v8a/libapp.so") != null)
        }
    }
}
