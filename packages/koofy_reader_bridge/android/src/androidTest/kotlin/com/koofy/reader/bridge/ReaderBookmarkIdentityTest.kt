package com.koofy.reader.bridge

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator

@RunWith(AndroidJUnit4::class)
class ReaderBookmarkIdentityTest {
    private fun locator(offset: Int, progress: Double, title: String = "chapter", href: String = "chapter.xhtml") = Locator.fromJSON(JSONObject("""{"href":"$href","title":"$title","type":"application/xhtml+xml","locations":{"totalProgression":$progress,"position":3,"koofyText":{"cssSelector":"#p1","textNodeIndex":0,"charOffset":$offset}}}"""))!!
    @Test fun identityUsesExactAnchorInsteadOfPercentageOrDisplayMetadata() {
        val first = locator(17, .4)
        assertTrue(ReaderBookmarkIdentity.same(first, locator(17, .6, "new title")))
        assertFalse(ReaderBookmarkIdentity.same(first, locator(18, .4)))
        assertFalse(ReaderBookmarkIdentity.same(first, locator(17, .4, href = "different.xhtml")))
        assertTrue(ReaderBookmarkIdentity.same(first, Locator.fromJSON(JSONObject(first.toJSON().toString()))!!))
    }
    @Test fun decodingRowsRepeatedlyNeverConsumesStoredFragmentAnchors() {
        val json = JSONObject("""{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{"fragments":["p-060"]}}""")
        val original = json.toString()
        repeat(3) {
            val decoded = ReaderBookmarkIdentity.decode(json)!!
            assertEquals("p-060", decoded.locations.fragments.single())
            assertEquals(original, json.toString())
        }
    }
    @Test fun generatedLabelsStayValidAtTheUtf16StorageLimit() {
        val label = ReaderBookmarkIdentity.label("x".repeat(299) + "😀")
        assertEquals(299, label.length)
        assertFalse(label.last().isHighSurrogate())
        assertTrue(ReaderBookmarkIdentity.label("  ").isNotBlank())
    }
}
