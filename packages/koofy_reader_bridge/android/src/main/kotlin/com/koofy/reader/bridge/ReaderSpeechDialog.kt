package com.koofy.reader.bridge

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.widget.SwitchCompat

@OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
internal class ReaderSpeechDialog(private val context: Context, private val speech: ReaderSpeech, private val palette: ReaderPalette) {
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
    private fun shape(selected: Boolean = false) = GradientDrawable().apply {
        setColor(if (selected) palette.accent else palette.panel)
        cornerRadius = dp(12).toFloat()
    }
    private fun text(value: String, size: Float = 14f, secondary: Boolean = false) = TextView(context).apply {
        this.text = value; textSize = size
        setTextColor(if (secondary) palette.secondary else palette.foreground)
    }
    fun show() {
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(16))
            setBackgroundColor(palette.background)
        }
        val scroll = ScrollView(context).apply { addView(column) }
        val title = text("듣기 설정", 20f).apply { setPadding(dp(20), dp(20), dp(20), dp(8)) }
        val dialog = AlertDialog.Builder(context).setCustomTitle(title)
            .setView(scroll).setPositiveButton("완료", null).create()
        fun heading(value: String) {
            column.addView(text(value, 13f, true).apply {
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(20), 0, dp(8))
            })
        }
        fun action(value: String, block: () -> Unit): Button {
            val button = Button(context).apply {
                this.text = value; textSize = 15f; isAllCaps = false
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                minHeight = dp(48); minimumHeight = dp(48)
                setPadding(dp(14), dp(10), dp(14), dp(10))
                setTextColor(palette.foreground); background = shape()
                stateListAnimator = null
                setOnClickListener { block() }
            }
            column.addView(button, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
            return button
        }
        fun choices(labels: List<String>, selected: Int, change: (Int) -> Unit) {
            val row = LinearLayout(context)
            val buttons = mutableListOf<Button>()
            labels.forEachIndexed { index, label ->
                val button = Button(context).apply {
                    this.text = label; textSize = 14f; isAllCaps = false
                    minWidth = dp(56); minimumWidth = dp(56)
                    minHeight = dp(48); minimumHeight = dp(48)
                    setPadding(dp(10), dp(10), dp(10), dp(10))
                    stateListAnimator = null
                    isSelected = index == selected
                    background = shape(isSelected)
                    setTextColor(if (isSelected) palette.background else palette.foreground)
                    contentDescription = "$label${if (isSelected) ", 선택됨" else ""}"
                    setOnClickListener {
                        change(index)
                        buttons.forEachIndexed { i, child ->
                            child.isSelected = i == index; child.background = shape(child.isSelected)
                            child.setTextColor(if (child.isSelected) palette.background else palette.foreground)
                            child.contentDescription = "${labels[i]}${if (child.isSelected) ", 선택됨" else ""}"
                        }
                    }
                }
                buttons.add(button)
                row.addView(button, LinearLayout.LayoutParams(-2, -2).apply { marginEnd = dp(6) })
            }
            column.addView(HorizontalScrollView(context).apply {
                isHorizontalScrollBarEnabled = false; addView(row)
            }, LinearLayout.LayoutParams(-1, -2))
        }
        column.addView(text("기기에 설치된 한국어 음성으로 책을 읽습니다.", secondary = true))
        heading("목소리")
        val voices = speech.voices
        fun selectedName(): String {
            val index = voices.indexOfFirst { it.id.value == speech.voiceId }
            return if (index < 0) "로컬 음성을 선택해 주세요" else "한국어 음성 ${index + 1}"
        }
        lateinit var voiceButton: Button
        voiceButton = action("${selectedName()}  ›") {
            if (voices.isEmpty()) return@action
            speech.stopPreview()
            val labels = voices.mapIndexed { i, voice -> "한국어 음성 ${i + 1}\n${voice.id.value}" }
            val adapter = object : ArrayAdapter<String>(context, android.R.layout.simple_list_item_single_choice, labels) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                    (super.getView(position, convertView, parent) as TextView).apply {
                        setTextColor(palette.foreground); setBackgroundColor(palette.background)
                    }
            }
            val picker = AlertDialog.Builder(context).setCustomTitle(text("한국어 목소리 선택", 20f).apply {
                setPadding(dp(20), dp(20), dp(20), dp(8))
            }).setSingleChoiceItems(adapter,
                    voices.indexOfFirst { it.id.value == speech.voiceId }) { picker, index ->
                    speech.selectVoice(voices[index].id.value)
                    voiceButton.text = "${selectedName()}  ›"
                    picker.dismiss()
                }.setNegativeButton("닫기", null).create()
            picker.show()
            picker.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background))
            picker.getButton(AlertDialog.BUTTON_NEGATIVE).setTextColor(palette.accent)
        }
        voiceButton.isEnabled = voices.isNotEmpty()
        action("▷  선택한 음성 미리 듣기") { speech.preview() }.isEnabled = voices.isNotEmpty()
        action("기기 음성 다운로드  ›") { dialog.dismiss(); speech.installVoice() }
        if (voices.isEmpty()) column.addView(text("설치된 로컬 한국어 음성이 없습니다. 음성을 다운로드한 뒤 독서 화면을 다시 열어 주세요.", secondary = true))
        heading("읽기 속도")
        val speeds = listOf(.75, 1.0, 1.25, 1.5, 2.0)
        choices(listOf("0.75배", "1배", "1.25배", "1.5배", "2배"), speeds.indexOf(speech.speed)) { speech.setSpeed(speeds[it]) }
        heading("취침 타이머")
        val times = listOf(0, 15, 30, 60)
        choices(listOf("꺼짐", "15분", "30분", "60분"), times.indexOf(speech.timerMinutes)) { speech.setTimer(times[it]) }
        heading("본문 표시")
        column.addView(SwitchCompat(context).apply {
            text = "음성을 따라 페이지 이동"; textSize = 15f
            setTextColor(palette.foreground); minHeight = dp(48)
            thumbTintList = ColorStateList.valueOf(palette.accent)
            isChecked = speech.follow
            setOnCheckedChangeListener { _, checked -> speech.setFollow(checked) }
        }, LinearLayout.LayoutParams(-1, -2))
        if (speech.hasSaved) {
            heading("이어 듣기")
            action("저장된 듣던 위치부터 재생  ›") { dialog.dismiss(); speech.start(savedPosition = true) }
        }
        column.addView(text("앱·독서 화면을 벗어나면 멈춥니다. 돌아와도 자동으로 재생하지 않습니다.", 13f, true).apply {
            setPadding(0, dp(16), 0, 0)
        })
        dialog.setOnDismissListener { speech.stopPreview() }
        dialog.show()
        dialog.window?.apply {
            setBackgroundDrawable(GradientDrawable().apply {
                setColor(palette.background); cornerRadius = dp(24).toFloat()
            })
            setGravity(Gravity.BOTTOM)
            setLayout(minOf(context.resources.displayMetrics.widthPixels - dp(24), dp(480)), ViewGroup.LayoutParams.WRAP_CONTENT)
        }
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(palette.accent)
    }
}
