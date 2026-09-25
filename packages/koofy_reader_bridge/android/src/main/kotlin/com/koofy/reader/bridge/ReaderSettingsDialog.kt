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
import androidx.appcompat.app.AlertDialog

/** Presentation only. All changes still pass through the host's anchor restoration. */
internal class ReaderSettingsDialog(
    private val context: Context,
    private val current: () -> ReaderPreferences,
    private val change: (ReaderPreferences) -> Unit,
    private val fontIds: List<String> = ReaderFonts.ids,
    private val fontLabels: List<String> = ReaderFonts.labels,
) {
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
            setTextColor(colors.foreground)
            isSelected = selected
            if (selected) setTypeface(typeface, Typeface.BOLD)
            background = GradientDrawable().apply {
                setColor(if (selected) colors.panel else colors.background)
                cornerRadius = dp(10).toFloat()
            }
            setOnClickListener { action() }
        }
        fun update(next: ReaderPreferences) { change(next); render() }
        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        heading.addView(label("독서 설정", 20f), LinearLayout.LayoutParams(0, -2, 1f))
        heading.addView(button("완료") { dialog.dismiss() }, LinearLayout.LayoutParams(dp(64), dp(48)))
        column.addView(heading)
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
                row.addView(button(if (i == selected) "✓ $text" else text, i == selected) { action(i) }.apply { isEnabled = enabled; alpha = if (enabled) 1f else .4f }, LinearLayout.LayoutParams(0, -2, 1f))
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
        choices("페이지 배치", listOf("자동", "한 페이지", "두 페이지"), p.columnCount.toInt(), enabled = !p.scroll) {
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
        column.addView(label("두 페이지는 화면 너비가 충분할 때 적용됩니다.", 12f).apply { setTextColor(colors.secondary) })
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
        fontIds.forEachIndexed { index, id ->
            val selected = id == selectedFont
            column.addView(button(if (selected) "✓ ${fontLabels[index]}" else fontLabels[index], selected) {
                update(current().copy(fontId = id))
            }, LinearLayout.LayoutParams(-1, -2))
        }
    }
}
