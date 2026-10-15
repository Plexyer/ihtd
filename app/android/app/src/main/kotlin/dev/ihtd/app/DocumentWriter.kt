package dev.ihtd.app

import java.security.MessageDigest

/** A best-effort provider conflict check, not a cross-device atomic transaction. */
internal object DocumentWriter {
    class Failure(val code: String) : IllegalStateException(code)
    fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    fun publish(bytes: ByteArray, expected: String, read: () -> ByteArray, write: (ByteArray) -> Unit): String {
        val digest = hash(bytes)
        val remote = hash(read())
        if (remote == digest) return digest // Also recovers a save interrupted before metadata commit.
        if (remote != expected) throw Failure("external_changed")
        try { write(bytes) } catch (e: Exception) {
            if (e is Failure) throw e
            throw Failure("write_failed")
        }
        val verified = try { hash(read()) } catch (_: Exception) { throw Failure("verification_failed") }
        if (verified != digest) throw Failure("verification_failed")
        return digest
    }
}
