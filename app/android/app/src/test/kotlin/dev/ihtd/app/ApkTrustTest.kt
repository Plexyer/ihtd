package dev.ihtd.app

import com.android.apksig.ApkSigner
import java.io.File
import java.nio.file.Files
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Test

class ApkTrustTest {
    @Test fun verifiesSignatureAndRejectsTamperingWrongSignerAndSize() {
        val directory = Files.createTempDirectory("ihtd-apk-trust").toFile()
        try {
            val store = File(directory, "temporary-test.p12")
            // Disposable test identity generated at runtime; never the release key.
            val generator = ProcessBuilder("${System.getProperty("java.home")}/bin/keytool",
                "-genkeypair", "-keystore", store.path, "-storepass", "test-password",
                "-alias", "fixture", "-dname", "CN=Disposable test", "-keyalg", "RSA",
                "-validity", "1", "-storetype", "PKCS12").redirectErrorStream(true).start()
            generator.inputStream.readBytes()
            assertEquals(0, generator.waitFor())
            val keyStore = KeyStore.getInstance("PKCS12")
            store.inputStream().use { keyStore.load(it, "test-password".toCharArray()) }
            val cert = keyStore.getCertificate("fixture") as X509Certificate
            val key = keyStore.getKey("fixture", "test-password".toCharArray()) as PrivateKey
            val source = File(directory, "unsigned.apk")
            ZipOutputStream(source.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry("AndroidManifest.xml"))
                zip.write(javaClass.classLoader!!.getResourceAsStream("fixture-manifest.bin")!!.readBytes())
                zip.closeEntry()
            }
            val apk = File(directory, "signed.apk")
            ApkSigner.Builder(listOf(ApkSigner.SignerConfig.Builder("fixture", key, listOf(cert)).build()))
                .setInputApk(source).setOutputApk(apk).setMinSdkVersion(35)
                .setV1SigningEnabled(false).setV2SigningEnabled(true).setV3SigningEnabled(true).build().sign()
            val pin = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }
            ApkTrust.verify(apk, apk.length(), ApkTrust.digest(apk), pin, 35)
            assertThrows(IllegalArgumentException::class.java) {
                ApkTrust.verify(apk, apk.length(), ApkTrust.digest(apk), "0".repeat(64), 35)
            }
            assertThrows(IllegalArgumentException::class.java) {
                ApkTrust.verify(apk, apk.length() + 1, ApkTrust.digest(apk), pin, 35)
            }
            // Recompute hash after modifying bytes: only cryptographic verification
            // can reject an attacker who changes package AND checksum together.
            val changed = apk.readBytes(); changed[100] = (changed[100].toInt() xor 1).toByte(); apk.writeBytes(changed)
            assertThrows(Exception::class.java) {
                ApkTrust.verify(apk, apk.length(), ApkTrust.digest(apk), pin, 35)
            }
        } finally { directory.deleteRecursively() }
    }
}
