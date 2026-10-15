package dev.ihtd.app

import com.android.apksig.ApkVerifier
import java.io.File
import java.security.MessageDigest

/** Cryptographic APK verification, not merely certificate parsing. */
object ApkTrust {
    fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val bytes = ByteArray(65536)
            while (true) {
                val count = stream.read(bytes)
                if (count < 0) break
                digest.update(bytes, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    fun verify(file: File, size: Long, hash: String, certificate: String, api: Int) {
        require(size in 1..536870912 && file.length() == size)
        require(digest(file) == hash)
        val verified = ApkVerifier.Builder(file)
            .setMinCheckedPlatformVersion(api).setMaxCheckedPlatformVersion(api)
            .build().verify()
        require(verified.isVerified && verified.signerCertificates.size == 1)
        val signer = MessageDigest.getInstance("SHA-256")
            .digest(verified.signerCertificates.single().encoded)
            .joinToString("") { "%02x".format(it) }
        require(signer == certificate)
    }
}
