package com.koofy.reader.bridge

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat
import androidx.appcompat.app.AlertDialog

/** Presentation only. All changes still pass through the host's anchor restoration. */
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
    private val previewFont: (String) -> Typeface? = { null },
) {
    private var detailsExpanded = false
    private var tab = 0
    private val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply { addView(column) }
    private val dialog = AlertDialog.Builder(context).setView(scroll).create()
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()

    fun show() {
        render()
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.BOTTOM)
            val available = context.resources.displayMetrics.widthPixels - dp(24)
            setLayout(minOf(available, dp(480)), ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    fun refreshLayout() { if (dialog.isShowing) render() }

    private fun render() {
        val p = current()
        val colors = ReaderPalette.forTheme(p.theme)
        column.removeAllViews()
        column.setPadding(dp(20), dp(12), dp(20), dp(24))
        column.background = GradientDrawable().apply {
            setColor(colors.background)
            cornerRadius = dp(24).toFloat()
        }
        fun label(text: String, size: Float = 13f) = TextView(context).apply {
            this.text = text
            textSize = size
            setTextColor(colors.foreground)
            setPadding(0, dp(14), 0, dp(10))
        }
        fun button(text: String, selected: Boolean = false, action: () -> Unit) = Button(context).apply {
            this.text = text
            isAllCaps = false
            stateListAnimator = null
            elevation = 0f
            textSize = 13f
            minWidth = 0
            minimumWidth = 0
            minimumHeight = dp(48)
            setPadding(dp(4), 0, dp(4), 0)
            setTextColor(if (selected) colors.background else colors.foreground)
            isSelected = selected
            if (selected) setTypeface(typeface, Typeface.BOLD)
            background = GradientDrawable().apply {
                setColor(if (selected) colors.accent else colors.panel)
                setStroke(dp(1), colors.secondary)
                cornerRadius = dp(10).toFloat()
            }
            setOnClickListener { action() }
        }
        fun update(next: ReaderPreferences) { change(next); render() }
        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        heading.addView(label("독서 설정", 20f), LinearLayout.LayoutParams(0, -2, 1f))
        heading.addView(button("완료") { dialog.dismiss() }, LinearLayout.LayoutParams(dp(64), dp(48)))
        column.addView(heading)
        val tabs = LinearLayout(context)
        listOf("보기", "듣기", "번역").forEachIndexed { i, name ->
            tabs.addView(button(name, tab == i) { tab = i; render() }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = dp(4) })
        }
        column.addView(tabs)
        if (tab == 1) {
            column.addView(button("▶  듣기 시작 / 재개") { dialog.dismiss(); speechStart?.invoke() })
            column.addView(button("목소리·속도·타이머  ›") { dialog.dismiss(); speechSettings?.invoke() })
            column.addView(button("듣기 종료") { speechEnd?.invoke(); dialog.dismiss() })
            val prefs = context.getSharedPreferences("reader_speech", Context.MODE_PRIVATE)
            column.addView(SwitchCompat(context).apply {
                text = "듣기 버튼 항상 표시"; setTextColor(colors.foreground); minHeight = dp(48)
                isChecked = prefs.getBoolean("alwaysShow", false)
                setOnCheckedChangeListener { _, value -> prefs.edit().putBoolean("alwaysShow", value).apply(); speechVisibility() }
            })
            column.addView(label("듣기를 시작하면 조작 버튼이 표시됩니다. 일시정지 후에도 유지되며, 듣기 종료를 누르면 숨겨집니다.", 13f))
            return
        }
        if (tab == 2) {
            column.addView(SwitchCompat(context).apply {
                text = "번역 모드"; setTextColor(colors.foreground); minHeight = dp(48)
                isChecked = translationEnabled
                setOnCheckedChangeListener { _, _ -> dialog.dismiss(); translationSettings?.invoke() }
            })
            column.addView(label("모드를 켠 뒤 본문을 길게 눌러 단어나 문장을 선택하세요. 번역은 하단에 표시됩니다.", 14f))
            return
        }
        column.addView(label("글자 크기"))
        val font = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        font.addView(button("A−") { update(current().copy(fontScale = (current().fontScale - .1).coerceAtLeast(.5))) }, LinearLayout.LayoutParams(0, -2, 1f))
        font.addView(label("${(p.fontScale * 100).toInt()}%", 16f).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
        font.addView(button("A+") { update(current().copy(fontScale = (current().fontScale + .1).coerceAtMost(3.0))) }, LinearLayout.LayoutParams(0, -2, 1f))
        column.addView(font)
        fun choices(title: String, labels: List<String>, selected: Int, enabled: Boolean = true, action: (Int) -> Unit) {
            column.addView(label(title))
            val row = LinearLayout(context)
            labels.forEachIndexed { i, text ->
                row.addView(button(if (i == selected) "✓ $text" else text, i == selected) { action(i) }.apply { isEnabled = enabled; alpha = if (enabled) 1f else .4f }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = dp(4) })
            }
            column.addView(row)
        }
        choices("배경", listOf("밝게", "종이색", "어둡게"), listOf("light", "sepia", "dark").indexOf(p.theme)) {
            update(current().copy(theme = listOf("light", "sepia", "dark")[it]))
        }
        column.addView(label("읽기 방식", 17f))
        choices("넘김 방식", listOf("페이지 넘김", "연속 스크롤"), if (p.scroll) 1 else 0) {
            update(current().copy(scroll = it == 1))
        }
        choices("페이지 배치", if (canShowSpread()) listOf("자동", "한 페이지", "두 페이지") else listOf("자동", "한 페이지"), if (!canShowSpread() && p.columnCount == 2L) -1 else p.columnCount.toInt(), enabled = !p.scroll) {
            update(current().copy(columnCount = it.toLong()))
        }
        if (!p.scroll) {
            choices("페이지 전환 효과", listOf("바로 넘기기", "책장 넘기기"), if (p.pageTurnStyle == "curl") 1 else 0) {
                update(current().copy(pageTurnStyle = if (it == 1) "curl" else "instant"))
            }
        } else {
            column.addView(label("연속 스크롤에서는 페이지 배치와 전환 효과를 사용하지 않습니다. 선택한 설정은 유지됩니다.", 12f)
                .apply { setTextColor(colors.secondary) })
        }
        column.addView(label(if (!canShowSpread() && p.columnCount == 2L) "현재 한 페이지로 표시 중 · 화면을 넓히면 두 페이지로 돌아갑니다." else "두 페이지 선택은 넓은 화면에서 표시됩니다.", 12f).apply { setTextColor(colors.secondary) })
        column.addView(button(if (detailsExpanded) "글꼴·문단 설정  ▴" else "글꼴·문단 설정  ▾") { detailsExpanded = !detailsExpanded; render() })
        if (!detailsExpanded) return
        column.addView(label("본문 간격", 17f))
        val lines = listOf(null, 1.2, 1.5, 1.8)
        choices("줄간격", listOf("기본", "촘촘", "보통", "넉넉"), lines.indexOf(p.lineHeight)) {
            update(current().copy(lineHeight = lines[it]))
        }
        val paragraphs = listOf(null, 0.0, 0.5, 1.0)
        choices("문단 간격", listOf("기본", "없음", "보통", "넓게"), paragraphs.indexOf(p.paragraphSpacing)) {
            update(current().copy(paragraphSpacing = paragraphs[it]))
        }
        val margins = listOf(null, 0.5, 1.0, 1.5)
        choices("페이지 여백", listOf("기본", "좁게", "보통", "넓게"), margins.indexOf(p.pageMargins)) {
            update(current().copy(pageMargins = margins[it]))
        }
        column.addView(label("기본은 책의 원래 설정입니다. 줄·문단 간격을 지정하면 출판사 문단 스타일 일부가 바뀔 수 있습니다. 두 페이지에서는 좌우 여백과 중앙 간격이 함께 조절됩니다.", 12f).apply { setTextColor(colors.secondary) })
        column.addView(label("글꼴"))
        val selectedFont = (p.fontId ?: "default").takeIf { it in fontIds } ?: "default"
        var lastGroup = ""
        fontIds.forEachIndexed { index, id ->
            val group = if (id.startsWith("personal_")) "내 글꼴" else if (id.startsWith("remote_")) "다운로드 글꼴" else "기본 글꼴"
            if (group != lastGroup) { column.addView(label(group)); lastGroup = group }
            val selected = id == selectedFont
            column.addView(button(if (selected) "✓ ${fontLabels[index]}" else fontLabels[index], selected) {
                update(current().copy(fontId = id))
            }.apply { previewFont(id)?.let { typeface = it } }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(4) })
        }
        column.addView(button("＋ 내 글꼴 추가·관리  ›") { dialog.dismiss(); manageFonts?.invoke() })
    }
}
