package com.koofy.reader.bridge

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.content.Context
import java.io.File
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReaderCheckpointJournalTest {
    private lateinit var root: File
    private lateinit var journal: ReaderCheckpointJournal

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        root = File(context.filesDir, "journal-test-${System.nanoTime()}")
        root.mkdirs()
        journal = ReaderCheckpointJournal(root)
    }

    @After fun tearDown() { root.deleteRecursively() }

    @Test fun staleAcknowledgementCannotRemoveNewerLocation() {
        journal.write(event("session-a", 1))
        journal.write(event("session-a", 2))
        journal.acknowledge("session-a", 1)
        assertEquals(2L, journal.pending().single().sequence)
        journal.acknowledge("session-a", 2)
        assertTrue(journal.pending().isEmpty())
    }

    @Test fun aNewJournalRestoresLatestPreferencesAndLocator() {
        journal.write(event("session-a", 3))
        val recovered = ReaderCheckpointJournal(root).pending().single()
        assertEquals(3L, recovered.sequence)
        assertEquals("{\"href\":\"chapter.xhtml\",\"type\":\"application/xhtml+xml\"}", recovered.locatorJson)
        assertEquals(1.4, recovered.preferences!!.fontScale, 0.0)
        assertEquals("sepia", recovered.preferences!!.theme)
    }

    @Test fun acknowledgementsAreIsolatedBySession() {
        journal.write(event("session-a", 1))
        journal.write(event("session-b", 1))
        journal.acknowledge("session-a", 1)
        assertEquals("session-b", journal.pending().single().sessionId)
    }

    @Test fun atomicBackupIsRecoveredAfterInterruptedReplacement() {
        journal.write(event("session-a", 1))
        val file = File(root, "koofy-reader-checkpoints-v1").listFiles()!!.single { it.extension == "json" }
        assertTrue(file.renameTo(File(file.path + ".bak")))
        file.writeText("incomplete write")
        assertEquals(1L, ReaderCheckpointJournal(root).pending().single().sequence)
    }

    @Test fun errorsCannotReplaceLastDurableLocation() {
        journal.write(event("session-a", 1))
        assertThrows(IllegalArgumentException::class.java) {
            journal.write(event("session-a", 2).copy(kind = "error", errorCode = "resource_failed"))
        }
        assertEquals(1L, journal.pending().single().sequence)
    }

    @Test fun curlPreferenceRoundTripsAndLegacyMissingFieldMeansInstant() {
        val state = event("style", 1)
        journal.write(state.copy(preferences = state.preferences!!.copy(pageTurnStyle = "curl", fontId = "maplestory")))
        assertEquals("curl", ReaderCheckpointJournal(root).pending().single().preferences!!.pageTurnStyle)
        assertEquals("maplestory", ReaderCheckpointJournal(root).pending().single().preferences!!.fontId)
        val file = File(root, "koofy-reader-checkpoints-v1").listFiles()!!.single { it.extension == "json" }
        val legacy = org.json.JSONObject(file.readText())
        legacy.getJSONObject("preferences").remove("pageTurnStyle")
        legacy.getJSONObject("preferences").remove("fontId")
        file.writeText(legacy.toString())
        val recovered = ReaderCheckpointJournal(root).pending().single()
        assertEquals("instant", recovered.preferences!!.pageTurnStyle ?: "instant")
        assertEquals("default", recovered.preferences!!.fontId ?: "default")
        assertEquals(state.locatorJson, recovered.locatorJson)
    }

    @Test fun corruptRecordDoesNotHideHealthyRecordsAndKeepsBookIdentity() {
        journal.write(event("bad", 1))
        val bad = File(root, "koofy-reader-checkpoints-v1").listFiles()!!.single { it.extension == "json" }
        bad.writeText("truncated")
        journal.write(event("good", 2).copy(publicationId = "book-b"))
        val pending = ReaderCheckpointJournal(root).pending()
        assertEquals(2, pending.size)
        assertEquals("book-a", pending.single { it.kind == "recoveryIssue" }.publicationId)
        assertEquals("good", pending.single { it.kind != "recoveryIssue" }.sessionId)
        assertTrue(bad.exists())
        journal.acknowledge("good", 2)
        assertEquals("recoveryIssue", journal.pending().single().kind)
    }

    @Test fun legacyCorruptionWithoutIdentityRemainsVisibleAndIsNotDeleted() {
        journal.write(event("bad", 1))
        val files = File(root, "koofy-reader-checkpoints-v1").listFiles()!!
        files.single { it.extension == "identity" }.delete()
        val bad = files.single { it.extension == "json" }
        bad.writeText("truncated")
        assertEquals("", journal.pending().single().publicationId)
        assertTrue(bad.exists())
    }

    private fun event(id: String, sequence: Long) = ReaderEvent(
        protocolVersion = 1,
        sessionId = id,
        sessionGeneration = 1,
        publicationId = "book-a",
        contentRevision = "revision-a",
        sequence = sequence,
        kind = "locationChanged",
        locatorJson = "{\"href\":\"chapter.xhtml\",\"type\":\"application/xhtml+xml\"}",
        preferences = ReaderPreferences(1.4, 2, false, "sepia"),
    )
}
