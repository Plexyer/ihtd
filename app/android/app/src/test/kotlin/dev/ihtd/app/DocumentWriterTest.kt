package dev.ihtd.app

import org.junit.Assert.*
import org.junit.Test

class DocumentWriterTest {
    private val old = "original".toByteArray()
    private val edited = "edited".toByteArray()

    @Test fun backupRequiresANewEmptyDocumentAndVerifiesTheOriginalBytes() {
        var backup = ByteArray(0)
        DocumentWriter.backup(old, { backup }) { backup = it }
        assertArrayEquals(old, backup)
        var writes = 0
        assertThrows(DocumentWriter.Failure::class.java) {
            DocumentWriter.backup(edited, { old }) { writes++ }
        }
        assertEquals(0, writes)
        assertThrows(DocumentWriter.Failure::class.java) {
            DocumentWriter.backup(old, { old }) { writes++ }
        }
        assertEquals(0, writes)
    }

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

    @Test fun renameBarrierIsPreservedBeforeWriting() {
        var writes = 0
        val failure = assertThrows(DocumentWriter.Failure::class.java) {
            DocumentWriter.publish(edited, DocumentWriter.hash(old), { old }) {
                throw DocumentWriter.Failure("renamed")
                @Suppress("UNREACHABLE_CODE")
                writes++
            }
        }
        assertEquals("renamed", failure.code)
        assertEquals(0, writes)
    }

    @Test fun writeAndVerificationErrorsHaveDistinctSafeCodes() {
        val failedWrite = assertThrows(DocumentWriter.Failure::class.java) {
            DocumentWriter.publish(edited, DocumentWriter.hash(old), { old }) {
                error("private filename and content must not escape")
            }
        }
        assertEquals("write_failed", failedWrite.code)
        var reads = 0
        val failedVerification = assertThrows(DocumentWriter.Failure::class.java) {
            DocumentWriter.publish(edited, DocumentWriter.hash(old), {
                reads++
                if (reads == 1) old else throw SecurityException("private provider")
            }) {}
        }
        assertEquals("verification_failed", failedVerification.code)
        assertFalse(failedWrite.message!!.contains("private"))
    }
}
