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
