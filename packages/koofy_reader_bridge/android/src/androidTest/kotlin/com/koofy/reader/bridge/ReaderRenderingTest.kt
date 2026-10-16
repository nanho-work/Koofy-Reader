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


    @Test fun settingsPanelAccordionPreservesViewportAndReadingAnchor() {
        launch()
        val original = ReaderRuntime.session!!.locatorJson!!
        var viewport = android.util.Size(0, 0)
        var panel: ReaderSettingsDialog? = null
        var dialog: androidx.appcompat.app.AlertDialog? = null
        fun view(name: String): android.view.View = ReaderSettingsDialog::class.java.getDeclaredField(name).apply { isAccessible = true }.get(panel) as android.view.View
        fun all(view: android.view.View): List<android.view.View> = listOf(view) +
            (if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList())
        fun section(name: String) { view("root").findViewWithTag<android.view.View>("reader.settings.section.$name").performClick() }
        fun choice(title: String): android.widget.Button = all(view("root")).filterIsInstance<android.widget.Button>().first { it.text.toString().removePrefix("✓ ") == title }
        scenario!!.onActivity { activity ->
            viewport = android.util.Size(navigator(activity).view!!.width, navigator(activity).view!!.height)
            ReaderActivity::class.java.getDeclaredMethod("showSettings").apply { isAccessible = true }.invoke(activity)
            panel = ReaderActivity::class.java.getDeclaredField("settingsDialog").apply { isAccessible = true }.get(activity) as ReaderSettingsDialog
            dialog = ReaderSettingsDialog::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(panel) as androidx.appcompat.app.AlertDialog
        }
        awaitCondition("Side panel did not finish its entrance") {
            var ready = false
            scenario!!.onActivity { ready = view("root").width > 0 && view("shell").translationX == 0f }
            ready
        }
        fun capturePanel(name: String) {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("screencap -p /sdcard/Download/koofy-settings-panel-$name.png")).use { it.readBytes() }
        }
        capturePanel("closed")
        scenario!!.onActivity { section("spacing") }
        awaitCondition("Expanded spacing was not laid out") {
            var laidOut = false
            scenario!!.onActivity { laidOut = all(view("root")).filterIsInstance<android.widget.SeekBar>().any { it.height > 0 } }
            laidOut
        }
        capturePanel("spacing")
        scenario!!.onActivity { section("spacing") }
        scenario!!.onActivity { activity ->
            section("footer")
            val options = all(view("root")).filterIsInstance<android.widget.Button>().map { it.text.toString().removePrefix("✓ ") }
            assertTrue(options.contains("없음") && options.contains("진행률"))
            assertFalse(options.contains("위치") || options.contains("함께"))
            assertEquals(viewport, android.util.Size(navigator(activity).view!!.width, navigator(activity).view!!.height))
            assertTrue(view("shell").width < view("root").width)
            assertTrue("Overlay must cover the complete reader height", view("root").height >= viewport.height)
            assertTrue("Panel must reach the reader bottom", view("shell").height >= viewport.height)
            val density = activity.resources.displayMetrics.density
            val base = if (viewport.width / density >= 700) viewport.width / 2 else viewport.width
            assertEquals(ReaderSettingsDialog.panelWidth(base, (240 * density).toInt()), view("shell").width)
            assertEquals(8, all(view("root")).count { it.tag?.toString()?.startsWith("reader.settings.section.") == true })
            section("spacing")
            assertEquals(1, all(view("root")).filterIsInstance<android.widget.SeekBar>().size)
            section("spacing")
            assertTrue(all(view("root")).filterIsInstance<android.widget.SeekBar>().isEmpty())
            section("font")
            assertNull(all(view("root")).firstOrNull { it.tag == "reader.settings.section.theme" })
            section("page"); choice("연속 스크롤").performClick()
        }
        awaitCondition("Scroll mode update was not applied") { ReaderRuntime.session!!.ready && ReaderRuntime.session!!.preferences.scroll }
        scenario!!.onActivity {
            assertFalse(choice("두 페이지").isEnabled)
            assertFalse(choice("책장 넘기기").isEnabled)
            assertTrue(choice("페이지 넘김").isEnabled)
            choice("페이지 넘김").performClick()
        }
        awaitCondition("Paged reading did not restore its anchor") { ReaderRuntime.session!!.ready && !ReaderRuntime.session!!.preferences.scroll && ReaderRuntime.session!!.locatorJson == original }
        // A backdrop tap must dismiss without becoming a page turn.
        scenario!!.onActivity { view("root").performClick() }
        awaitCondition("Backdrop tap did not close settings") { !dialog!!.isShowing }
        scenario!!.onActivity { activity ->
            assertEquals(viewport, android.util.Size(navigator(activity).view!!.width, navigator(activity).view!!.height))
            assertEquals(original, ReaderRuntime.session!!.locatorJson)
        }
    }

    @Test fun bookmarksAddRemoveUndoAndMoveWithoutNestedActionMenus() {
        launch()
        val original = ReaderRuntime.session!!.locatorJson!!
        val target = org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(original))!!
        var stored = "[]"
        var rejectSave = false
        var jumped: org.readium.r2.shared.publication.Locator? = null
        var dialog: androidx.appcompat.app.AlertDialog? = null
        var tools: ReaderTools? = null
        fun view(tag: String): android.view.View? = dialog?.window?.decorView?.findViewWithTag(tag)
        scenario!!.onActivity { activity ->
            val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
            tools = ReaderTools(activity, activity.lifecycleScope, publication, ReaderPalette.forTheme("light"), { target }, { stored }, { value, done ->
                if (rejectSave) done(false) else { stored = value; done(true) }
            }, { jumped = it }, { "42%" })
            tools!!.show()
            dialog = ReaderTools::class.java.getDeclaredField("bookmarkDialog").apply { isAccessible = true }.get(tools) as androidx.appcompat.app.AlertDialog
            assertEquals(L("이곳에 책갈피 추가"), (view("bookmark-toggle") as android.widget.Button).text.toString())
            view("bookmark-toggle")!!.performClick()
            assertEquals(1, org.json.JSONArray(stored).length())
            assertEquals(L("이곳의 책갈피 해제"), (view("bookmark-toggle") as android.widget.Button).text.toString())
        }
        val originalRow = org.json.JSONArray(stored).getJSONObject(0)
        val id = originalRow.getString("id")
        awaitCondition("Bookmark row did not expose delete directly") {
            var ready = false
            scenario!!.onActivity { ready = view("bookmark-delete-$id") != null }
            ready
        }
        android.os.SystemClock.sleep(500) // Let the dialog entrance animation finish before visual capture.
        android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("screencap -p /sdcard/Download/koofy-bookmark-manager.png")).use { it.readBytes() }
        scenario!!.onActivity {
            rejectSave = true
            view("bookmark-delete-$id")!!.performClick()
            assertEquals("Failed persistence must retain the bookmark", 1, org.json.JSONArray(stored).length())
            rejectSave = false
        }
        awaitCondition("Bookmark delete action disappeared after failure") {
            var ready = false
            scenario!!.onActivity { ready = view("bookmark-delete-$id") != null }
            ready
        }
        scenario!!.onActivity {
            view("bookmark-delete-$id")!!.performClick()
            assertEquals(0, org.json.JSONArray(stored).length())
            assertEquals(android.view.View.VISIBLE, view("bookmark-undo")!!.visibility)
            view("bookmark-undo")!!.performClick()
            val restored = org.json.JSONArray(stored).getJSONObject(0)
            assertEquals(id, restored.getString("id"))
            assertEquals(originalRow.getJSONObject("locator").toString(), restored.getJSONObject("locator").toString())
            assertEquals(L("이곳의 책갈피 해제"), (view("bookmark-toggle") as android.widget.Button).text.toString())
            dialog!!.dismiss()
            tools!!.show()
            dialog = ReaderTools::class.java.getDeclaredField("bookmarkDialog").apply { isAccessible = true }.get(tools) as androidx.appcompat.app.AlertDialog
        }
        awaitCondition("Reopening bookmarks did not retain the saved entry") {
            var ready = false
            scenario!!.onActivity { ready = view("bookmark-open-$id") != null }
            ready
        }
        scenario!!.onActivity {
            view("bookmark-open-$id")!!.performClick()
            assertFalse(dialog!!.isShowing)
            assertTrue("Saved anchor changed: ${target.toJSON()} vs ${jumped!!.toJSON()}", ReaderBookmarkIdentity.same(target, jumped!!))
            assertEquals(original, ReaderRuntime.session!!.locatorJson)
        }
    }

    @Test fun accessibleSpacingFontsFooterAndAutomaticTurning() {
        launch(preferences = ReaderPreferences(1.0, 1, false, "light", lineHeight = 2.75, fontId = "nanum-gothic", footerInfo = "both", autoTurnSeconds = 5))
        val original = ReaderRuntime.session!!.locatorJson!!
        val spacing = snapshot("""JSON.stringify({line:parseFloat(getComputedStyle(document.querySelector('p')).lineHeight)/parseFloat(getComputedStyle(document.querySelector('p')).fontSize),family:getComputedStyle(document.querySelector('p')).fontFamily})""")
        assertEquals(2.75, spacing.getDouble("line"), .08)
        assertTrue(spacing.getString("family").contains("Koofynanumgothic"))
        assertTrue(anchorVisible(original))
        var status = ""
        scenario!!.onActivity { activity ->
            status = (ReaderActivity::class.java.getDeclaredField("status").apply { isAccessible = true }.get(activity) as android.widget.TextView).text.toString()
        }
        assertTrue(status, !status.contains("위치") && status.contains("%"))
        for (id in listOf("nanum-myeongjo", "nanum-gothic")) {
            scenario!!.onActivity { it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(fontId = id)) }
            awaitCondition("Font change lost exact reading anchor") { runCatching { anchorVisible(original) && ReaderRuntime.session!!.locatorJson == original }.getOrDefault(false) }
            awaitCondition("New bundled TTF did not load") { snapshot("""JSON.stringify({loaded:Array.from(document.fonts).some(f=>f.family.includes('Koofy'+ '${id.replace("-", "")}')&&f.status==='loaded')})""").getBoolean("loaded") }
        }
        scenario!!.onActivity { it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(footerInfo = "none")) }
        scenario!!.onActivity { activity ->
            assertEquals("", (ReaderActivity::class.java.getDeclaredField("status").apply { isAccessible = true }.get(activity) as android.widget.TextView).text.toString())
            ReaderActivity::class.java.getDeclaredMethod("startAutoTurn").apply { isAccessible = true }.invoke(activity)
            assertTrue("Auto-turn must start even while the last font reflow is settling", ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
        }
        awaitCondition("Automatic turn did not advance") { ReaderRuntime.session!!.locatorJson != original }
        scenario!!.onActivity { activity ->
            val button = ReaderActivity::class.java.getDeclaredField("autoButton").apply { isAccessible = true }.get(activity) as android.widget.Button
            button.performClick()
            assertFalse(ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
            assertEquals(android.view.View.VISIBLE, button.visibility)
            assertTrue(button.text.toString().contains("▶"))
            // A previously used, now paused speech mode cannot crowd out resume.
            ReaderActivity::class.java.getDeclaredField("listeningMode").apply { isAccessible = true }.setBoolean(activity, true)
            ReaderActivity::class.java.getDeclaredMethod("updateSpeechControls").apply { isAccessible = true }.invoke(activity)
            val speechControls = ReaderActivity::class.java.getDeclaredField("speechControls").apply { isAccessible = true }.get(activity) as android.view.View
            assertEquals(android.view.View.GONE, speechControls.visibility)
            assertEquals(android.view.View.VISIBLE, button.visibility)
            assertTrue(button.contentDescription.toString().contains("5초"))
            assertTrue(button.isEnabled)
            button.performClick()
            assertTrue(ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
            assertTrue(button.text.toString().contains("Ⅱ"))
        }
        // Returning from the background leaves a visible, manually resumable control.
        scenario!!.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        scenario!!.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        scenario!!.onActivity { activity ->
            assertFalse(ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
            val button = ReaderActivity::class.java.getDeclaredField("autoButton").apply { isAccessible = true }.get(activity) as android.widget.Button
            assertEquals(android.view.View.VISIBLE, button.visibility)
            assertTrue(button.text.toString().contains("▶"))
            button.performClick()
            assertTrue(ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
        }
        scenario!!.onActivity { activity ->
            ReaderActivity::class.java.getDeclaredMethod("showSettings").apply { isAccessible = true }.invoke(activity)
            assertFalse(ReaderActivity::class.java.getDeclaredField("autoRunning").apply { isAccessible = true }.getBoolean(activity))
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { image ->
            File(context.getExternalFilesDir(null), "reader-settings-ux.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
        }
        android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("screencap -p /sdcard/Download/koofy-reader-settings-ux.png")).use { it.readBytes() }
    }

    @Test fun translationUsesSelectionAndPreservesReadingCheckpoint() {
        launch(initial = null)
        fun translation(activity: ReaderActivity): ReaderTranslation {
            val field = ReaderActivity::class.java.getDeclaredField("translation").apply { isAccessible = true }
            return field.get(activity) as ReaderTranslation
        }
        scenario!!.onActivity {
            ReaderActivity::class.java.getDeclaredMethod("toggleTranslation").apply { isAccessible = true }.invoke(it)
            assertTrue(translation(it).enabled)
        }
        Thread.sleep(1500)
        snapshot("""(function(){var p=document.querySelector('p'); p.textContent='The leaves were trembling in the wind.'; var r=document.createRange();r.selectNodeContents(p);var s=getSelection();s.removeAllRanges();s.addRange(r);return JSON.stringify({selected:s.toString()});})()""")
        awaitCondition("Selection was not sent to the translation panel") {
            var selected = false
            scenario!!.onActivity {
                val field = ReaderTranslation::class.java.getDeclaredField("source").apply { isAccessible = true }
                selected = field.get(translation(it)) == "The leaves were trembling in the wind."
            }
            selected
        }
        scenario!!.onActivity { translation(it).prepare() }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(180)
        var korean = false
        while (!korean && System.nanoTime() < deadline) {
            scenario!!.onActivity {
                val field = ReaderTranslation::class.java.getDeclaredField("result").apply { isAccessible = true }
                korean = (field.get(translation(it)) as String).any { it in '가'..'힣' }
            }
            Thread.sleep(300)
        }
        assertTrue("Foreground model download/translation failed", korean)
        InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { image ->
            File(context.getExternalFilesDir(null), "translation-panel.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        }
        val checkpoint = ReaderRuntime.session!!.locatorJson
        scenario!!.onActivity { it.pageTurns!!.request(true) }
        Thread.sleep(700)
        assertEquals("Selecting must block page turns", checkpoint, ReaderRuntime.session!!.locatorJson)
        snapshot("""(function(){getSelection().removeAllRanges();return JSON.stringify({ok:true});})()""")
        Thread.sleep(700)
        snapshot("""(function(){var r=document.createRange();r.selectNodeContents(document.querySelector('p'));getSelection().addRange(r);return JSON.stringify({ok:true});})()""")
        awaitCondition("Reselecting the same sentence must translate again") {
            var ready = false
            scenario!!.onActivity {
                val field = ReaderTranslation::class.java.getDeclaredField("result").apply { isAccessible = true }
                ready = (field.get(translation(it)) as String).any { it in '가'..'힣' }
            }
            ready
        }
        scenario!!.onActivity {
            ReaderActivity::class.java.getDeclaredMethod("toggleTranslation").apply { isAccessible = true }.invoke(it)
            assertFalse(translation(it).enabled)
        }
        awaitCondition("Reading did not resume after translation mode") { ReaderRuntime.session?.ready == true }
    }

    @Test fun registeredCoverIsOnePageAndSpeechStartsAtBody() {
        InstrumentationRegistry.getInstrumentation().context.assets.open("reader-display-cover.epub").use { input ->
            fixture.outputStream().use { input.copyTo(it) }
        }
        launch(initial = null, preferences = ReaderPreferences(1.0, 1, false, "light"))
        fun onCover() = ReaderRuntime.session!!.locatorJson?.let { isReaderDisplayCover(org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(it))) } == true
        assertTrue(onCover())
        val cover = snapshot("""JSON.stringify({columns:getComputedStyle(document.documentElement).columnCount,width:innerWidth,extent:document.documentElement.scrollWidth,image:getComputedStyle(document.body,'::before').backgroundImage.includes('image.png')})""")
        assertEquals("1", cover.getString("columns"))
        assertTrue(cover.getBoolean("image"))
        val done = CountDownLatch(1)
        var speechHref: String? = null
        scenario!!.onActivity { activity -> activity.lifecycleScope.launch {
            try {
                val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
                speechHref = speechStart(publication, org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(ReaderRuntime.session!!.locatorJson!!))!!).locator.href.toString()
            } finally { done.countDown() }
        } }
        assertTrue(done.await(10, TimeUnit.SECONDS))
        assertEquals("EPUB/section-00000.xhtml", speechHref)
        scenario!!.onActivity { navigator(it).goForward(false) }
        awaitCondition("Cover must turn to body in one action") { !onCover() }
        val body = ReaderRuntime.session!!.locatorJson!!
        scenario!!.onActivity { navigator(it).goBackward(false) }
        awaitCondition("Previous must return to cover") { onCover() }
        for (scroll in listOf(true, false)) {
            val before = ReaderRuntime.session!!.sequence
            scenario!!.onActivity { it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(scroll = scroll)) }
            awaitCondition("Cover mode switch did not settle") {
                var settled = false
                scenario!!.onActivity { activity ->
                    val target = ReaderActivity::class.java.getDeclaredField("restoreTarget").apply { isAccessible = true }.get(activity)
                    val pending = ReaderActivity::class.java.getDeclaredField("layoutPending").apply { isAccessible = true }.getBoolean(activity)
                    settled = target == null && !pending && ReaderRuntime.session!!.sequence > before
                }
                settled
            }
            assertTrue(onCover())
        }
        scenario!!.onActivity { it.goToLocator(body) }
        awaitCondition("Saved body locator must still resolve") { !onCover() }
        assertEquals(JSONObject(body).getString("href"), JSONObject(ReaderRuntime.session!!.locatorJson!!).getString("href"))
        scenario!!.onActivity { navigator(it).goBackward(false) }
        awaitCondition("Return to cover for curl") { onCover() }
        scenario!!.onActivity { it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(pageTurnStyle = "curl")) }
        awaitCondition("Cover curl did not prepare") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.next != null }
            ready
        }
        scenario!!.onActivity {
            assertEquals(1, it.pageTurns!!.surfaces!!.columns)
            assertFalse(isReaderDisplayCover(it.pageTurns!!.surfaces!!.next!!.locator))
            it.pageTurns!!.request(true)
        }
        awaitCondition("Cover curl did not move to body") { !onCover() }
        val bodyColumns = snapshot("JSON.stringify({columns:parseInt(getComputedStyle(document.documentElement).columnCount)||1})").getInt("columns")
        awaitCondition("Body curl must adopt the body column count") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.let { f -> f.next != null && f.columns == bodyColumns } == true }
            ready
        }
        scenario!!.onActivity { assertEquals(0, it.pageTurns!!.fallbackCount) }
        if (cover.getInt("width") >= 700) {
            scenario!!.onActivity { it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(columnCount = 2, pageTurnStyle = "instant")) }
            awaitCondition("Spread did not settle") { snapshot("JSON.stringify({columns:getComputedStyle(document.documentElement).columnCount})").optString("columns") == "2" }
            scenario!!.onActivity { it.goToLocator("""{"href":"EPUB/section-00000.xhtml","type":"application/xhtml+xml","locations":{"progression":0,"koofyCover":1}}""") }
            awaitCondition("Body must be beside cover") {
                val rect = snapshot("JSON.stringify({x:document.querySelector('p').getBoundingClientRect().left,width:innerWidth})")
                rect.getDouble("x") >= rect.getDouble("width") / 2 && rect.getDouble("x") < rect.getDouble("width")
            }
        }
    }

    @Test fun speechStopsOnBackgroundAndManualNavigationWithoutOverwritingReadingCheckpoint() {
        launch()
        val storage = context.getSharedPreferences("speech-test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        val fake = TestSpeechEngine()
        var speech: ReaderSpeech? = null
        var visual = org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(targetLocator()))!!
        val positions = mutableListOf<org.readium.r2.shared.publication.Locator>()
        try {
            scenario!!.onActivity { activity ->
                val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
                val field = ReaderActivity::class.java.getDeclaredField("speech").apply { isAccessible = true }
                (field.get(activity) as? ReaderSpeech)?.close()
                speech = ReaderSpeech(activity, publication, ReaderRuntime.session!!.request, { visual }, { true }, {
                    ReaderActivity::class.java.getDeclaredMethod("updateSpeechControls").apply { isAccessible = true }.invoke(activity)
                }, { it?.let(positions::add) }, storage, { fake })
                field.set(activity, speech)
                speech!!.foreground(true)
                speech!!.toggle()
            }
            awaitCondition("TTS did not start from the current text") { fake.spoken.isNotEmpty() }
            assertTrue("TTS must begin at the visible paragraph, not chapter start: ${fake.spoken.first()}", fake.spoken.first().contains("060"))
            val image = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            File(context.getExternalFilesDir(null), "speech-reader.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
            android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeShellCommand("cp ${context.getExternalFilesDir(null)}/speech-reader.png /sdcard/Download/koofy-speech-reader.png")).use { it.readBytes() }
            val checkpoint = ReaderRuntime.session!!.locatorJson
            scenario!!.onActivity {
                assertTrue(speech!!.playing)
                speech!!.foreground(false)
                assertFalse(speech!!.playing)
                fake.deliverLateCompletion()
            }
            Thread.sleep(250)
            val count = fake.spoken.size
            scenario!!.onActivity { speech!!.foreground(true) }
            Thread.sleep(250)
            assertEquals("Foreground must never resume automatically", count, fake.spoken.size)
            assertEquals("Audio checkpoint must not overwrite visual checkpoint", checkpoint, ReaderRuntime.session!!.locatorJson)
            scenario!!.onActivity {
                speech!!.selectVoice("local-ko")
                speech!!.setSpeed(1.25)
                speech!!.toggle()
            }
            awaitCondition("Explicit resume did not restart speech") { fake.spoken.size > count }
            val manager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val competing = android.media.AudioFocusRequest.Builder(android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).build())
                .setOnAudioFocusChangeListener {}.build()
            scenario!!.onActivity { manager.requestAudioFocus(competing) }
            awaitCondition("Transient audio focus loss must pause speech") {
                var paused = false; scenario!!.onActivity { paused = speech!!.playing == false }; paused
            }
            val interruptedCount = fake.spoken.size
            scenario!!.onActivity { manager.abandonAudioFocusRequest(competing) }
            Thread.sleep(200)
            assertEquals("Audio focus gain must not resume", interruptedCount, fake.spoken.size)
            scenario!!.onActivity {
                speech!!.userNavigation()
                assertFalse(speech!!.playing)
                assertTrue(speech!!.fromVisible)
                assertTrue(speech!!.hasSaved)
                assertEquals(1.25, speech!!.speed, 0.001)
                assertTrue(fake.stops > 0)
                assertEquals(checkpoint, ReaderRuntime.session!!.locatorJson)
                val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(it) as org.readium.r2.shared.publication.Publication
                val changed = ReaderSpeech(it, publication, ReaderRuntime.session!!.request.copy(contentRevision = "changed"), { visual }, { true }, {}, {}, storage, { fake })
                assertFalse("A changed book must not reuse an old audio checkpoint", changed.hasSaved)
                changed.close()
            }
            // Capture the settings with a deterministic installed voice for UI review.
            scenario!!.onActivity { activity ->
                ReaderSpeechDialog(activity, speech!!, ReaderPalette.forTheme("light")).show()
            }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            // Wait for the dialog window entrance animation before the UI capture.
            Thread.sleep(500)
            val settingsImage = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            File(context.getExternalFilesDir(null), "speech-settings.png").outputStream().use {
                settingsImage.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            settingsImage.recycle()
            android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeShellCommand("cp ${context.getExternalFilesDir(null)}/speech-settings.png /sdcard/Download/koofy-speech-settings.png")).use { it.readBytes() }
        } finally { scenario!!.onActivity { speech?.close() }; storage.edit().clear().commit() }
    }

    @Test fun speechInitializationCancelledByLeavingReaderNeverStartsLater() {
        launch()
        val storage = context.getSharedPreferences("speech-test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
        val entered = CountDownLatch(1)
        val fake = TestSpeechEngine()
        var speech: ReaderSpeech? = null
        try {
            scenario!!.onActivity { activity ->
                val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
                speech = ReaderSpeech(activity, publication, ReaderRuntime.session!!.request,
                    { org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(targetLocator())) }, { true }, {}, {}, storage,
                    { entered.countDown(); gate.await(); fake })
                speech!!.foreground(true); speech!!.toggle()
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            scenario!!.onActivity { speech!!.foreground(false); gate.complete(Unit) }
            Thread.sleep(250)
            scenario!!.onActivity { assertFalse(speech!!.playing); assertFalse(speech!!.busy); speech!!.foreground(true) }
            Thread.sleep(250)
            assertTrue("Late initialization must never produce audio", fake.spoken.isEmpty())
        } finally { scenario!!.onActivity { speech?.close() }; storage.edit().clear().commit() }
    }

    @Test fun speechStartsInLongParagraphAndResumesTheSameSentence() {
        createFixture(fixture, longParagraph = true)
        launch()
        val storage = context.getSharedPreferences("speech-test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        val fake = TestSpeechEngine()
        var speech: ReaderSpeech? = null
        var resolvedSkip = -1
        val target = org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(targetLocator()).put("text", JSONObject()
            .put("before", "페이지 시작은 문단 시작과 다릅니다. ")
            .put("highlight", "긴 문단의 80 번째 문장입니다.")
            .put("after", " 페이지 시작은 문단 시작과 다릅니다.")))!!
        try {
            scenario!!.onActivity { activity ->
                val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
                speech = ReaderSpeech(activity, publication, ReaderRuntime.session!!.request, { target }, { true }, {}, {}, storage, { resolvedSkip = speechStart(publication, target).skip; fake })
                speech!!.foreground(true); speech!!.toggle()
            }
            awaitCondition("TTS did not reach the selected sentence") { fake.spoken.isNotEmpty() }
            assertTrue("Skipped sentences must never reach the speech engine (skip=$resolvedSkip): ${fake.spoken.first()}", fake.spoken.first().contains("80 번째"))
            scenario!!.onActivity { speech!!.pause() }
            Thread.sleep(100)
            val count = fake.spoken.size
            scenario!!.onActivity { speech!!.start(savedPosition = true) }
            awaitCondition("Saved sentence did not resume") { fake.spoken.size > count }
            assertEquals("Resume must not rewind to the paragraph start", fake.spoken.first(), fake.spoken.last())
            var previousCount = fake.spoken.size
            scenario!!.onActivity { speech!!.skip(true) }
            awaitCondition("Next sentence did not play") { fake.spoken.size > previousCount }
            assertTrue(fake.spoken.last().contains("페이지 시작은"))
            scenario!!.onActivity { speech!!.pause() }
            Thread.sleep(100)
            previousCount = fake.spoken.size
            scenario!!.onActivity { speech!!.start(savedPosition = true) }
            awaitCondition("Repeated sentence did not resume") { fake.spoken.size > previousCount }
            assertTrue(fake.spoken.last().contains("페이지 시작은"))
            previousCount = fake.spoken.size
            scenario!!.onActivity { speech!!.skip(true) }
            awaitCondition("The sentence after resume did not play") { fake.spoken.size > previousCount }
            assertTrue("Repeated quotes must retain their ordinal", fake.spoken.last().contains("81 번째"))
        } finally { scenario!!.onActivity { speech?.close() }; storage.edit().clear().commit() }
    }

    @Test fun installedVoicePreviewThenBookPlaybackUsesRealTts() {
        launch()
        val storage = context.getSharedPreferences("speech-test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        var speech: ReaderSpeech? = null
        var failure: Throwable? = null
        val prepared = CountDownLatch(1)
        fun speaking(): Boolean {
            var speaking = false
            scenario!!.onActivity {
                val engine = ReaderSpeech::class.java.getDeclaredField("engine").apply { isAccessible = true }.get(speech) as? OfflineSpeechEngine
                if (engine != null) {
                    val tts = OfflineSpeechEngine::class.java.getDeclaredField("native").apply { isAccessible = true }.get(engine) as android.speech.tts.TextToSpeech
                    speaking = tts.isSpeaking
                }
            }
            return speaking
        }
        try {
            scenario!!.onActivity { activity -> activity.lifecycleScope.launch {
                try {
                    val publication = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
                    speech = ReaderSpeech(activity, publication, ReaderRuntime.session!!.request,
                        { org.readium.r2.shared.publication.Locator.fromJSON(JSONObject(targetLocator())) }, { true }, {}, {}, storage)
                    speech!!.foreground(true)
                    kotlinx.coroutines.withTimeout(20_000) { assertNotNull("Readium content service/navigator missing", speech!!.prepare()) }
                    assertTrue("Test device must have an installed offline Korean voice", speech!!.voices.isNotEmpty())
                    speech!!.selectVoice(speech!!.voices.first().id.value)
                    speech!!.preview()
                } catch (error: Throwable) { failure = error }
                finally { prepared.countDown() }
            } }
            assertTrue(prepared.await(25, TimeUnit.SECONDS))
            failure?.let { throw it }
            awaitCondition("Real preview never entered speaking state", ::speaking)
            scenario!!.onActivity { speech!!.stopPreview(); speech!!.toggle() }
            awaitCondition("Book playback after preview never entered speaking state", ::speaking)
            scenario!!.onActivity {
                assertNull(speech!!.preparationFailure)
                assertTrue(speech!!.playing)
                speech!!.foreground(false)
            }
            awaitCondition("Backgrounding did not stop the native voice") { !speaking() }
        } finally { scenario!!.onActivity { speech?.close() }; storage.edit().clear().commit() }
    }

    @Test fun missingBookContentIsNotReportedAsMissingVoiceEngine() {
        launch()
        val finished = CountDownLatch(1)
        var failure: Throwable? = null
        scenario!!.onActivity { activity -> activity.lifecycleScope.launch {
            val real = ReaderActivity::class.java.getDeclaredField("publication").apply { isAccessible = true }.get(activity) as org.readium.r2.shared.publication.Publication
            val withoutContent = org.readium.r2.shared.publication.Publication(real.manifest)
            val storage = context.getSharedPreferences("speech-test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
            val speech = ReaderSpeech(activity, withoutContent, ReaderRuntime.session!!.request,
                { null }, { true }, {}, {}, storage, { TestSpeechEngine() })
            val noEngine = ReaderSpeech(activity, real, ReaderRuntime.session!!.request,
                { null }, { true }, {}, {}, storage, { null })
            try {
                assertNull(speech.prepare())
                assertTrue("Installed voices remain available even when content service is absent", speech.voices.isNotEmpty())
                assertEquals(SpeechPreparationFailure.CONTENT_SERVICE_MISSING, speech.preparationFailure)
                assertNull(noEngine.prepare())
                assertEquals(SpeechPreparationFailure.ENGINE_INITIALIZATION, noEngine.preparationFailure)
            } catch (error: Throwable) { failure = error }
            finally { speech.close(); noEngine.close(); withoutContent.close(); storage.edit().clear().commit(); finished.countDown() }
        } }
        assertTrue("Preparation did not finish", finished.await(20, TimeUnit.SECONDS))
        failure?.let { throw it }
    }

    private class TestSpeechEngine : ReaderSpeechEngine {
        val spoken = java.util.concurrent.CopyOnWriteArrayList<String>()
        var stops = 0
        private var callback: org.readium.navigator.media.tts.TtsEngine.Listener<org.readium.navigator.media.tts.android.AndroidTtsEngine.Error>? = null
        private var last: org.readium.navigator.media.tts.TtsEngine.RequestId? = null
        override val voices = setOf(org.readium.navigator.media.tts.android.AndroidTtsEngine.Voice(
            org.readium.navigator.media.tts.android.AndroidTtsEngine.Voice.Id("local-ko"), org.readium.r2.shared.util.Language("ko")))
        override val settings = kotlinx.coroutines.flow.MutableStateFlow(org.readium.navigator.media.tts.android.AndroidTtsSettings(org.readium.r2.shared.util.Language("ko"), true, 1.0, 1.0, emptyMap()))
        override fun submitPreferences(preferences: org.readium.navigator.media.tts.android.AndroidTtsPreferences) {
            settings.value = settings.value.copy(speed = preferences.speed ?: 1.0, voices = preferences.voices.orEmpty())
        }
        override fun setListener(listener: org.readium.navigator.media.tts.TtsEngine.Listener<org.readium.navigator.media.tts.android.AndroidTtsEngine.Error>?) { callback = listener }
        override fun speak(requestId: org.readium.navigator.media.tts.TtsEngine.RequestId, text: String, language: org.readium.r2.shared.util.Language?) {
            last = requestId; spoken.add(text); callback?.onStart(requestId)
        }
        override fun stop() { stops++ }
        override fun close() { stop(); callback = null }
        fun deliverLateCompletion() { last?.let { callback?.onDone(it) } }
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

    @Test fun localFontsLoadRealFacesPreserveAnchorAndRefreshCurl() {
        createFixture(fixture, fontFaces = true)
        launch(preferences = ReaderPreferences(1.0, 0, false, "sepia", "curl", "maplestory"))
        val original = ReaderRuntime.session!!.locatorJson!!
        val faces = snapshot("""JSON.stringify((function(){
            document.fonts.load('700 16px "KoofyMaplestory"', '한글 Bold');
            return {family:getComputedStyle(document.querySelector('p')).fontFamily};
        })())""")
        assertTrue(faces.getString("family").contains("KoofyMaplestory"))
        awaitCondition("Maple Light and Bold must load real local OTFs") {
            snapshot("""JSON.stringify({loaded:Array.from(document.fonts).filter(f=>f.family.includes('KoofyMaplestory')&&f.status==='loaded').map(f=>f.weight).sort().join(',')})""")
                .optString("loaded") == "300,700"
        }
        var prior = 0L
        awaitCondition("Initial custom-font curl not prepared") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.next != null; prior = it.pageTurns!!.generation }
            ready
        }
        scenario!!.onActivity {
            it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(fontId = "hakgyoansim-siganpyo"))
            assertNull(it.pageTurns!!.surfaces)
        }
        awaitCondition("School font did not load") {
            snapshot("""JSON.stringify({family:getComputedStyle(document.querySelector('p')).fontFamily,loaded:Array.from(document.fonts).some(f=>f.family.includes('KoofySiganpyo')&&f.status==='loaded')})""")
                .let { it.optString("family").contains("KoofySiganpyo") && it.optBoolean("loaded") }
        }
        awaitCondition("Changed font images did not replace old images") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns!!.surfaces?.let { f -> f.generation > prior && f.next != null } == true }
            ready
        }
        assertEquals(original, ReaderRuntime.session!!.locatorJson)
        assertTrue(anchorVisible(original))
        assertCurlMatchesBaseline()
        val resume = ReaderRuntime.session!!.locatorJson!!
        val savedPreferences = ReaderRuntime.session!!.preferences
        scenario!!.close()
        launch(initial = resume, preferences = savedPreferences)
        assertEquals(resume, ReaderRuntime.session!!.locatorJson)
        assertTrue(anchorVisible(resume))
        assertTrue(snapshot("JSON.stringify({family:getComputedStyle(document.querySelector('p')).fontFamily})").getString("family").contains("KoofySiganpyo"))
        scenario!!.onActivity { it.applyReaderPreferences(savedPreferences.copy(fontId = "default", pageTurnStyle = "instant", fontScale = 1.4, scroll = true)) }
        awaitCondition("Default must restore the publication font") {
            runCatching { !snapshot("JSON.stringify({family:getComputedStyle(document.querySelector('p')).fontFamily})").getString("family").contains("Koofy") }.getOrDefault(false)
        }
        assertTrue(anchorVisible(resume))
    }

    @Test fun personalFontRendersAndReaderMenuKeepsUnavailableSpread() {
        val directory = File(context.filesDir, "personal_fonts").apply { mkdirs() }
        val manifest = File(directory, "catalog.json")
        val previous = if (manifest.exists()) manifest.readBytes() else null
        val face = ReaderFonts(context).families.first().faces.first()
        val file = File(directory, face.file.name)
        val existed = file.exists()
        val id = "personal_" + face.file.nameWithoutExtension.take(32)
        try {
            face.file.copyTo(file, overwrite = true)
            manifest.writeText("""{"version":1,"families":[{"id":"$id","label":"개인 글꼴 테스트","cssFamily":"KoofyPersonal_${id.removePrefix("personal_")}","faces":[{"file":"${file.name}","weight":400,"sha256":"${file.nameWithoutExtension}"}]}]}""")
            launch(initial = null, preferences = ReaderPreferences(1.0, 1, false, "light", fontId = id))
            assertTrue(snapshot("JSON.stringify({loaded:Array.from(document.fonts).some(f=>f.family.includes('KoofyPersonal_')&&f.status==='loaded')})").getBoolean("loaded"))
            val speechStarted = java.util.concurrent.atomic.AtomicBoolean(false)
            scenario!!.onActivity { activity ->
                val speechButton = ReaderActivity::class.java.getDeclaredField("speechButton").apply { isAccessible = true }.get(activity) as android.widget.Button
                assertEquals(android.view.View.INVISIBLE, speechButton.visibility)
                val settings = ReaderSettingsDialog(activity, { ReaderRuntime.session!!.preferences }, {}, canShowSpread = { false }, speechStart = { speechStarted.set(true) })
                settings.show()
                val dialog = ReaderSettingsDialog::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(settings) as androidx.appcompat.app.AlertDialog
                fun texts(view: android.view.View): List<android.widget.TextView> =
                    (if (view is android.widget.TextView) listOf(view) else emptyList()) +
                    (if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { texts(view.getChildAt(it)) } else emptyList())
                fun labels() = texts(dialog.window!!.decorView)
                dialog.window!!.decorView.findViewWithTag<android.view.View>("reader.settings.section.page").performClick()
                assertTrue(labels().any { it.text.toString() == "두 페이지" && it is android.widget.Button && !it.isEnabled })
                assertFalse(labels().any { it.text.toString() == "줄간격" })
                dialog.window!!.decorView.findViewWithTag<android.view.View>("reader.settings.section.spacing").performClick()
                assertTrue(labels().any { it.text.toString() == "줄간격" })
                dialog.window!!.decorView.findViewWithTag<android.view.View>("reader.settings.section.speech").performClick()
                labels().first { it.text.toString().contains("듣기 시작 / 재개") }.performClick()
            }
            awaitCondition("Speech action must wait for panel dismissal") { speechStarted.get() }
        } finally {
            if (previous == null) manifest.delete() else manifest.writeBytes(previous)
            if (!existed) file.delete()
        }
    }

    @Test fun downloadedFontCatalogLoadsVerifiedFacesAndSkipsCorruptOnes() {
        val directory = File(context.cacheDir, "downloaded-font-test-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val bundled = ReaderFonts(context).families.first().faces.first()
            val target = File(directory, bundled.file.name)
            bundled.file.copyTo(target)
            val id = "remote_" + "a".repeat(32)
            File(directory, "catalog.json").writeText("""{"version":1,"families":[{"id":"$id","label":"다운로드 글꼴","cssFamily":"KoofyRemote_${"a".repeat(32)}","faces":[{"file":"${target.name}","weight":300,"sha256":"${target.nameWithoutExtension}"}]}]}""")
            val loaded = ReaderFonts(context, directory)
            assertTrue(loaded.optionIds.contains(id))
            assertEquals("다운로드 글꼴", loaded.optionLabels[loaded.optionIds.indexOf(id)])
            assertNotNull(loaded.family(id))
            target.writeText("corrupted downloaded font")
            val repaired = ReaderFonts(context, directory)
            assertFalse(repaired.optionIds.contains(id))
            assertTrue(repaired.optionIds.contains("maplestory"))
            assertTrue(ReaderFonts.isValidId(id))
            assertFalse(ReaderFonts.isValidId("remote_../escape"))
        } finally { directory.deleteRecursively() }
    }

    @Test fun corruptLocalFontIsRepairedFromVerifiedBundle() {
        val installed = ReaderFonts(context)
        val file = installed.families.first().faces.first().file
        val original = file.readBytes()
        file.writeText("interrupted download")
        ReaderFonts(context)
        assertArrayEquals(original, file.readBytes())
    }

    @Test fun appThemeFollowsShellAndPreservesExplicitBackgrounds() {
        launch()
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val key = "flutter.app_theme_v1"
        val old = prefs.getString(key, null)
        val original = ReaderRuntime.session!!.locatorJson
        try {
            for (mode in listOf("dark", "light", "sepia", "system")) {
                prefs.edit().putString(key, mode).commit()
                scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.0, 1, false, "sepia")) }
                awaitCondition("Explicit background not ready") { ReaderRuntime.session!!.ready }
                assertEquals("sepia", ReaderTheme.resolve("sepia"))
                scenario!!.onActivity { it.applyReaderPreferences(ReaderPreferences(1.0, 1, false, "app")) }
                val effective = ReaderTheme.resolve("app")
                if (mode != "system") assertEquals(mode, effective)
                val color = ReaderPalette.forTheme(effective).background
                val expected = "rgb(${android.graphics.Color.red(color)}, ${android.graphics.Color.green(color)}, ${android.graphics.Color.blue(color)})"
                awaitCondition("Follow-app canvas did not match $mode") {
                    ReaderRuntime.session!!.ready && snapshot("JSON.stringify({background:getComputedStyle(document.documentElement).backgroundColor})").getString("background") == expected
                }
                assertEquals("app", ReaderRuntime.session!!.preferences.theme)
                assertEquals(original, ReaderRuntime.session!!.locatorJson)
            }
        } finally {
            if (old == null) prefs.edit().remove(key).commit() else prefs.edit().putString(key, old).commit()
        }
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
                    if (view.contentDescription == "서재로 돌아가기") shown = view.isShown
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

    @Test fun englishReaderLabelsPreserveBookText() = localizedReader("en", "Back to library", "Reading settings")
    @Test fun japaneseReaderLabelsPreserveBookText() = localizedReader("ja", "本棚に戻る", "読書設定")

    private fun localizedReader(language: String, library: String, settings: String) {
        ReaderStrings.language = language
        try {
            launch()
            scenario!!.onActivity { activity ->
                fun texts(view: android.view.View): List<String> =
                    (if (view is android.widget.TextView) listOf(view.text.toString()) else emptyList()) +
                    (if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { texts(view.getChildAt(it)) } else emptyList())
                val labels = texts(activity.window.decorView)
                fun descriptions(view: android.view.View): List<String> = listOfNotNull(view.contentDescription?.toString()) +
                    (if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { descriptions(view.getChildAt(it)) } else emptyList())
                val accessibleLabels = labels + descriptions(activity.window.decorView)
                assertTrue(accessibleLabels.toString(), accessibleLabels.contains(library))
                assertTrue(accessibleLabels.toString(), accessibleLabels.contains(settings))
                assertTrue("Book title must stay in its original language", labels.contains("한글 독서 엔진 검증"))
                ReaderActivity::class.java.getDeclaredMethod("showSettings").apply { isAccessible = true }.invoke(activity)
            }
            Thread.sleep(500)
            android.os.ParcelFileDescriptor.AutoCloseInputStream(
                InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
                    "screencap -p /sdcard/Download/koofy-reader-$language.png")
            ).use { it.readBytes() }
        } finally { ReaderStrings.language = "ko" }
    }

    @Test fun foldableViewportAndCheckpointSurviveFoldUnfoldAndBackground() {
        val args = InstrumentationRegistry.getArguments()
        val closed = args.getString("foldClosedState")
        val opened = args.getString("foldOpenedState")
        assumeTrue("Requires explicit emulator fold state IDs", closed != null && opened != null)
        fun shell(command: String): String = android.os.ParcelFileDescriptor.AutoCloseInputStream(
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        ).bufferedReader().use { it.readText() }
        fun width(): Int {
            var result = 0
            scenario!!.onActivity { activity ->
                result = activity.window.decorView.width
                assertEquals("App window must fill the active display width",
                    activity.windowManager.maximumWindowMetrics.bounds.width(), result)
            }
            return result
        }
        fun capture(name: String) {
            shell("screencap -p /sdcard/Download/koofy-fold-$name.png")
        }
        try {
            shell("cmd device_state state reset")
            launch()
            val wide = width()
            val anchor = requireNotNull(ReaderRuntime.session!!.locatorJson)
            capture("opened")
            android.util.Log.i("KoofyFoldTest", "REQUEST_FOLD")
            awaitCondition("Closed display did not resize and restore the text") {
                width() < wide && anchorVisible(anchor)
            }
            capture("closed")
            android.util.Log.i("KoofyFoldTest", "REQUEST_UNFOLD")
            awaitCondition("Open display did not restore its width and text") {
                width() == wide && anchorVisible(anchor)
            }
            scenario!!.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            scenario!!.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            awaitCondition("Background return lost the reading anchor") { anchorVisible(anchor) }
            capture("returned")
            val before = snapshot().visibleIds()
            scenario!!.onActivity { navigator(it).goForward(false) }
            awaitCondition("Page turn after unfolding did not advance") { snapshot().visibleIds() != before }
        } finally {
            shell("cmd device_state state reset")
        }
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
            awaitCondition("Column reflow did not settle") {
                val state = snapshot()
                state.getString("columns") == (if (state.getInt("width") < 700) "1" else columns.toString())
            }
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

    @Test fun curlUsesActualPagesCancelsWithoutCheckpointAndCommitsExactlyOnePage() {
        launch(preferences = ReaderPreferences(1.0, 1, false, "light", "curl"))
        awaitCondition("Independent page image provider did not prepare a next page") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.next != null }
            ready
        }
        var target: String? = null
        var sourceImage: android.graphics.Bitmap? = null
        scenario!!.onActivity {
            val frames = requireNotNull(it.pageTurns!!.surfaces)
            sourceImage = frames.source.image
            target = frames.next!!.locator.toJSON().toString()
            assertNotEquals(frames.source.locator.toJSON().toString(), target)
            val pixels = IntArray(frames.source.image.width * frames.source.image.height)
            frames.source.image.getPixels(pixels, 0, frames.source.image.width, 0, 0,
                frames.source.image.width, frames.source.image.height)
            assertTrue("Source capture contains no rendered text", pixels.count {
                android.graphics.Color.red(it) < 180 && android.graphics.Color.alpha(it) > 200
            } > 100)
            assertFalse("Adjacent image duplicates current page", frames.source.image.sameAs(frames.next!!.image))
        }
        val before = ReaderRuntime.session!!.locatorJson
        val sequence = ReaderRuntime.session!!.sequence
        dragPage(.87f, .34f, cancel = true, capture = true)
        awaitCondition("Cancelled curl did not become idle") {
            var idle = false
            scenario!!.onActivity { idle = it.pageTurns?.state == "idle" }
            idle
        }
        assertEquals(before, ReaderRuntime.session!!.locatorJson)
        assertEquals("Preview/cancel emitted a persisted reader event", sequence, ReaderRuntime.session!!.sequence)
        scenario!!.onActivity {
            assertEquals("Prepared gestures must use curl, not fallback", 0, it.pageTurns!!.fallbackCount)
            android.util.Log.i("KoofyCurlTest", "captureMillis=${it.pageTurns!!.captureMillis} capturedBytes=${it.pageTurns!!.capturedBytes}")
        }
        dragPage(.87f, .18f, cancel = false)
        awaitCondition("Curl did not commit the prepared destination") {
            ReaderRuntime.session!!.locatorJson == target
        }
        assertTrue("Committed page must contain the prepared anchor", anchorVisible(target!!))
    }

    @Test fun consecutiveCurlsReuseImagesAndNeverFallBackDuringPreparation() {
        createFixture(fixture, paragraphCount = 600)
        launch(preferences = ReaderPreferences(1.0, 1, false, "light", "curl"))
        awaitCondition("Lookahead not prepared") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.at(2) != null }
            ready
        }
        var generation = 0L
        scenario!!.onActivity { generation = it.pageTurns!!.generation }
        repeat(10) { step ->
            val before = ReaderRuntime.session!!.locatorJson
            var prepared: PageSurface? = null
            scenario!!.onActivity {
                prepared = it.pageTurns!!.surfaces?.next
                it.pageTurns!!.request(true)
            }
            awaitCondition("Continuous turn $step was lost") {
                var idle = false
                scenario!!.onActivity { idle = it.pageTurns!!.state == "idle" }
                idle && ReaderRuntime.session!!.locatorJson != before
            }
            scenario!!.onActivity {
                val turns = it.pageTurns!!
                assertEquals("Continuous turns must retain the layout generation", generation, turns.generation)
                assertEquals("No instant fallback during normal curl preparation", 0, turns.fallbackCount)
                prepared?.let { frame -> assertSame("Destination bitmap must become current without recapture", frame.image, turns.surfaces!!.source.image) }
                assertNotNull("Reverse page must remain cached", turns.surfaces!!.previous)
            }
        }
    }

    @Test fun slowReleaseUsesHalfViewportAndCancelPreservesCheckpoint() {
        launch(preferences = ReaderPreferences(1.0, 1, false, "light", "curl"))
        awaitCondition("Curl not prepared") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.next != null }
            ready
        }
        val before = ReaderRuntime.session!!.locatorJson
        dragPage(.95f, .46f, cancel = false, releaseHold = 350)
        awaitCondition("Under-half release did not settle") {
            var idle = false
            scenario!!.onActivity { idle = it.pageTurns!!.state == "idle" }
            idle
        }
        assertEquals("Under half must return without moving the reading position", before, ReaderRuntime.session!!.locatorJson)
        var target: String? = null
        scenario!!.onActivity { target = it.pageTurns!!.surfaces!!.next!!.locator.toJSON().toString() }
        dragPage(.95f, .44f, cancel = false, releaseHold = 350)
        awaitCondition("Over-half release did not complete") { ReaderRuntime.session!!.locatorJson == target }
    }

    @Test fun changingOnlyTurnStyleKeepsNavigatorAndFontChangeInvalidatesImages() {
        launch()
        var original: EpubNavigatorFragment? = null
        val anchor = ReaderRuntime.session!!.locatorJson
        scenario!!.onActivity {
            original = navigator(it)
            it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(pageTurnStyle = "curl"))
            assertSame(original, navigator(it))
        }
        awaitCondition("Curl preparation failed after enabling style") {
            var ready = false
            scenario!!.onActivity { ready = it.pageTurns?.surfaces?.next != null }
            ready
        }
        assertEquals(anchor, ReaderRuntime.session!!.locatorJson)
        var previousGeneration = 0L
        scenario!!.onActivity {
            previousGeneration = it.pageTurns!!.generation
            it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(fontScale = 1.4))
            assertNull(it.pageTurns!!.surfaces)
        }
        awaitCondition("New font pages were not prepared") {
            var ready = false
            scenario!!.onActivity {
                ready = it.pageTurns!!.surfaces?.let { frames ->
                    frames.generation > previousGeneration && frames.next != null
                } == true
            }
            ready
        }
        assertEquals(anchor, ReaderRuntime.session!!.locatorJson)
        assertTrue(anchorVisible(anchor!!))
    }

    @Test fun spreadCurlMatchesOneRealReadiumAdvanceInsideLongParagraph() {
        createFixture(fixture, longParagraph = true)
        launch(preferences = ReaderPreferences(1.0, 2, false, "light"))
        val point = exactVisiblePoint()
        val sequence = ReaderRuntime.session!!.sequence
        scenario!!.onActivity { navigator(it).goForward(false) }
        awaitCondition("Long paragraph did not advance") {
            ReaderRuntime.session!!.sequence > sequence && exactVisiblePoint() != point
        }
        assertCurlMatchesBaseline()
    }

    @Test fun curlCrossesChapterBoundaryExactlyLikeReadium() {
        createFixture(fixture, secondChapter = true)
        launch(initial = JSONObject(targetLocator()).put("locations", JSONObject().put("progression", 1.0)).toString())
        assertCurlMatchesBaseline()
        assertTrue(ReaderRuntime.session!!.locatorJson!!.contains("second.xhtml"))
    }

    @Test fun backwardCurlMatchesReadiumAndSupportsHoldingPageEdge() {
        launch()
        assertCurlMatchesBaseline(forward = false)
    }

    @Test fun cornerTapCommitsExactlyOnePage() {
        launch()
        assertCurlMatchesBaseline(tap = true)
    }

    private fun exactVisiblePoint(): String {
        val script = context.assets.open("reader_anchor.js").bufferedReader().use { it.readText() }
            .replace("__KOOFY_RESTORE__", "false").replace("__KOOFY_ANCHOR__", "null")
        val state = snapshot(script)
        var href = ""
        scenario!!.onActivity { href = navigator(it).currentLocator.value.href.toString() }
        return href + ":" + state.optJSONObject("locations")?.optJSONObject("koofyText")?.toString()
    }

    private fun assertCurlMatchesBaseline(forward: Boolean = true, tap: Boolean = false) {
        val sourcePoint = exactVisiblePoint()
        val saved = ReaderRuntime.session!!.locatorJson!!
        val before = ReaderRuntime.session!!.sequence
        scenario!!.onActivity { if (forward) navigator(it).goForward(false) else navigator(it).goBackward(false) }
        awaitCondition("Baseline next page did not advance") {
            ReaderRuntime.session!!.sequence > before && exactVisiblePoint() != sourcePoint
        }
        val expected = exactVisiblePoint()
        val beforeRestore = ReaderRuntime.session!!.sequence
        scenario!!.onActivity { it.goToLocator(saved) }
        awaitCondition("Source page was not restored") {
            ReaderRuntime.session!!.sequence > beforeRestore && exactVisiblePoint() == sourcePoint
        }
        scenario!!.onActivity {
            it.applyReaderPreferences(ReaderRuntime.session!!.preferences.copy(pageTurnStyle = "curl"))
        }
        awaitCondition("Baseline comparison could not prepare real next page") {
            var ready = false
            scenario!!.onActivity {
                ready = if (forward) it.pageTurns!!.surfaces?.next != null else it.pageTurns!!.surfaces?.previous != null
            }
            ready
        }
        dragPage(if (forward) .94f else .06f, if (tap) .94f else if (forward) .18f else .82f,
            cancel = false, capture = !tap, holdMillis = if (forward) 0 else 650,
            steps = if (tap) 0 else 12)
        awaitCondition("Curl destination differs from one Readium advance") {
            var idle = false
            scenario!!.onActivity { idle = it.pageTurns!!.state == "idle" }
            idle && exactVisiblePoint() == expected
        }
        scenario!!.onActivity { assertEquals(0, it.pageTurns!!.fallbackCount) }
    }

    private fun dragPage(from: Float, to: Float, cancel: Boolean, capture: Boolean = false, holdMillis: Long = 0, steps: Int = 12, releaseHold: Long = 0) {
        val location = IntArray(2)
        var width = 0
        var height = 0
        scenario!!.onActivity {
            val view = navigator(it).publicationView
            view.getLocationOnScreen(location)
            width = view.width
            height = view.height
        }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val now = android.os.SystemClock.uptimeMillis()
        fun send(action: Int, portion: Float) {
            val event = android.view.MotionEvent.obtain(now, android.os.SystemClock.uptimeMillis(), action,
                location[0] + width * portion, location[1] + height * .8f, 0)
            instrumentation.sendPointerSync(event)
            event.recycle()
        }
        send(android.view.MotionEvent.ACTION_DOWN, from)
        if (holdMillis > 0) Thread.sleep(holdMillis)
        for (step in 1..steps) {
            Thread.sleep(18)
            send(android.view.MotionEvent.ACTION_MOVE, from + (to - from) * step / steps)
        }
        if (capture) {
            scenario!!.onActivity {
                assertEquals("dragging", it.pageTurns!!.state)
                assertTrue("Native WebView swallowed the page gesture", it.pageTurns!!.showingCurl)
            }
            val screenshot = instrumentation.uiAutomation.takeScreenshot()
            File(context.getExternalFilesDir(null), "curl-mid.png").outputStream().use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            screenshot.recycle()
            val fileName = if (ReaderRuntime.session!!.preferences.columnCount == 2L) "koofy-curl-mid-spread.png"
                else if (from < to) "koofy-curl-mid-backward.png" else "koofy-curl-mid.png"
            android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation
                .executeShellCommand("screencap -p /sdcard/Download/$fileName")).use { it.readBytes() }
        }
        if (releaseHold > 0) Thread.sleep(releaseHold)
        send(if (cancel) android.view.MotionEvent.ACTION_CANCEL else android.view.MotionEvent.ACTION_UP, to)
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

    private fun createFixture(file: File, longParagraph: Boolean = false, secondChapter: Boolean = false, fontFaces: Boolean = false, paragraphCount: Int = 120) {
        val paragraphs = (1..paragraphCount).joinToString("\n") { index ->
            val id = index.toString().padStart(3, '0')
            val bold = if (fontFaces) "<strong>굵은 글씨 Bold</strong>" else ""
            val repeated = if (longParagraph && index == 60) (1..160).joinToString(" ") { "긴 문단의 $it 번째 문장입니다. 페이지 시작은 문단 시작과 다릅니다." } else ""
            "<p id=\"p-$id\">$repeated $id 단락. 한글 전자책의 페이지 경계와 읽던 문장을 검증합니다. 화면 크기와 글꼴 설정이 달라져도 이 본문 위치를 다시 찾을 수 있어야 합니다.$bold</p>"
        }
        val files = linkedMapOf(
            "mimetype" to "application/epub+zip",
            "META-INF/container.xml" to """<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
            "EPUB/package.opf" to """<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">koofy-render-fixture</dc:identifier><dc:title>한글 독서 엔진 검증</dc:title><dc:language>ko</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>""",
            "EPUB/nav.xhtml" to """<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ko"><head><title>목차</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">본문</a></li></ol></nav></body></html>""",
            "EPUB/chapter.xhtml" to """<html xmlns="http://www.w3.org/1999/xhtml" lang="ko"><head><title>한글 독서 엔진 검증</title><style>body{font-family:serif}p{line-height:1.6;margin:0 0 1em}</style></head><body>$paragraphs</body></html>""",
        )
        if (secondChapter) {
            files["EPUB/package.opf"] = files.getValue("EPUB/package.opf")
                .replace("</manifest>", "<item id=\"second\" href=\"second.xhtml\" media-type=\"application/xhtml+xml\"/></manifest>")
                .replace("</spine>", "<itemref idref=\"second\"/></spine>")
            files["EPUB/second.xhtml"] = """<html xmlns="http://www.w3.org/1999/xhtml" lang="ko"><head><title>두 번째 장</title></head><body><h1 id="second-start">두 번째 장 시작</h1>$paragraphs</body></html>"""
        }
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
