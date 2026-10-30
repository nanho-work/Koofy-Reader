package com.koofy.reader.bridge

import android.content.Context
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat
import androidx.appcompat.app.AlertDialog
import androidx.core.view.ViewCompat

/** An overlay: opening or resizing settings never changes the navigator's viewport. */
internal class ReaderSettingsDialog(
    private val context: Context,
    private val current: () -> ReaderPreferences,
    private val change: (ReaderPreferences) -> Unit,
    private val fontIds: List<String> = ReaderFonts.ids,
    private val fontLabels: List<String> = ReaderFonts.labels,
    private val speechSettings: (() -> Unit)? = null,
    private val translationSettings: (() -> Unit)? = null,
    private val translationEnabled: Boolean = false,
    private val canShowSpread: () -> Boolean = { true },
    private val speechStart: (() -> Unit)? = null,
    private val speechEnd: (() -> Unit)? = null,
    private val manageFonts: (() -> Unit)? = null,
    private val speechVisibility: () -> Unit = {},
    private val autoRunning: () -> Boolean = { false },
    private val toggleAuto: () -> Unit = {},
    private val previewFont: (String) -> Typeface? = { null },
    private val readerBounds: () -> Rect? = { null },
) {
    private var expanded: String? = null
    private var closing = false
    private var autoDraft: String? = null
    private val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply { isFillViewport = true; addView(column) }
    private val header = LinearLayout(context)
    private val shell = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        isClickable = true
        addView(header)
        addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
    }
    private val root = FrameLayout(context).apply {
        setBackgroundColor(0x55000000)
        isClickable = true
        setOnClickListener { dismiss() }
        addView(shell, FrameLayout.LayoutParams(dp(260), -1, Gravity.RIGHT))
    }
    private val dialog = AlertDialog.Builder(context).create()
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()

    fun show() {
        render()
        dialog.setCanceledOnTouchOutside(false)
        dialog.setOnKeyListener { _, key, event ->
            if (key == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) { dismiss(); true } else false
        }
        dialog.show()
        dialog.setContentView(root, ViewGroup.LayoutParams(-1, -1))
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(android.graphics.Color.TRANSPARENT))
            clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND or android.view.WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
            decorView.setPadding(0, 0, 0, 0)
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        }
        root.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob ->
            if (r - l != or - ol || b - t != ob - ot) resizePanel()
        }
        root.post {
            if (closing || !dialog.isShowing) return@post
            resizePanel()
            shell.translationX = shell.layoutParams.width.toFloat()
            shell.animate().translationX(0f).setDuration(220).start()
            header.sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)
        }
    }

    private fun resizePanel() {
        if (root.width == 0 || root.height == 0) return
        val origin = IntArray(2).also { root.getLocationOnScreen(it) }
        val bounds = readerBounds()
        val right = bounds?.right?.minus(origin[0])?.coerceIn(0, root.width) ?: root.width
        val paneWidth = bounds?.width()?.coerceAtMost(root.width) ?: root.width
        val baseWidth = if (canShowSpread() && paneWidth >= dp(600)) paneWidth / 2 else paneWidth
        val width = panelWidth(baseWidth, dp(240))
        val top = bounds?.top?.minus(origin[1])?.coerceIn(0, root.height) ?: 0
        val height = bounds?.height()?.coerceAtMost(root.height - top) ?: root.height
        val next = FrameLayout.LayoutParams(width, height, Gravity.TOP or Gravity.RIGHT).apply {
            topMargin = top; rightMargin = root.width - right
        }
        val old = shell.layoutParams as FrameLayout.LayoutParams
        if (old.width != next.width || old.height != next.height || old.topMargin != next.topMargin || old.rightMargin != next.rightMargin) shell.layoutParams = next
    }

    internal fun dismiss(after: () -> Unit = {}) {
        if (closing || !dialog.isShowing) return
        closing = true
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.hideSoftInputFromWindow(root.windowToken, 0)
        shell.animate().cancel()
        if (!shell.isLaidOut || !shell.isAttachedToWindow) { dialog.dismiss(); after(); return }
        shell.animate().translationX(shell.width.toFloat()).setDuration(180).withEndAction {
            dialog.dismiss(); after()
        }.start()
    }

    fun refreshLayout() { if (dialog.isShowing && !closing) { resizePanel(); render() } }

    private fun render(focus: String? = null) {
        val oldY = scroll.scrollY
        val p = current()
        val colors = ReaderPalette.forTheme(p.theme)
        column.removeAllViews(); header.removeAllViews()
        header.gravity = Gravity.CENTER_VERTICAL; header.isBaselineAligned = false
        header.setPadding(dp(16), dp(8), dp(8), dp(8))
        column.setPadding(dp(16), 0, dp(16), dp(24))
        shell.setBackgroundColor(colors.background)
        fun label(text: String, size: Float = 13f) = TextView(context).apply {
            this.text = text; textSize = size; setTextColor(colors.foreground)
            setPadding(0, dp(8), 0, dp(8))
        }
        fun button(text: String, selected: Boolean = false, action: () -> Unit) = Button(context).apply {
            this.text = text; isAllCaps = false; stateListAnimator = null; elevation = 0f
            textSize = 14f; minWidth = 0; minimumWidth = 0; minimumHeight = dp(48)
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setTextColor(if (selected) colors.accent else colors.foreground)
            background = android.graphics.drawable.StateListDrawable().apply {
                addState(intArrayOf(android.R.attr.state_pressed), ColorDrawable(colors.panel))
                addState(intArrayOf(), ColorDrawable(android.graphics.Color.TRANSPARENT))
            }
            isSelected = selected
            if (selected) setTypeface(typeface, Typeface.BOLD)
            setOnClickListener { action() }
        }
        fun update(next: ReaderPreferences) { change(next); render() }
        header.addView(label(L("독서 설정"), 19f), LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(button("×") { dismiss() }.apply { contentDescription = L("닫기"); gravity = Gravity.CENTER; setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, 25f); setPadding(0, 0, 0, 0) }, LinearLayout.LayoutParams(dp(48), -2))
        fun note(text: String) { column.addView(label(text, 12f).apply { setTextColor(colors.secondary) }) }
        var focused: View? = null
        fun section(id: String, title: String, summary: String, content: () -> Unit) {
            val open = expanded == id
            val heading = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL; minimumHeight = dp(68)
                setPadding(0, dp(10), 0, dp(10)); isFocusable = true; isClickable = true
                tag = "reader.settings.section.$id"
                contentDescription = "$title, $summary, ${if (open) L("접기") else L("펼치기")}"
                ViewCompat.setAccessibilityHeading(this, true)
                setOnClickListener { expanded = if (open) null else id; render(id) }
            }
            val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; isBaselineAligned = false }
            row.addView(label(title, 16f).apply { setPadding(0, 0, 0, 0) }, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(label(if (open) "⌃" else "⌄", 18f).apply { setPadding(dp(8), 0, 0, 0); importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO })
            heading.addView(row)
            heading.addView(label(summary, 12f).apply { setPadding(0, dp(4), 0, 0); setTextColor(colors.secondary) })
            column.addView(heading)
            if (focus == id) focused = heading
            if (open) content()
            column.addView(View(context).apply { setBackgroundColor(colors.secondary); alpha = .18f }, LinearLayout.LayoutParams(-1, dp(1)))
        }
        fun choices(title: String, labels: List<String>, selected: Int, enabled: Boolean = true, unavailable: Set<Int> = emptySet(), action: (Int) -> Unit) {
            if (title.isNotBlank()) column.addView(label(title))
            labels.forEachIndexed { i, text ->
                column.addView(button(if (i == selected) "✓ $text" else text, i == selected) { action(i) }.apply {
                    isEnabled = enabled && i !in unavailable; alpha = if (isEnabled) 1f else .4f
                }, LinearLayout.LayoutParams(-1, -2))
            }
        }
        val selectedFont = (p.fontId ?: "default").takeIf { it in fontIds } ?: "default"
        val fontName = fontLabels.getOrNull(fontIds.indexOf(selectedFont)) ?: L("기본")
        section("font", L("글자·글꼴"), "${(p.fontScale * 100).toInt()}% · $fontName") {
            column.addView(label(L("글자 크기")))
            val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; isBaselineAligned = false }
            row.addView(button("A−") { update(current().copy(fontScale = (current().fontScale - .1).coerceAtLeast(.5))) }.apply { contentDescription = L("글자 작게"); gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(48), -2))
            row.addView(label("${(p.fontScale * 100).toInt()}%", 16f).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(button("A+") { update(current().copy(fontScale = (current().fontScale + .1).coerceAtMost(3.0))) }.apply { contentDescription = L("글자 크게"); gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(48), -2))
            column.addView(row)
            var lastGroup = ""
            fontIds.forEachIndexed { index, id ->
                val group = if (id.startsWith("personal_")) L("내 글꼴") else if (id.startsWith("remote_")) L("다운로드 글꼴") else L("기본 글꼴")
                if (group != lastGroup) { column.addView(label(group)); lastGroup = group }
                column.addView(button((if (id == selectedFont) "✓ " else "") + fontLabels[index] + "\n" + L("오늘도 한 페이지를 읽습니다."), id == selectedFont) {
                    update(current().copy(fontId = id))
                }.apply { previewFont(id)?.let { typeface = it } }, LinearLayout.LayoutParams(-1, -2))
            }
            column.addView(button(L("＋ 내 글꼴 추가·관리")) { dismiss { manageFonts?.invoke() } })
        }
        section("spacing", L("줄·문단 간격"), L("줄간격") + " · " + (p.lineHeight?.let { String.format(java.util.Locale.ROOT, "%.2f×", it) } ?: L("책 기본값"))) {
            column.addView(label(L("줄간격")))
            column.addView(button(L("책 기본값"), p.lineHeight == null) { update(current().copy(lineHeight = null)) })
            val value = label(p.lineHeight?.let { String.format(java.util.Locale.ROOT, "%.2f×", it) } ?: L("기본"), 16f).apply { gravity = Gravity.CENTER }
            fun setLine(value: Double) = update(current().copy(lineHeight = (kotlin.math.round(value * 20) / 20).coerceIn(1.0, 3.0)))
            val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; isBaselineAligned = false }
            row.addView(button("−") { setLine((current().lineHeight ?: 1.5) - .05) }.apply { contentDescription = L("줄간격 줄이기"); gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(48), -2))
            row.addView(value, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(button("＋") { setLine((current().lineHeight ?: 1.5) + .05) }.apply { contentDescription = L("줄간격 늘리기"); gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(48), -2))
            column.addView(row)
            column.addView(android.widget.SeekBar(context).apply {
                max = 40; progress = (((p.lineHeight ?: 1.5) - 1) * 20).toInt(); contentDescription = L("줄간격")
                setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: android.widget.SeekBar?, step: Int, user: Boolean) { value.text = String.format(java.util.Locale.ROOT, "%.2f×", 1 + step * .05) }
                    override fun onStartTrackingTouch(bar: android.widget.SeekBar?) {}
                    override fun onStopTrackingTouch(bar: android.widget.SeekBar) { setLine(1 + bar.progress * .05) }
                })
            }, LinearLayout.LayoutParams(-1, dp(48)))
            choices(L("문단 간격"), listOf(L("기본"), L("없음"), L("보통"), L("넓게")), listOf(null, 0.0, .5, 1.0).indexOf(p.paragraphSpacing)) { update(current().copy(paragraphSpacing = listOf(null, 0.0, .5, 1.0)[it])) }
        }
        val marginLabels = listOf(L("기본"), L("좁게"), L("보통"), L("넓게"))
        section("margin", L("페이지 여백"), marginLabels.getOrElse(listOf(null, .5, 1.0, 1.5).indexOf(p.pageMargins)) { L("기본") }) {
            choices("", marginLabels, listOf(null, .5, 1.0, 1.5).indexOf(p.pageMargins)) { update(current().copy(pageMargins = listOf(null, .5, 1.0, 1.5)[it])) }
            note(L("기본은 책의 원래 설정입니다. 간격과 여백 변경은 모든 책에 적용됩니다."))
        }
        val backgrounds = listOf("light", "sepia", "dark")
        val backgroundLabels = listOf(L("밝게"), L("종이색"), L("어둡게"))
        val backgroundIndex = backgrounds.indexOf(ReaderTheme.resolve(p.theme)).coerceAtLeast(0)
        section("background", L("독서 배경"), backgroundLabels[backgroundIndex]) {
            choices("", backgroundLabels, backgroundIndex) {
                update(current().copy(theme = backgrounds[it]))
            }
        }
        section("page", L("페이지 넘김"), if (p.scroll) L("연속 스크롤") else if (p.pageTurnStyle == "curl") L("책장 넘기기") else L("바로 넘기기")) {
            choices(L("넘김 방식"), listOf(L("페이지 넘김"), L("연속 스크롤")), if (p.scroll) 1 else 0) { update(current().copy(scroll = it == 1)) }
            choices(L("페이지 배치"), listOf(L("자동"), L("한 페이지"), L("두 페이지")), p.columnCount.toInt(), !p.scroll, if (canShowSpread()) emptySet() else setOf(2)) { update(current().copy(columnCount = it.toLong())) }
            choices(L("페이지 전환 효과"), listOf(L("바로 넘기기"), L("책장 넘기기")), if (p.pageTurnStyle == "curl") 1 else 0, !p.scroll) { update(current().copy(pageTurnStyle = if (it == 1) "curl" else "instant")) }
            note(if (p.scroll) L("연속 스크롤에서는 페이지 배치와 전환 효과를 사용하지 않습니다. 선택한 설정은 유지됩니다.") else L("두 페이지 선택은 넓은 화면에서 표시됩니다."))
        }
        section("auto", L("자동 넘김"), L("넘김 간격: {0}초", p.autoTurnSeconds ?: 30)) {
            if (p.scroll) note(L("연속 스크롤에서는 자동 넘김을 사용할 수 없습니다."))
            column.addView(label(L("넘김 간격 (초) · 5~300")))
            val seconds = EditText(context).apply {
                inputType = android.text.InputType.TYPE_CLASS_NUMBER
                setText(autoDraft ?: (p.autoTurnSeconds ?: 30).toString()); setTextColor(colors.foreground)
                contentDescription = L("넘김 간격 (초)"); isEnabled = !p.scroll
                addTextChangedListener(object : android.text.TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { autoDraft = s.toString() }
                    override fun afterTextChanged(s: android.text.Editable?) {}
                })
            }
            column.addView(seconds)
            fun save(): Boolean {
                val interval = seconds.text.toString().toLongOrNull()
                if (interval == null || interval !in 5L..300L) { seconds.error = L("5~300초로 입력해 주세요."); return false }
                change(current().copy(autoTurnSeconds = interval)); return true
            }
            column.addView(button(L("저장")) { if (save()) { autoDraft = null; render() } }.apply { isEnabled = !p.scroll })
            column.addView(button(if (autoRunning()) L("자동 넘김 일시정지") else L("자동 넘김 시작")) { if (save()) dismiss { toggleAuto() } }.apply { isEnabled = !p.scroll })
        }
        val footers = listOf(L("없음"), L("진행률"))
        val footerIndex = if (p.footerInfo == "none") 0 else 1
        section("footer", L("하단 정보"), footers.getOrElse(footerIndex) { footers[1] }) {
            choices("", footers, footerIndex) { update(current().copy(footerInfo = listOf("none", "progress")[it])) }
        }
        section("speech", L("듣기"), L("목소리·속도·타이머")) {
            column.addView(button(L("▶ 듣기 시작 / 재개")) { dismiss { speechStart?.invoke() } })
            column.addView(button(L("목소리·속도·타이머")) { dismiss { speechSettings?.invoke() } })
            column.addView(button(L("듣기 종료")) { dismiss { speechEnd?.invoke() } })
            val prefs = context.getSharedPreferences("reader_speech", Context.MODE_PRIVATE)
            column.addView(SwitchCompat(context).apply {
                text = L("듣기 버튼 항상 표시"); setTextColor(colors.foreground); minHeight = dp(48)
                isChecked = prefs.getBoolean("alwaysShow", false)
                setOnCheckedChangeListener { _, value -> prefs.edit().putBoolean("alwaysShow", value).apply(); speechVisibility() }
            })
        }
        section("translation", L("번역"), if (translationEnabled) L("켜짐") else L("꺼짐")) {
            column.addView(SwitchCompat(context).apply {
                text = L("번역 모드"); setTextColor(colors.foreground); minHeight = dp(48); isChecked = translationEnabled
                setOnCheckedChangeListener { _, _ -> dismiss { translationSettings?.invoke() } }
            })
            note(L("모드를 켠 뒤 본문을 길게 눌러 단어나 문장을 선택하세요. 번역은 하단에 표시됩니다."))
        }
        scroll.post { if (!closing) scroll.scrollTo(0, focused?.top ?: oldY) }
    }
    companion object {
        internal fun panelWidth(paneWidth: Int, minimum: Int): Int = maxOf(paneWidth * 2 / 3, minOf(minimum, paneWidth)).coerceAtMost(paneWidth)
    }
}
