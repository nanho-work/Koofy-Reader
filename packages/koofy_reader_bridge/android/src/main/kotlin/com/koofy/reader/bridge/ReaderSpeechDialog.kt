package com.koofy.reader.bridge

import android.content.Context
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog

@OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
internal class ReaderSpeechDialog(private val context: Context, private val speech: ReaderSpeech, private val palette: ReaderPalette) {
    fun show() {
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 16, 24, 24); setBackgroundColor(palette.background) }
        fun label(text: String) { column.addView(TextView(context).apply { this.text = text; setTextColor(palette.foreground); setPadding(0, 16, 0, 16) }) }
        fun action(text: String, block: () -> Unit) { column.addView(Button(context).apply { this.text = text; setTextColor(palette.foreground); setOnClickListener { block() } }) }
        val dialog = AlertDialog.Builder(context).setTitle("듣기 설정").setView(ScrollView(context).apply { addView(column) }).setPositiveButton("완료", null).create()
        label("기기에 설치된 한국어 음성으로 읽습니다. 앱·독서 화면을 벗어나면 멈추며 자동으로 재생하지 않습니다.")
        if (speech.voices.isEmpty()) label("설치된 로컬 한국어 음성이 없습니다.")
        speech.voices.forEachIndexed { index, voice ->
            action("${if (speech.voiceId == voice.id.value) "✓ " else ""}한국어 음성 ${index + 1} · ${voice.id.value}") {
                speech.selectVoice(voice.id.value); dialog.dismiss(); show()
            }
        }
        action("선택한 음성 미리 듣기") { speech.preview() }
        action("기기 음성 다운로드") { dialog.dismiss(); speech.installVoice() }
        label("읽기 속도 · ${speech.speed}배")
        val speeds = doubleArrayOf(.75, 1.0, 1.25, 1.5, 2.0)
        action("속도 변경") { AlertDialog.Builder(context).setItems(speeds.map { "${it}배" }.toTypedArray()) { _, index -> speech.setSpeed(speeds[index]); dialog.dismiss(); show() }.show() }
        action(if (speech.follow) "✓ 음성을 따라 페이지 이동" else "음성을 따라 페이지 이동") { speech.setFollow(!speech.follow); dialog.dismiss(); show() }
        action("취침 타이머 · ${if (speech.timerMinutes == 0) "사용 안 함" else "${speech.timerMinutes}분"}") {
            val times = intArrayOf(0, 15, 30, 60)
            AlertDialog.Builder(context).setItems(arrayOf("사용 안 함", "15분", "30분", "60분")) { _, index -> speech.setTimer(times[index]); dialog.dismiss(); show() }.show()
        }
        if (speech.hasSaved) action("저장된 듣던 위치부터 재생") { dialog.dismiss(); speech.start(savedPosition = true) }
        dialog.setOnDismissListener { speech.stopPreview() }
        dialog.show()
        dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background))
    }
}
