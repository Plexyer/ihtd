package dev.ihtd.app

import java.security.MessageDigest

/** A best-effort provider conflict check, not a cross-device atomic transaction. */
internal object DocumentWriter {
    fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    fun publish(bytes: ByteArray, expected: String, read: () -> ByteArray, write: (ByteArray) -> Unit): String {
        val digest = hash(bytes)
        val remote = hash(read())
        if (remote == digest) return digest // Also recovers a save interrupted before metadata commit.
        check(remote == expected) {
            "The selected file changed outside IHTD. Your local copy is retained. Save a copy before reopening the changed file."
        }
        write(bytes)
        check(hash(read()) == digest) {
            "The provider did not confirm the save. Your local copy is retained; retry saving or save a copy."
        }
        return digest
    }
}
