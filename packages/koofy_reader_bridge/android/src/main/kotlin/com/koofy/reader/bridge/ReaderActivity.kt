@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.FragmentContainerView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.json.JSONTokener
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.input.Key
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.epub.EpubLayout
import org.readium.r2.shared.publication.presentation.presentation
import org.readium.r2.shared.publication.services.isRestricted
import org.readium.r2.shared.publication.services.search.searchServiceFactory
import org.readium.r2.shared.publication.services.search.StringSearchService
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.HttpClient
import org.readium.r2.shared.util.http.HttpError
import org.readium.r2.shared.util.http.HttpRequest
import org.readium.r2.shared.util.http.HttpStreamResponse
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

/** Full-screen G1 reader. Flutter keeps ownership of the bookshelf and domain database. */
class ReaderActivity : AppCompatActivity(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener {
    companion object { const val SESSION_ID = "koofy.reader.session" }

    private lateinit var session: ReaderSession
    private lateinit var outer: FrameLayout
    private lateinit var page: LinearLayout
    private lateinit var status: TextView
    private lateinit var toolbar: LinearLayout
    private lateinit var navigation: LinearLayout
    private var bannerFooter: ReaderBannerFooter? = null
    private var chromeVisible = true
    private lateinit var container: FragmentContainerView
    private lateinit var turnHost: ReaderTurnHost
    private lateinit var previewContainer: FragmentContainerView
    private lateinit var curlView: ReaderPageCurlView
    private lateinit var spreadDivider: View
    internal var pageTurns: ReaderPageTurns? = null
        private set
    private lateinit var readerFonts: ReaderFonts
    private var publication: Publication? = null
    private var navigator: EpubNavigatorFragment? = null
    private var lastLocator: Locator? = null
    private val navigationHistory = java.util.ArrayDeque<Locator>()
    private var toolsNavigationCompleted: (() -> Unit)? = null
    private lateinit var returnButton: Button
    private var initialTarget: Locator? = null
    private var restoreTarget: Locator? = null
    private var restoreIssued = false
    private var layoutPending = false
    private var restoreTimeout: Job? = null
    private var openingTimeout: Job? = null
    private var layoutJob: Job? = null
    private var layoutGeneration = 0L
    private var lastWidth = 0
    private var lastHeight = 0
    private var hingeFallback = false
    private var loadingFailed = false
    private var captureJob: Job? = null
    private var captureGeneration = 0L
    private val anchorScript by lazy { assets.open("reader_anchor.js").bufferedReader().use { it.readText() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        // A process-restored Activity must never reopen an old Intent locator. The shell
        // first reconciles durable checkpoints with SQLite and issues a new session.
        val current = ReaderRuntime.session
        super.onCreate(null)
        if (current == null || current.request.sessionId != intent.getStringExtra(SESSION_ID)) {
            finish()
            return
        }
        session = current
        ReaderRuntime.reader = this
        session.ready = false
        buildLayout()
        if (session.closeRequested) {
            closeReader()
            return
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = closeReader()
        })
        observeFold()
        lifecycleScope.launch { openPublication() }
        openingTimeout = lifecycleScope.launch {
            delay(30_000)
            if (!session.ready && !loadingFailed) fail("open_timeout", "책을 표시하는 데 시간이 너무 오래 걸립니다.")
        }
    }

    private fun buildLayout() {
        outer = FrameLayout(this)
        page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        outer.addView(page, FrameLayout.LayoutParams(-1, -1))
        toolbar = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        toolbar.addView(button("서재") { closeReader() })
        toolbar.addView(TextView(this).apply {
            text = session.request.title
            maxLines = 1
            textSize = 16f
            setTextColor(Color.rgb(40, 35, 30))
            setPadding(dp(8), 0, dp(8), 0)
        }, LinearLayout.LayoutParams(0, -2, 1f))
        toolbar.addView(button("목차") { showContents() })
        toolbar.addView(button("찾기") { showReaderTools() })
        toolbar.addView(button("독서 설정") { showSettings() })
        page.addView(toolbar, LinearLayout.LayoutParams(-1, dp(52)))
        container = FragmentContainerView(this).apply { id = View.generateViewId() }
        previewContainer = FragmentContainerView(this).apply {
            id = View.generateViewId()
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        turnHost = ReaderTurnHost(this)
        curlView = ReaderPageCurlView(this)
        turnHost.addView(previewContainer, FrameLayout.LayoutParams(-1, -1))
        turnHost.addView(container, FrameLayout.LayoutParams(-1, -1))
        spreadDivider = View(this).apply {
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            visibility = View.GONE
        }
        turnHost.addView(spreadDivider, FrameLayout.LayoutParams(dp(1), -1, Gravity.CENTER).apply {
            topMargin = dp(24)
            bottomMargin = dp(24)
        })
        turnHost.addView(curlView, FrameLayout.LayoutParams(-1, -1))
        page.addView(turnHost, LinearLayout.LayoutParams(-1, 0, 1f))
        navigation = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        returnButton = button("↶") { returnToReading() }.apply {
            contentDescription = "이동 전 위치로"; isEnabled = false
        }
        navigation.addView(returnButton)
        navigation.addView(button("이전") { pageTurns?.request(false) })
        status = TextView(this).apply {
            text = "책을 여는 중…"
            gravity = Gravity.CENTER
            textSize = 12f
            setTextColor(Color.rgb(60, 50, 40))
        }
        navigation.addView(status, LinearLayout.LayoutParams(0, -2, 1f))
        navigation.addView(button("다음") { pageTurns?.request(true) })
        session.request.nextBookTitle?.let { title ->
            navigation.addView(button("다음 권") {
                if (session.ready && !session.closing) {
                    AlertDialog.Builder(this).setTitle("다음 권 읽기")
                        .setMessage(title)
                        .setPositiveButton("열기") { _, _ -> closeReader(nextBook = true) }
                        .setNegativeButton("취소", null).show()
                }
            })
        }
        page.addView(navigation, LinearLayout.LayoutParams(-1, dp(48)))
        bannerFooter = ReaderBannerFooter(this, session.request.bannerAdUnitId, session.adHiddenUntilEpochMs, beforeResize = {
            if (session.ready && !session.closing) scheduleRelayout()
        }).also {
            page.addView(it, LinearLayout.LayoutParams(-1, dp(66)))
        }
        ViewCompat.setOnApplyWindowInsetsListener(outer) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        container.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            val width = right - left
            val height = bottom - top
            if (width > 0 && height > 0 && (width != lastWidth || height != lastHeight)) {
                lastWidth = width
                lastHeight = height
                updateSpreadDivider()
                if (session.ready) scheduleRelayout()
            }
        }
        setContentView(outer)
        applyChromeTheme()
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        textSize = 13f
        isAllCaps = false
        stateListAnimator = null
        elevation = 0f
        setBackgroundColor(Color.TRANSPARENT)
        minWidth = dp(48)
        minimumWidth = dp(48)
        setPadding(dp(8), 0, dp(8), 0)
        setOnClickListener { action() }
    }

    private suspend fun openPublication() {
        try {
            val opened = withContext(Dispatchers.IO) {
                readerFonts = ReaderFonts(this@ReaderActivity)
                val http = object : HttpClient {
                    override suspend fun stream(request: HttpRequest): Try<HttpStreamResponse, HttpError> =
                        Try.failure(HttpError.IO(IOException("Remote publication resources are disabled")))
                }
                val retriever = AssetRetriever(contentResolver, http)
                val asset = retriever.retrieve(File(session.request.filePath).toUrl())
                    .getOrElse { throw IOException(it.message) }
                val opener = PublicationOpener(DefaultPublicationParser(this@ReaderActivity, http, retriever, null))
                opener.open(asset, allowUserInteraction = false, onCreatePublication = {
                    servicesBuilder.searchServiceFactory = StringSearchService.createDefaultFactory()
                    // Readium's own scripts are required for layout. Publication scripts,
                    // event handlers, remote fetches and nested frames are denied by CSP.
                    container = TransformingContainer(org.readium.r2.shared.util.data.CompositeContainer(readerFonts.container(), container)) { url, resource ->
                        if (url.toString().substringBefore('?').substringBefore('#')
                                .endsWithHtml()) {
                            TransformingResource(resource) { bytes ->
                                val html = bytes.toString(Charsets.UTF_8)
                                val head = Regex("<head(?:\\s[^>]*)?>", RegexOption.IGNORE_CASE).find(html)
                                if (head == null) Try.failure(ReadError.Decoding("Missing EPUB document head"))
                                else Try.success(StringBuilder(html).insert(head.range.last + 1, CONTENT_POLICY)
                                    .toString().toByteArray(Charsets.UTF_8))
                            }
                        } else resource
                    }
                }).getOrElse { asset.close(); throw IOException(it.message) }
            }
            publication = opened
            require(opened.conformsTo(Publication.Profile.EPUB) && !opened.isRestricted) {
                "보호되지 않은 EPUB 파일만 지원합니다."
            }
            require(opened.metadata.presentation.layout != EpubLayout.FIXED) {
                "고정 레이아웃 EPUB은 아직 지원하지 않습니다."
            }
            require(opened.readingOrder.isNotEmpty()) { "책에 읽을 본문이 없습니다." }
            val initial = session.locatorJson?.let { parseLocator(it) }
            if (initial != null) require(opened.linkWithHref(initial.href) != null) { "저장한 본문 위치를 찾을 수 없습니다." }
            lastLocator = initial
            initialTarget = initial
            restoreTarget = initial
            restoreIssued = true
            val factory = EpubNavigatorFactory(opened).createFragmentFactory(
                initialLocator = initial,
                initialPreferences = epubPreferences(),
                listener = this,
                paginationListener = this,
                configuration = readerNavigatorConfiguration(readerFonts),
            )
            supportFragmentManager.fragmentFactory = factory
            val reader = factory.instantiate(classLoader, EpubNavigatorFragment::class.java.name) as EpubNavigatorFragment
            navigator = reader
            supportFragmentManager.beginTransaction().replace(container.id, reader, "koofy.epub").commitNow()
            pageTurns = ReaderPageTurns(this, turnHost, curlView,
                ReaderPageSurfaces(supportFragmentManager, previewContainer, opened, anchorScript, readerFonts),
                { navigator }, { epubPreferences() },
                { session.preferences.pageTurnStyle == "curl" && !session.preferences.scroll },
                { session.ready && !session.closing && !loadingFailed && !layoutPending &&
                    restoreTarget == null && captureJob?.isActive != true },
                { target ->
                    beginRestore(target)
                    restoreIssued = true
                    navigator?.go(target, false) == true
                })
            turnHost.pageMode = !session.preferences.scroll
            reader.addInputListener(object : InputListener {
                override fun onTap(event: TapEvent): Boolean {
                    val width = reader.publicationView.width.toDouble()
                    val edge = maxOf(80.0, width * .3)
                    if (event.point.x <= edge || event.point.x >= width - edge) {
                        if (session.preferences.scroll) return false
                        val right = event.point.x >= width - edge
                        val rtl = reader.settings.value.readingProgression == org.readium.r2.navigator.preferences.ReadingProgression.RTL
                        pageTurns?.request(if (rtl) !right else right)
                        return true
                    }
                    toggleChrome()
                    return true
                }
                override fun onKey(event: KeyEvent): Boolean {
                    if (event.type != KeyEvent.Type.Down || event.modifiers.isNotEmpty()) return false
                    val rtl = reader.settings.value.readingProgression == org.readium.r2.navigator.preferences.ReadingProgression.RTL
                    val next = when (event.key) {
                        Key.ArrowRight -> !rtl
                        Key.ArrowLeft -> rtl
                        Key.ArrowDown, Key.Space -> true
                        Key.ArrowUp -> false
                        else -> return false
                    }
                    pageTurns?.request(next)
                    return true
                }
            })
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            fail("open_failed", error.message ?: "책을 열 수 없습니다.")
        }
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        if (session.closing || loadingFailed) return
        if (!session.ready && initialTarget != null &&
            initialTarget!!.href.removeFragment() != locator.href.removeFragment()) {
            fail("initial_restore_failed", "저장한 챕터로 이동하지 못했습니다. 기존 읽기 기록은 보존됩니다.")
            return
        }
        if (layoutPending) return
        val target = restoreTarget
        if (target != null && !restoreIssued) {
            restoreIssued = true
            if (navigator?.go(target, false) != true) fail("restore_failed", "읽던 위치를 복원하지 못했습니다.")
            return
        }
        if (target != null && target.href.removeFragment() != locator.href.removeFragment()) return
        val generation = ++captureGeneration
        val layout = layoutGeneration
        val reader = navigator ?: return
        captureJob?.cancel()
        captureJob = lifecycleScope.launch {
            try {
                if (readerFonts.family(session.preferences.fontId) != null) readerFonts.waitUntilStable(reader)
                // Readium emits page-rounded positions. Inspect text only after this
                // callback, and discard work belonging to an older viewport.
                val anchor = target ?: lastLocator
                val sameResource = anchor?.href?.removeFragment() == locator.href.removeFragment()
                val script = anchorScript.replace("__KOOFY_RESTORE__", (target != null).toString()).replace("__KOOFY_ANCHOR__",
                    if (sameResource) anchor?.toJSON()?.toString() ?: "null" else "null")
                val raw = reader.evaluateJavascript(script) ?: return@launch
                val value = JSONTokener(raw).nextValue()
                val snapshot = JSONObject(value as? String ?: raw)
                if (generation != captureGeneration || layout != layoutGeneration ||
                    loadingFailed) return@launch
                // Restoration is complete only when the requested character is
                // actually visible. A callback for the same chapter is insufficient.
                if (target != null && snapshot.has("anchorVisible") &&
                    !snapshot.isNull("anchorVisible") && !snapshot.optBoolean("anchorVisible")) return@launch
                val visible = sameResource && snapshot.optBoolean("anchorVisible", false)
                val exact = snapshot.optJSONObject("locations")?.let { locations ->
                    val json = locator.toJSON()
                    val merged = json.optJSONObject("locations") ?: JSONObject()
                    // Position estimates remain presentation metadata only.
                    merged.remove("fragments")
                    locations.keys().forEach { key -> merged.put(key, locations.get(key)) }
                    json.put("locations", merged)
                    json.put("text", snapshot.getJSONObject("text"))
                    parseLocator(json.toString())
                }
                val saved = if (visible) anchor!! else exact ?: target ?: locator
                restoreTimeout?.cancel()
                restoreTarget = null
                lastLocator = saved
                session.locatorJson = saved.toJSON().toString()
                val kind = if (!session.ready) "ready" else "locationChanged"
                session.ready = true
                openingTimeout?.cancel()
                status.text = buildString {
                    locator.locations.totalProgression?.let { append("${(it * 100).toInt()}% · ") }
                    append("이 장 ${pageIndex + 1} / $totalPages")
                    if (hingeFallback) append(" · 한쪽 화면")
                }
                emit(kind)
                if (target != null) {
                    val completed = toolsNavigationCompleted
                    toolsNavigationCompleted = null
                    completed?.invoke()
                }
                pageTurns?.mainSettled()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                fail("anchor_capture_failed", "본문 위치를 확인하지 못했습니다. 저장된 기록은 보존됩니다. 책을 다시 열어 주세요.")
            }
        }
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        Toast.makeText(this, "외부 링크는 독서 화면에서 열지 않습니다.", Toast.LENGTH_SHORT).show()
    }

    override fun onResourceLoadFailed(href: Url, error: ReadError) {
        runOnUiThread { fail("resource_failed", "책의 일부 내용을 불러오지 못했습니다.") }
    }

    fun goToLocator(json: String) {
        check(session.ready && !session.closing) { "The reader is not ready" }
        val locator = parseLocator(json)
        require(publication?.linkWithHref(locator.href) != null) { "Unknown publication location" }
        pageTurns?.invalidate()
        beginRestore(locator)
        restoreIssued = true
        if (navigator?.go(locator, false) != true) {
            restoreTimeout?.cancel()
            restoreTarget = null
            restoreIssued = false
            error("Could not navigate to the location")
        }
    }

    fun applyReaderPreferences(preferences: ReaderPreferences) {
        check(session.ready && !session.closing) { "The reader is not ready" }
        validatePreferences(preferences)
        val previous = session.preferences
        session.preferences = preferences
        turnHost.pageMode = !preferences.scroll
        if (previous.copy(pageTurnStyle = preferences.pageTurnStyle) == preferences) {
            pageTurns?.refresh()
        } else {
            applyChromeTheme()
            scheduleRelayout()
        }
        emit("preferencesChanged")
    }

    private fun beginRestore(anchor: Locator) {
        captureGeneration++
        captureJob?.cancel()
        restoreTarget = anchor
        restoreIssued = false
        restoreTimeout?.cancel()
        restoreTimeout = lifecycleScope.launch {
            delay(12_000)
            if (restoreTarget != null) fail("restore_timeout", "읽던 위치 복원이 완료되지 않았습니다. 책을 다시 열어 주세요.")
        }
    }

    private fun scheduleRelayout() {
        pageTurns?.invalidate()
        val generation = ++layoutGeneration
        val anchor = restoreTarget ?: lastLocator ?: return
        beginRestore(anchor)
        layoutPending = true
        layoutJob?.cancel()
        layoutJob = lifecycleScope.launch {
            delay(120)
            if (generation != layoutGeneration || session.closing) return@launch
            navigator?.submitPreferences(epubPreferences())
            // submitPreferences can be a no-op during resize. Drive restoration
            // explicitly in either case, retrying only while Readium is busy.
            delay(200)
            layoutPending = false
            restoreIssued = true
            repeat(80) {
                if (generation != layoutGeneration || session.closing || loadingFailed) return@launch
                if (navigator?.go(anchor, false) == true) return@launch
                delay(100)
            }
        }
    }

    private fun readerColumns(): ColumnCount {
        val p = session.preferences
        val usableWidth = if (::container.isInitialized && container.width > 0) container.width / resources.displayMetrics.density
            else resources.configuration.screenWidthDp.toFloat()
        return when {
            p.scroll || hingeFallback || usableWidth < 700 -> ColumnCount.ONE
            p.columnCount == 1L -> ColumnCount.ONE
            p.columnCount == 2L -> ColumnCount.TWO
            else -> ColumnCount.TWO
        }
    }

    private fun updateSpreadDivider() {
        if (!::spreadDivider.isInitialized) return
        spreadDivider.visibility = if (readerColumns() == ColumnCount.TWO) View.VISIBLE else View.GONE
        val color = ReaderPalette.forTheme(session.preferences.theme).foreground
        spreadDivider.setBackgroundColor((color and 0x00FFFFFF) or (24 shl 24))
    }

    private fun epubPreferences(): EpubPreferences {
        val p = session.preferences
        updateSpreadDivider()
        val palette = ReaderPalette.forTheme(p.theme)
        return EpubPreferences(
            backgroundColor = org.readium.r2.navigator.preferences.Color(palette.background),
            textColor = org.readium.r2.navigator.preferences.Color(palette.foreground),
            fontSize = p.fontScale,
            fontFamily = readerFonts.family(p.fontId),
            columnCount = readerColumns(),
            scroll = p.scroll,
            theme = when (p.theme) { "dark" -> Theme.DARK; "light" -> Theme.LIGHT; else -> Theme.SEPIA },
            verticalText = false,
        )
    }

    private fun showSettings() {
        if (!session.ready || session.closing) return
        ReaderSettingsDialog(this, { session.preferences }, { applyReaderPreferences(it) },
            readerFonts.optionIds, readerFonts.optionLabels).show()
    }

    private fun toggleChrome() {
        chromeVisible = !chromeVisible
        // INVISIBLE retains the navigator's exact viewport, so a menu tap cannot repaginate.
        toolbar.visibility = if (chromeVisible) View.VISIBLE else View.INVISIBLE
        navigation.visibility = if (chromeVisible) View.VISIBLE else View.INVISIBLE
    }

    @Suppress("DEPRECATION")
    private fun applyChromeTheme() {
        updateSpreadDivider()
        val palette = ReaderPalette.forTheme(session.preferences.theme)
        outer.setBackgroundColor(palette.background)
        page.setBackgroundColor(palette.background)
        bannerFooter?.applyPalette(palette)
        container.setBackgroundColor(palette.background)
        fun tint(view: View) {
            if (view is TextView) view.setTextColor(palette.foreground)
            if (view is ViewGroup) for (i in 0 until view.childCount) tint(view.getChildAt(i))
        }
        tint(toolbar)
        tint(navigation)
        status.setTextColor(palette.secondary)
        window.statusBarColor = palette.background
        window.navigationBarColor = palette.background
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        WindowCompat.getInsetsController(window, outer).apply {
            isAppearanceLightStatusBars = session.preferences.theme != "dark"
            isAppearanceLightNavigationBars = session.preferences.theme != "dark"
        }
    }

    private fun toolsReady() = session.ready && !session.closing && restoreTarget == null && captureJob?.isActive != true
    private fun jumpFromTools(target: Locator) {
        if (!toolsReady()) { Toast.makeText(this, "본문 위치 확인 후 다시 눌러 주세요.", Toast.LENGTH_SHORT).show(); return }
        val source = lastLocator ?: return
        try {
            goToLocator(target.toJSON().toString())
            toolsNavigationCompleted = {
                navigationHistory.addLast(source)
                if (navigationHistory.size > 20) navigationHistory.removeFirst()
                returnButton.isEnabled = true
            }
        } catch (_: Exception) { Toast.makeText(this, "해당 위치로 이동하지 못했습니다.", Toast.LENGTH_SHORT).show() }
    }
    private fun returnToReading() {
        if (!toolsReady() || navigationHistory.isEmpty()) return
        try {
            goToLocator(navigationHistory.last.toJSON().toString())
            toolsNavigationCompleted = {
                navigationHistory.removeLast()
                returnButton.isEnabled = navigationHistory.isNotEmpty()
            }
        } catch (_: Exception) { Toast.makeText(this, "이전 위치로 돌아가지 못했습니다.", Toast.LENGTH_SHORT).show() }
    }
    private fun showReaderTools() {
        if (!toolsReady()) return
        val pub = publication ?: return
        ReaderTools(this, lifecycleScope, pub, ReaderPalette.forTheme(session.preferences.theme), { if (toolsReady()) lastLocator else null },
            { session.bookmarksJson }, { value, done ->
                if (value.toByteArray(Charsets.UTF_8).size > 512 * 1024) { done(false) }
                else {
                    val previous = session.bookmarksJson
                    session.bookmarksJson = value
                    ReaderRuntime.emit(session.event("locationChanged")) { result ->
                        if (result.isFailure) session.bookmarksJson = previous
                        done(result.isSuccess)
                    }
                }
            }, { jumpFromTools(it) }).show()
    }

    private fun showContents() {
        if (!session.ready) return
        val links = publication?.tableOfContents.orEmpty().ifEmpty { publication?.readingOrder.orEmpty() }
        val flattened = mutableListOf<org.readium.r2.shared.publication.Link>()
        fun add(items: List<org.readium.r2.shared.publication.Link>) {
            items.forEach { flattened += it; add(it.children) }
        }
        add(links)
        AlertDialog.Builder(this).setTitle("목차")
            .setItems(flattened.mapIndexed { index, link -> link.title ?: "${index + 1}장" }.toTypedArray()) { _, index ->
                publication?.locatorFromLink(flattened[index])?.let { jumpFromTools(it) }
            }.setNegativeButton("닫기", null).show().also { dialog ->
                val colors = ReaderPalette.forTheme(session.preferences.theme)
                dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(colors.background))
                fun tint(view: View) {
                    if (view is TextView) view.setTextColor(colors.foreground)
                    if (view is ViewGroup) for (i in 0 until view.childCount) tint(view.getChildAt(i))
                }
                dialog.window?.decorView?.let { tint(it) }
            }
    }

    private fun observeFold() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                WindowInfoTracker.getOrCreate(this@ReaderActivity).windowLayoutInfo(this@ReaderActivity).collect { info ->
                    val fold = info.displayFeatures.filterIsInstance<FoldingFeature>()
                        .firstOrNull { it.isSeparating || it.occlusionType == FoldingFeature.OcclusionType.FULL }
                    outer.post {
                        if (isFinishing || isDestroyed) return@post
                        val params = FrameLayout.LayoutParams(-1, -1)
                        hingeFallback = fold != null
                        if (fold != null) {
                            val bounds = fold.bounds
                            val location = IntArray(2).also { outer.getLocationInWindow(it) }
                            if (fold.orientation == FoldingFeature.Orientation.VERTICAL) {
                                val left = (bounds.left - location[0] - outer.paddingLeft).coerceAtLeast(0)
                                val right = (outer.width - outer.paddingRight - bounds.right + location[0]).coerceAtLeast(0)
                                params.width = maxOf(left, right)
                                if (right > left) params.leftMargin = bounds.right - location[0] - outer.paddingLeft
                            } else {
                                val top = (bounds.top - location[1] - outer.paddingTop).coerceAtLeast(0)
                                val bottom = (outer.height - outer.paddingBottom - bounds.bottom + location[1]).coerceAtLeast(0)
                                params.height = maxOf(top, bottom)
                                if (bottom > top) params.topMargin = bounds.bottom - location[1] - outer.paddingTop
                            }
                        }
                        page.layoutParams = params
                        if (session.ready) scheduleRelayout()
                    }
                }
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (::session.isInitialized && session.ready) scheduleRelayout()
    }

    fun updateAdHiddenUntil(epochMs: Long?) { bannerFooter?.updateHiddenUntil(epochMs) }

    override fun onPause() {
        bannerFooter?.pause()
        pageTurns?.suspendPreparation()
        if (::session.isInitialized && session.ready && !session.closing && !loadingFailed) emit("locationChanged")
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        bannerFooter?.resume()
        if (::session.isInitialized && session.ready) pageTurns?.resumePreparation()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) pageTurns?.dispose()
    }

    override fun onActionModeStarted(mode: android.view.ActionMode) {
        super.onActionModeStarted(mode)
        if (::turnHost.isInitialized) turnHost.selecting = true
    }

    override fun onActionModeFinished(mode: android.view.ActionMode) {
        super.onActionModeFinished(mode)
        if (::turnHost.isInitialized) turnHost.selecting = false
    }

    fun closeReader(nextBook: Boolean = false) {
        if (!::session.isInitialized || session.closing) return
        session.closing = true
        pageTurns?.invalidate()
        restoreTimeout?.cancel()
        openingTimeout?.cancel()
        layoutJob?.cancel()
        lifecycleScope.launch {
            // If closing follows a settled page callback, finish its DOM read.
            // During a relayout retain the canonical pre-layout anchor.
            captureJob?.join()
            ReaderRuntime.emit(session.event("closed", message = if (nextBook) "nextBook" else null)) { result ->
                if (result.isSuccess) {
                    if (ReaderRuntime.session === session) ReaderRuntime.session = null
                    finish()
                } else {
                    session.closing = false
                    AlertDialog.Builder(this@ReaderActivity).setTitle("읽기 기록 저장 실패")
                        .setMessage("기기 저장 공간을 확인한 뒤 다시 시도해 주세요.")
                        .setPositiveButton("다시 저장") { _, _ -> closeReader(nextBook) }
                        .setNegativeButton("계속 읽기", null).show()
                }
            }
        }
    }

    private fun emit(kind: String) {
        ReaderRuntime.emit(session.event(kind)) { result ->
            if (result.isFailure && !isFinishing) {
                status.text = "읽기 기록 저장 실패 · 저장 공간을 확인해 주세요"
            }
        }
    }

    private fun fail(code: String, message: String) {
        toolsNavigationCompleted = null
        if (loadingFailed || isFinishing) return
        loadingFailed = true
        restoreTimeout?.cancel()
        openingTimeout?.cancel()
        status.text = message
        ReaderRuntime.emit(session.event("error", code, message))
        AlertDialog.Builder(this).setTitle("책을 표시할 수 없습니다")
            .setMessage(message).setCancelable(false)
            .setPositiveButton("서재로") { _, _ -> closeReader() }.show()
    }

    override fun onDestroy() {
        bannerFooter?.dispose()
        pageTurns?.dispose()
        if (ReaderRuntime.reader === this) ReaderRuntime.reader = null
        super.onDestroy()
        publication?.close()
    }

    private fun parseLocator(json: String): Locator =
        requireNotNull(Locator.fromJSON(JSONObject(json))) { "Invalid Readium locator" }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

private fun String.endsWithHtml(): Boolean =
    lowercase().let { it.endsWith(".xhtml") || it.endsWith(".html") || it.endsWith(".htm") }

private const val CONTENT_POLICY = """<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src https://readium/assets/readium/scripts/; style-src https://readium 'unsafe-inline'; img-src https://readium data:; font-src https://readium data:; media-src https://readium; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" />"""
