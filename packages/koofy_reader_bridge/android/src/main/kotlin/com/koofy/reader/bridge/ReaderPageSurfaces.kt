@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.fragment.app.FragmentContainerView
import androidx.fragment.app.FragmentManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.json.JSONTokener
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.css.RsProperties
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import kotlin.coroutines.resume

internal fun readerNavigatorConfiguration(fonts: ReaderFonts) = EpubNavigatorFragment.Configuration(
    shouldApplyInsetsPadding = false,
    readiumCssRsProperties = RsProperties(overrides = mapOf(
        "--RS__colWidth" to "auto", "--RS__colCount" to "var(--USER__colCount, 1)",
    )),
).also(fonts::configure)

internal data class PageSurface(val image: Bitmap, val locator: Locator)

/** A rolling window of at most five viewports, scoped to one layout generation. */
internal class PageSurfaces(
    val generation: Long,
    source: PageSurface,
    val columns: Int,
    val rtl: Boolean,
) {
    private val pages = mutableMapOf(0 to source)
    private val boundaries = mutableSetOf<Int>()
    private var center = 0
    val source: PageSurface get() = pages.getValue(center)
    val next: PageSurface? get() = at(1)
    val previous: PageSurface? get() = at(-1)
    fun at(offset: Int): PageSurface? = pages[center + offset]
    fun known(offset: Int): Boolean = pages.containsKey(center + offset) || boundaries.contains(center + offset)
    fun put(offset: Int, frame: PageSurface?) {
        if (frame == null) boundaries.add(center + offset) else pages[center + offset] = frame
    }
    fun advance(target: PageSurface): Boolean {
        val index = pages.entries.firstOrNull { it.value === target }?.key ?: return false
        center = index
        val expired = pages.keys.filter { kotlin.math.abs(it - center) > 2 }
        expired.forEach { pages.remove(it)?.image?.recycle() }
        boundaries.removeAll { kotlin.math.abs(it - center) > 2 }
        return true
    }
    fun recycle() {
        pages.values.map { it.image }.distinct().forEach { if (!it.isRecycled) it.recycle() }
        pages.clear()
        boundaries.clear()
    }
}

/**
 * An independent, attached Readium navigator. Its events are private to this provider;
 * it has no ReaderSession, ReaderRuntime, checkpoint writer, or access to the main locator.
 * The host stays VISIBLE behind the real navigator, at exactly the same measured size.
 */
internal class ReaderPageSurfaces(
    private val fragments: FragmentManager,
    private val host: FragmentContainerView,
    private val publication: Publication,
    private val anchorScript: String,
    private val fonts: ReaderFonts,
) {
    private data class Position(val index: Int, val count: Int, val locator: Locator)
    private val events = Channel<Position>(Channel.CONFLATED)
    private var reader: EpubNavigatorFragment? = null
    private var position: Position? = null
    private var navigatorEpoch = 0L
    var lastCaptureMillis = 0L
        private set
    var capturedBytes = 0L
        private set
    var sourceMismatch = false
        private set
    var lastFailure: String? = null
        private set

    suspend fun prepare(
        main: EpubNavigatorFragment,
        preferences: EpubPreferences,
        generation: Long,
        existing: PageSurfaces? = null,
        preferForward: Boolean = true,
        publish: (PageSurfaces) -> Unit,
    ) {
        var frames = existing
        var unattachedSource: PageSurface? = null
        var published = existing != null
        try {
            lastFailure = null
            sourceMismatch = false
            val sourceLocator = exactLocator(main, main.currentLocator.value)
            currentCoroutineContext().ensureActive()
            if (frames == null) {
                val source = capture(main, sourceLocator)
                unattachedSource = source
                val columns = json(main, GEOMETRY).optInt("columns", 1).coerceIn(1, 2)
                frames = PageSurfaces(generation, source, columns,
                    main.settings.value.readingProgression == ReadingProgression.RTL)
                unattachedSource = null
            } else {
                sourceMismatch = !samePoint(sourceLocator, frames.source.locator)
                check(!sourceMismatch) { "Visible page differs from cached source" }
            }
            val window = frames
            if (reader == null) {
                recreate(preferences, sourceLocator)
                awaitPosition { it.locator.href.removeFragment() == sourceLocator.href.removeFragment() }
            }
            val preview = requireNotNull(reader)
            if (existing == null) {
                align(preview, sourceLocator)
                check(samePoint(sourceLocator, exactLocator(preview, requireNotNull(position).locator))) {
                    "Preview layout differs from visible page"
                }
            }
            currentCoroutineContext().ensureActive()
            publish(window)
            published = true
            // Adjacent faces first, then one more in each direction. Existing
            // destination/source bitmaps survive a commit and are never recaptured.
            val order = if (preferForward) listOf(1, 2, -1, -2) else listOf(-1, -2, 1, 2)
            for (offset in order) {
                currentCoroutineContext().ensureActive()
                if (window.known(offset)) continue
                val direction = offset > 0
                val baseOffset = offset - if (direction) 1 else -1
                val base = window.at(baseOffset)
                if (base == null) { window.put(offset, null); publish(window); continue }
                align(preview, base.locator)
                val webView = readyWebView(preview)
                val origin = requireNotNull(position).copy(index = kotlin.math.abs(webView.scrollX) / webView.width)
                position = origin
                if (canMove(origin, direction)) {
                    move(preview, origin, direction)
                    val target = exactLocator(preview, requireNotNull(position).locator)
                    currentCoroutineContext().ensureActive()
                    check(!samePoint(base.locator, target)) { "Preview did not advance" }
                    window.put(offset, capture(preview, target))
                } else window.put(offset, null)
                publish(window)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: OutOfMemoryError) {
            lastFailure = "Not enough memory for page images"
            disposeNavigator()
        } catch (error: Exception) {
            lastFailure = error.message ?: error.javaClass.simpleName
            android.util.Log.w("KoofyPageSurfaces", "Preview unavailable: $lastFailure", error)
            disposeNavigator()
        } finally {
            unattachedSource?.image?.recycle()
            if (!published) frames?.recycle()
            // Keep the attached renderer warm until a layout change, background
            // transition or memory warning. It never writes reading checkpoints.
        }
    }

    private suspend fun align(preview: EpubNavigatorFragment, locator: Locator) {
        val current = position?.locator
        if (current != null && samePoint(exactLocator(preview, current), locator)) return
        navigate(preview, locator)
        restore(preview, locator)
    }

    private fun recreate(preferences: EpubPreferences, initial: Locator) {
        disposeNavigator()
        val epoch = navigatorEpoch
        val factory = EpubNavigatorFactory(publication).createFragmentFactory(
            initialLocator = initial,
            initialPreferences = preferences,
            configuration = readerNavigatorConfiguration(fonts),
            paginationListener = object : EpubNavigatorFragment.PaginationListener {
                override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
                    if (epoch != navigatorEpoch) return
                    position = Position(pageIndex, totalPages, locator)
                    events.trySend(requireNotNull(position))
                }
            },
        )
        val navigator = factory.instantiate(host.context.classLoader,
            EpubNavigatorFragment::class.java.name) as EpubNavigatorFragment
        reader = navigator
        fragments.beginTransaction().replace(host.id, navigator, "koofy.preview").commitNow()
    }

    private suspend fun awaitPosition(predicate: (Position) -> Boolean): Position = withTimeout(8_000) {
        while (true) {
            val current = events.receive()
            if (predicate(current)) return@withTimeout current
        }
        @Suppress("UNREACHABLE_CODE") error("unreachable")
    }

    private fun drain() { while (events.tryReceive().isSuccess) Unit }

    private suspend fun navigate(navigator: EpubNavigatorFragment, locator: Locator) {
        drain()
        check(navigator.go(locator, false))
        awaitPosition { it.locator.href.removeFragment() == locator.href.removeFragment() }
    }

    private suspend fun restore(navigator: EpubNavigatorFragment, locator: Locator) {
        withTimeout(4_000) {
            while (true) {
                val state = json(navigator, anchorScript.replace("__KOOFY_RESTORE__", "true")
                    .replace("__KOOFY_ANCHOR__", locator.toJSON().toString()))
                if (!state.has("anchorVisible") || state.isNull("anchorVisible") ||
                    state.optBoolean("anchorVisible")) break
                delay(32)
            }
        }
        readyWebView(navigator)
    }

    private fun canMove(origin: Position, forward: Boolean): Boolean {
        val resource = publication.readingOrder.indexOfFirst {
            it.url().removeFragment() == origin.locator.href.removeFragment()
        }
        return if (forward) origin.index < origin.count - 1 || resource < publication.readingOrder.lastIndex
        else origin.index > 0 || resource > 0
    }

    private suspend fun move(navigator: EpubNavigatorFragment, origin: Position, forward: Boolean) {
        drain()
        check(if (forward) navigator.goForward(false) else navigator.goBackward(false))
        awaitPosition { it.index != origin.index || it.locator.href != origin.locator.href }
    }

    private suspend fun exactLocator(navigator: EpubNavigatorFragment, base: Locator): Locator {
        readyWebView(navigator)
        val value = json(navigator, anchorScript.replace("__KOOFY_RESTORE__", "false")
            .replace("__KOOFY_ANCHOR__", "null"))
        val locations = value.optJSONObject("locations") ?: return base
        val result = base.toJSON()
        val merged = result.optJSONObject("locations") ?: JSONObject()
        merged.remove("fragments")
        locations.keys().forEach { merged.put(it, locations.get(it)) }
        result.put("locations", merged).put("text", value.optJSONObject("text"))
        return requireNotNull(Locator.fromJSON(result))
    }

    private fun samePoint(a: Locator, b: Locator): Boolean {
        if (a.href.removeFragment() != b.href.removeFragment()) return false
        val ap = a.toJSON().optJSONObject("locations")?.optJSONObject("koofyText")
        val bp = b.toJSON().optJSONObject("locations")?.optJSONObject("koofyText")
        return if (ap != null || bp != null) ap?.toString() == bp?.toString()
        else a.locations.progression == b.locations.progression
    }

    private suspend fun readyWebView(navigator: EpubNavigatorFragment): WebView = withTimeout(5_000) {
        var stable: String? = null
        while (true) {
            val state = json(navigator, GEOMETRY)
            val view = currentWebView(navigator.publicationView)
            val signature = state.toString() + ":${view?.scrollX}:${view?.scrollY}"
            if (view != null && state.optBoolean("ready") && signature == stable) {
                suspendCancellableCoroutine<Unit> { continuation ->
                    view.postVisualStateCallback(SystemClock.uptimeMillis(), object : WebView.VisualStateCallback() {
                        override fun onComplete(requestId: Long) {
                            if (continuation.isActive) continuation.resume(Unit)
                        }
                    })
                }
                return@withTimeout view
            }
            stable = if (state.optBoolean("ready")) signature else null
            delay(32)
        }
        @Suppress("UNREACHABLE_CODE") error("unreachable")
    }

    private suspend fun capture(navigator: EpubNavigatorFragment, locator: Locator): PageSurface {
        val started = SystemClock.elapsedRealtime()
        val view = readyWebView(navigator)
        currentCoroutineContext().ensureActive()
        check(view.width == host.width && view.height == host.height) { "Preview viewport mismatch" }
        // Five viewports use at most ~48 MiB. No per-gesture half-page bitmap copies.
        val scale = minOf(1.0, kotlin.math.sqrt(2_500_000.0 / (view.width.toDouble() * view.height)))
        val image = Bitmap.createBitmap((view.width * scale).toInt().coerceAtLeast(1),
            (view.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(image)
            canvas.scale(scale.toFloat(), scale.toFloat())
            canvas.translate(-view.scrollX.toFloat(), -view.scrollY.toFloat())
            view.draw(canvas)
            lastCaptureMillis = SystemClock.elapsedRealtime() - started
            capturedBytes = image.allocationByteCount.toLong()
            return PageSurface(image, locator)
        } catch (error: Throwable) {
            image.recycle()
            throw error
        }
    }

    fun disposeNavigator() {
        navigatorEpoch++
        reader?.let { if (it.isAdded && !fragments.isDestroyed) fragments.beginTransaction().remove(it).commitNowAllowingStateLoss() }
        reader = null
        position = null
        drain()
    }

    companion object {
        private suspend fun json(navigator: EpubNavigatorFragment, script: String): JSONObject {
            val raw = requireNotNull(navigator.evaluateJavascript(script))
            val value = JSONTokener(raw).nextValue()
            return JSONObject(value as? String ?: raw)
        }

        /** Public Android view traversal, isolated here; no Readium private fields/reflection. */
        internal fun currentWebView(root: View): WebView? {
            val candidates = mutableListOf<Pair<WebView, Int>>()
            val viewport = Rect()
            root.getGlobalVisibleRect(viewport)
            fun visit(view: View) {
                if (view is WebView && view.isShown && view.width > 0 && view.height > 0) {
                    val visible = Rect()
                    if (view.getGlobalVisibleRect(visible) && visible.intersect(viewport))
                        candidates += view to visible.width() * visible.height()
                }
                if (view is ViewGroup) for (i in 0 until view.childCount) visit(view.getChildAt(i))
            }
            visit(root)
            return candidates.maxByOrNull { it.second }?.first
        }
        private const val GEOMETRY = """JSON.stringify((function(){var d=document.documentElement,s=getComputedStyle(d);return {ready:document.readyState==='complete'&&(!document.fonts||document.fonts.status==='loaded')&&Array.from(document.images).every(function(i){return i.complete;}),columns:parseInt(s.columnCount)||1,width:innerWidth,height:innerHeight,scroll:document.scrollingElement.scrollLeft,font:s.fontSize,total:d.scrollWidth};})())"""
    }
}
