@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment

/** Exercises the real WebView/Readium renderer; no Flutter engine or renderer mocks. */
@RunWith(AndroidJUnit4::class)
class ReaderRenderingTest {
    private lateinit var context: Context
    private lateinit var fixture: File
    private var scenario: ActivityScenario<ReaderActivity>? = null

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        fixture = File(context.filesDir, "koofy-render-${UUID.randomUUID()}.epub")
        createFixture(fixture)
        ReaderRuntime.initialize(context)
    }

    @After fun tearDown() {
        val id = ReaderRuntime.session?.request?.sessionId
        scenario?.close()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            ReaderRuntime.reader = null
            ReaderRuntime.session = null
        }
        // Drain the native writer before deleting the test's own checkpoint.
        val drained = CountDownLatch(1)
        ReaderRuntime.io.execute {
            if (id != null) ReaderRuntime.journal.pending()
                .filter { it.sessionId == id }.forEach { ReaderRuntime.journal.acknowledge(id, it.sequence) }
            drained.countDown()
        }
        assertTrue(drained.await(5, TimeUnit.SECONDS))
        fixture.delete()
    }

    @Test fun opensKnownParagraphTurnsPageAndRestoresAfterFontChange() {
        launch()
        awaitCondition("Initial paragraph p-060 was not rendered") { snapshot().visibleIds().contains("p-060") }
        val before = snapshot().visibleIds()
        scenario!!.onActivity { navigator(it).goForward(false) }
        awaitCondition("Next page did not change the visible paragraph range") {
            snapshot().visibleIds().let { it.isNotEmpty() && it != before }
        }
        // Restore a real EPUB fragment, then exercise the production preference path.
        scenario!!.onActivity { it.goToLocator(targetLocator()) }
        awaitCondition("Explicit paragraph restoration did not finish") { snapshot().visibleIds().contains("p-060") }
        scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.4, 1, false, "sepia")) }
        awaitCondition("Font reflow lost the requested paragraph") {
            val state = snapshot()
            state.getDouble("fontSize") >= 20 && state.visibleIds().contains("p-060")
        }
        assertNotNull(ReaderRuntime.session?.locatorJson)
    }

    @Test fun themeColorsMatchCanvasAndChromeWithoutMovingAnchor() {
        launch()
        val anchor = ReaderRuntime.session!!.locatorJson
        for (theme in listOf("sepia", "dark", "light")) {
            val palette = ReaderPalette.forTheme(theme)
            scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.0, 1, false, theme)) }
            val expected = "rgb(${android.graphics.Color.red(palette.background)}, ${android.graphics.Color.green(palette.background)}, ${android.graphics.Color.blue(palette.background)})"
            awaitCondition("EPUB background does not match $theme chrome") {
                snapshot("JSON.stringify({background:getComputedStyle(document.documentElement).backgroundColor})")
                    .getString("background") == expected
            }
            scenario!!.onActivity {
                val root = (it.findViewById<android.view.ViewGroup>(android.R.id.content)).getChildAt(0)
                assertEquals(palette.background, (root.background as android.graphics.drawable.ColorDrawable).color)
            }
            assertEquals(anchor, ReaderRuntime.session!!.locatorJson)
        }
        val before = snapshot()
        fun tapCenter() {
            val location = IntArray(2)
            scenario!!.onActivity {
                val view = navigator(it).publicationView
                view.getLocationOnScreen(location)
                location[0] += view.width / 2
                location[1] += view.height / 2
            }
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val now = android.os.SystemClock.uptimeMillis()
            for (action in listOf(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.ACTION_UP)) {
                val event = android.view.MotionEvent.obtain(now, now + 50, action, location[0].toFloat(), location[1].toFloat(), 0)
                instrumentation.sendPointerSync(event)
                event.recycle()
            }
        }
        fun chromeShown(): Boolean {
            var shown = false
            scenario!!.onActivity { activity ->
                fun find(view: android.view.View) {
                    if (view is android.widget.Button && view.text == "서재") shown = view.isShown
                    if (view is android.view.ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))
                }
                find(activity.findViewById(android.R.id.content))
            }
            return shown
        }
        tapCenter()
        awaitCondition("Center tap did not hide chrome") { !chromeShown() }
        assertEquals(before.getInt("height"), snapshot().getInt("height"))
        assertEquals(anchor, ReaderRuntime.session!!.locatorJson)
        tapCenter()
        awaitCondition("Center tap did not restore chrome") { chromeShown() }
        assertEquals(before.getInt("height"), snapshot().getInt("height"))
        assertEquals(anchor, ReaderRuntime.session!!.locatorJson)
    }

    @Test fun twoPagesAreActualCssColumnsOnWideViewport() {
        launch()
        // Android 16 ignores app orientation requests on large displays. They
        // already have enough width for a spread, including portrait tablets.
        if (snapshot().getInt("width") < 700) {
            scenario!!.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
            awaitCondition("Wide viewport was not applied") { snapshot().getInt("width") >= 700 }
        }
        val first = snapshot()
        assumeTrue("Requires a viewport at least 700 CSS px wide", first.getInt("width") >= 700)
        scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.0, 2, false, "light")) }
        awaitCondition("The renderer did not apply two real CSS columns") {
            val state = snapshot()
            state.getString("columns") == "2" && state.visibleIds().contains("p-060")
        }
        val before = snapshot().visibleIds()
        scenario!!.onActivity { navigator(it).goForward(false) }
        awaitCondition("The next spread did not advance its content") { snapshot().visibleIds() != before }
    }

    @Test fun characterAnchorSurvivesRepeatedReopenAndColumnChanges() {
        createFixture(fixture, longParagraph = true)
        launch()
        scenario!!.onActivity { navigator(it).goForward(false) }
        awaitCondition("A page inside the long paragraph was not captured as a character") {
            val location = ReaderRuntime.session?.locatorJson?.let { JSONObject(it) }
            (location?.optJSONObject("locations")?.optJSONObject("koofyText")?.optInt("charOffset") ?: 0) > 0
        }
        val canonical = requireNotNull(ReaderRuntime.session?.locatorJson)
        for (cycle in 0 until 4) {
            val columns = if (cycle % 2 == 0) 2L else 1L
            scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.0 + cycle * 0.1, columns, false, "light")) }
            awaitCondition("Column reflow did not settle") { snapshot().getString("columns") == columns.toString() }
            Thread.sleep(1200) // Include duplicate/late pagination notifications.
            assertEquals("Reflow rewrote the reading anchor", canonical, ReaderRuntime.session?.locatorJson)
            val session = requireNotNull(ReaderRuntime.session)
            scenario!!.onActivity { it.closeReader() }
            awaitCondition("Close checkpoint did not finish") { ReaderRuntime.session == null }
            val persisted = ReaderRuntime.journal.pending().first { it.sessionId == session.request.sessionId }
            assertEquals(canonical, persisted.locatorJson)
            scenario!!.close()
            scenario = null
            launch(persisted.locatorJson, persisted.preferences!!)
            Thread.sleep(1200)
            assertEquals("Reopen $cycle drifted backwards", canonical, ReaderRuntime.session?.locatorJson)
            assertTrue("The saved character is not actually visible", anchorVisible(canonical))
            ReaderRuntime.journal.acknowledge(persisted.sessionId, persisted.sequence)
        }
    }

    @Test fun repeatedTextRestoresExactDomOffsetInsteadOfFirstMatchingQuote() {
        createFixture(fixture, longParagraph = true)
        val point = JSONObject().put("cssSelector", "#p-060").put("textNodeIndex", 0).put("charOffset", 2500)
        val anchor = JSONObject(targetLocator()).put("locations", JSONObject()
            .put("cssSelector", "#p-060").put("koofyText", point))
            .put("text", JSONObject().put("highlight", "문")).toString()
        launch(anchor)
        assertTrue("Repeated text quote must not displace the DOM point", anchorVisible(anchor))
        assertEquals(anchor, ReaderRuntime.session?.locatorJson)
    }

    private fun anchorVisible(locator: String): Boolean {
        val script = context.assets.open("reader_anchor.js").bufferedReader().use { it.readText() }
            .replace("__KOOFY_RESTORE__", "false").replace("__KOOFY_ANCHOR__", locator)
        return snapshot(script).optBoolean("anchorVisible", false)
    }

    private fun launch(initial: String? = targetLocator(), preferences: ReaderPreferences = ReaderPreferences(1.0, 1, false, "light")) {
        val request = ReaderLaunchRequest(
            protocolVersion = 1,
            sessionId = "render-test-${UUID.randomUUID()}",
            sessionGeneration = 1,
            publicationId = "render-fixture",
            contentRevision = "v1",
            filePath = fixture.path,
            title = "한글 독서 엔진 검증",
            initialLocatorJson = initial,
            preferences = preferences,
        )
        InstrumentationRegistry.getInstrumentation().runOnMainSync { ReaderRuntime.session = ReaderSession(request) }
        scenario = ActivityScenario.launch(Intent(context, ReaderActivity::class.java)
            .putExtra(ReaderActivity.SESSION_ID, request.sessionId))
        awaitCondition("Reader did not reach ready") {
            var ready = false
            scenario!!.onActivity { ready = ReaderRuntime.session?.ready == true }
            ready
        }
    }

    private fun snapshot(script: String = DOM_SNAPSHOT): JSONObject {
        val completed = CountDownLatch(1)
        var result: String? = null
        var failure: Throwable? = null
        scenario!!.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { result = navigator(activity).evaluateJavascript(script) }
                catch (error: Throwable) { failure = error }
                finally { completed.countDown() }
            }
        }
        assertTrue("DOM snapshot timed out", completed.await(5, TimeUnit.SECONDS))
        failure?.let { throw AssertionError("DOM snapshot failed", it) }
        val raw = requireNotNull(result) { "No active EPUB WebView" }
        // WebView's callback JSON-encodes a returned JS string once more.
        val json = if (raw.startsWith("\"")) org.json.JSONTokener(raw).nextValue() as String else raw
        return JSONObject(json)
    }

    private fun navigator(activity: ReaderActivity) =
        activity.supportFragmentManager.findFragmentByTag("koofy.epub") as EpubNavigatorFragment

    private fun JSONObject.visibleIds(): List<String> = getJSONArray("visible").let { array ->
        (0 until array.length()).map { array.getString(it) }
    }

    private fun awaitCondition(message: String, predicate: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            if (predicate()) return
            Thread.sleep(100)
        }
        fail(message)
    }

    private fun targetLocator() = """{"href":"EPUB/chapter.xhtml","type":"application/xhtml+xml","locations":{"fragments":["p-060"]}}"""

    private fun createFixture(file: File, longParagraph: Boolean = false) {
        val paragraphs = (1..120).joinToString("\n") { index ->
            val id = index.toString().padStart(3, '0')
            val repeated = if (longParagraph && index == 60) (1..160).joinToString(" ") { "긴 문단의 $it 번째 문장입니다. 페이지 시작은 문단 시작과 다릅니다." } else ""
            "<p id=\"p-$id\">$repeated $id 단락. 한글 전자책의 페이지 경계와 읽던 문장을 검증합니다. 화면 크기와 글꼴 설정이 달라져도 이 본문 위치를 다시 찾을 수 있어야 합니다.</p>"
        }
        val files = linkedMapOf(
            "mimetype" to "application/epub+zip",
            "META-INF/container.xml" to """<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
            "EPUB/package.opf" to """<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">koofy-render-fixture</dc:identifier><dc:title>한글 독서 엔진 검증</dc:title><dc:language>ko</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>""",
            "EPUB/nav.xhtml" to """<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ko"><head><title>목차</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">본문</a></li></ol></nav></body></html>""",
            "EPUB/chapter.xhtml" to """<html xmlns="http://www.w3.org/1999/xhtml" lang="ko"><head><title>한글 독서 엔진 검증</title><style>body{font-family:serif}p{line-height:1.6;margin:0 0 1em}</style></head><body>$paragraphs</body></html>""",
        )
        ZipOutputStream(file.outputStream()).use { zip ->
            files.forEach { (name, text) ->
                val bytes = text.toByteArray(Charsets.UTF_8)
                val entry = ZipEntry(name)
                if (name == "mimetype") {
                    entry.method = ZipEntry.STORED
                    entry.size = bytes.size.toLong()
                    entry.crc = CRC32().apply { update(bytes) }.value
                }
                zip.putNextEntry(entry)
                zip.write(bytes)
                zip.closeEntry()
            }
        }
    }
}

private const val DOM_SNAPSHOT = """JSON.stringify((function(){
    var root = document.documentElement;
    var style = getComputedStyle(root);
    var visible = Array.from(document.querySelectorAll('p[id]')).filter(function(p){
      return Array.from(p.getClientRects()).some(function(r){
        return r.right > 0 && r.left < innerWidth && r.bottom > 0 && r.top < innerHeight;
      });
    }).map(function(p){return p.id;});
    return {width:innerWidth, height:innerHeight, columns:style.columnCount, fontSize:parseFloat(style.fontSize), visible:visible};
  })());"""
