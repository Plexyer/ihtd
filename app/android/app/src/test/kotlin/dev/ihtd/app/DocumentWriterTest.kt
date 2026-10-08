package dev.ihtd.app

import org.junit.Assert.*
import org.junit.Test

class DocumentWriterTest {
    private val old = "original".toByteArray()
    private val edited = "edited".toByteArray()

    @Test fun publishesAndVerifies() {
        var remote = old
        val result = DocumentWriter.publish(edited, DocumentWriter.hash(old), { remote }) { remote = it }
        assertArrayEquals(edited, remote)
        assertEquals(DocumentWriter.hash(edited), result)
    }

    @Test fun externalChangeIsNeverOverwritten() {
        val external = "other device".toByteArray()
        var writes = 0
        assertThrows(IllegalStateException::class.java) {
            DocumentWriter.publish(edited, DocumentWriter.hash(old), { external }) { writes++ }
        }
        assertEquals(0, writes)
    }

    @Test fun recoversInterruptedMetadataSaveWithoutRewriting() {
        var writes = 0
        assertEquals(DocumentWriter.hash(edited),
            DocumentWriter.publish(edited, DocumentWriter.hash(old), { edited }) { writes++ })
        assertEquals(0, writes)
    }

    @Test fun partialWriteIsReportedAndCannotOverwriteOnRetry() {
        var remote = old
        var writes = 0
        val write: (ByteArray) -> Unit = { remote = it.copyOf(2); writes++ }
        repeat(2) {
            assertThrows(IllegalStateException::class.java) {
                DocumentWriter.publish(edited, DocumentWriter.hash(old), { remote }, write)
            }
        }
        assertEquals(1, writes)
    }

    @Test fun revokedAccessDoesNotWrite() {
        var writes = 0
        assertThrows(SecurityException::class.java) {
            DocumentWriter.publish(edited, DocumentWriter.hash(old), { throw SecurityException("revoked") }) { writes++ }
        }
        assertEquals(0, writes)
    }
}
