package com.koofy.reader.bridge

import android.graphics.BitmapFactory
import android.speech.tts.TextToSpeech
import android.view.View
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.*
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils

/** Ephemeral selected-text translation; never writes reading or speech checkpoints. */
internal class ReaderTranslation(
    private val activity: AppCompatActivity,
    private val sample: suspend (String) -> String?,
    private val pauseBook: () -> Unit,
    private val selectionChanged: (Boolean) -> Unit,
    private val onClose: () -> Unit,
) {
    val view = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; visibility = View.GONE }
    var enabled = false; private set
    private var foreground = true
    private var disposed = false
    private var generation = 0
    private var modelGeneration = 0
    private var poll: Job? = null
    private var preparationTimeout: Job? = null
    private var translator: Translator? = null
    private var ready = false
    private var downloading = false
    private var source = ""
    private var result = ""
    private var identity = ""
    private var pending = ""
    private var pendingAt = 0L
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var voiceGeneration = 0
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val focus = AudioManager.OnAudioFocusChangeListener { if (it <= 0) stopVoice() }
    private val noisy = object : BroadcastReceiver() { override fun onReceive(context: Context?, intent: Intent?) { stopVoice() } }
    private val script = activity.assets.open("reader_selection.js").bufferedReader().use { it.readText() }
    private val text = TextView(activity).apply { textSize = 15f; setPadding(dp(12), dp(4), dp(12), dp(4)) }
    private val download = button("번역 준비 · Wi-Fi") { prepare() }
    private val originalVoice = button("원문 듣기") { speak(source, "en") }
    private val translatedVoice = button("번역 듣기") { speak(result, "ko") }
    private val badge = ImageView(activity).apply { adjustViewBounds = true; contentDescription = "powered by Google Translate" }
    private fun dp(n: Int) = (n * activity.resources.displayMetrics.density).toInt()
    private fun button(label: String, action: () -> Unit) = Button(activity).apply {
        this.text = label; textSize = 12f; isAllCaps = false; minWidth = 0; minimumWidth = 0
        setPadding(dp(4), 0, dp(4), 0); setOnClickListener { action() }
    }
    init {
        ContextCompat.registerReceiver(activity, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED)
        val header = LinearLayout(activity)
        header.addView(TextView(activity).apply { text = "영어 → 한국어 · 번역"; textSize = 14f; setPadding(dp(12), 0, 0, 0) }, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(button("끄기") { onClose() }, LinearLayout.LayoutParams(dp(64), dp(44)))
        view.addView(header)
        view.addView(ScrollView(activity).apply { addView(text) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(activity)
        actions.addView(originalVoice, LinearLayout.LayoutParams(0, dp(44), 1f))
        actions.addView(translatedVoice, LinearLayout.LayoutParams(0, dp(44), 1f))
        actions.addView(download, LinearLayout.LayoutParams(0, dp(44), 1f))
        view.addView(actions)
        view.addView(badge, LinearLayout.LayoutParams(dp(140), dp(22)).apply { gravity = android.view.Gravity.END; rightMargin = dp(12) })
        badge.setOnClickListener { AlertDialog.Builder(activity).setTitle("Google Translate 자동 번역")
            .setMessage("선택한 본문은 기기 안에서 번역합니다. 번역은 학습 참고용이며 정확성·신뢰성·특정 목적 적합성을 보장하지 않습니다. Google은 번역에 관한 명시적·묵시적 보증을 제공하지 않습니다. 처음에는 Wi-Fi로 언어 데이터를 내려받아야 합니다. SDK는 성능·사용 통계를 Google에 전송할 수 있습니다.")
            .setPositiveButton("확인", null).show() }
    }
    fun palette(p: ReaderPalette) {
        view.setBackgroundColor(p.background); text.setTextColor(p.foreground)
        fun tint(v: View) { if (v is TextView) v.setTextColor(p.foreground); if (v is android.view.ViewGroup) for (i in 0 until v.childCount) tint(v.getChildAt(i)) }
        tint(view)
        val dark = ColorUtils.calculateLuminance(p.background) < .3
        activity.assets.open(if (dark) "translate-white-regular.png" else "translate-color-regular.png").use { badge.setImageBitmap(BitmapFactory.decodeStream(it)) }
    }
    fun enable() {
        enabled = true; view.visibility = View.VISIBLE
        translator = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.ENGLISH).setTargetLanguage(TranslateLanguage.KOREAN).build())
        ready = false; text.text = "단어를 길게 누르고 선택 범위를 조절하세요. 번역 준비는 Wi-Fi에서 진행합니다."
        val token = ++modelGeneration
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java).addOnSuccessListener { models ->
            if (enabled && token == modelGeneration) { ready = models.any { it.language == TranslateLanguage.KOREAN }; controls() }
        }
        controls(); resume()
    }
    private fun controls() {
        originalVoice.isEnabled = source.isNotEmpty(); translatedVoice.isEnabled = result.isNotEmpty()
        download.text = if (downloading) "준비 중…" else if (ready) "다시 번역" else "번역 준비 · Wi-Fi"
        download.isEnabled = !downloading
    }
    fun prepare() {
        val engine = translator ?: return
        if (ready) { identity = ""; return }
        downloading = true; controls(); text.text = "Wi-Fi에서 번역 데이터를 준비하고 있습니다. 끄기를 눌러 독서를 계속할 수 있습니다."
        val token = ++modelGeneration
        preparationTimeout?.cancel()
        preparationTimeout = activity.lifecycleScope.launch {
            delay(180_000)
            if (enabled && downloading && token == modelGeneration) {
                modelGeneration++; downloading = false
                text.text = "번역 준비가 지연되고 있습니다. Wi-Fi 연결을 확인하고 다시 시도하세요."
                controls()
            }
        }
        engine.downloadModelIfNeeded(DownloadConditions.Builder().requireWifi().build()).addOnCompleteListener { task ->
            if (!enabled || disposed || token != modelGeneration) return@addOnCompleteListener
            preparationTimeout?.cancel()
            downloading = false; ready = task.isSuccessful; identity = ""
            text.text = if (ready) "준비됐습니다. 단어나 문장을 길게 눌러 선택하세요." else "번역 데이터를 준비하지 못했습니다. Wi-Fi 연결을 확인하고 다시 시도하세요."
            controls()
        }
    }
    fun resume() {
        foreground = true
        if (!enabled || disposed || poll?.isActive == true) return
        poll = activity.lifecycleScope.launch {
            while (isActive && enabled && foreground) {
                try {
                    val raw = sample(script)
                    if (raw != null) {
                        val value = JSONTokener(raw).nextValue()
                        val snapshot = JSONObject(value as? String ?: raw)
                        accept(snapshot)
                    }
                } catch (error: CancellationException) { throw error } catch (_: Exception) { /* A navigator can be remounting. Retry without logging book text. */ }
                delay(200)
            }
        }
    }
    internal fun accept(snapshot: JSONObject) {
        if (!enabled || !foreground) return
        val selected = snapshot.optString("text").trim()
        selectionChanged(snapshot.optBoolean("active"))
        val key = snapshot.optString("resource") + "\n" + selected
        if (key != pending) {
            pending = key; identity = ""; pendingAt = android.os.SystemClock.uptimeMillis(); generation++; stopVoice()
            source = selected; result = ""; controls()
            if (selected.isNotEmpty()) { pauseBook(); text.text = if (selected.length > 2000) "한 번에 2,000자까지 선택해 주세요." else "$selected\n\n선택을 마치면 번역합니다." }
            else text.text = "단어나 문장을 길게 눌러 선택하세요."
        }
        if (selected.isEmpty() || selected.length > 2000 || snapshot.optBoolean("busy") || key == identity || android.os.SystemClock.uptimeMillis() - pendingAt < 500) return
        if (!ready) { if (!downloading) text.text = "$selected\n\n번역 준비를 눌러 언어 데이터를 내려받으세요."; return }
        identity = key; val token = ++generation
        text.text = "$selected\n\n번역 중…"
        translator?.translate(selected)?.addOnSuccessListener { translated ->
            if (enabled && foreground && token == generation) { result = translated; text.text = "$selected\n\n$translated"; controls() }
        }?.addOnFailureListener {
            if (enabled && foreground && token == generation) { text.text = "$selected\n\n번역하지 못했습니다. 다시 번역을 눌러 주세요."; controls() }
        }
    }
    private fun speak(value: String, language: String) {
        if (value.isBlank() || value.length > TextToSpeech.getMaxSpeechInputLength() || !foreground) return
        pauseBook()
        if (tts == null) {
            tts = TextToSpeech(activity.applicationContext) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                    override fun onStart(id: String?) = Unit
                    override fun onDone(id: String?) = release(id)
                    @Deprecated("Required legacy callback") override fun onError(id: String?) = release(id)
                    private fun release(id: String?) { activity.runOnUiThread {
                        if (id == "selection-$voiceGeneration") stopVoice()
                    } }
                })
                if (enabled && foreground) Toast.makeText(activity, if (ttsReady) "음성이 준비됐습니다. 듣기를 다시 눌러 주세요." else "기기 음성 엔진을 사용할 수 없습니다.", Toast.LENGTH_SHORT).show()
            }
            return
        }
        val engine = tts ?: return
        if (!ttsReady) return
        val voice = engine.voices?.filter { it.locale.language == language && !it.isNetworkConnectionRequired && !(it.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) ?: false) }?.maxByOrNull { it.quality }
        if (voice == null) { Toast.makeText(activity, "기기 TTS 설정에서 ${if (language == "en") "영어" else "한국어"} 오프라인 음성을 설치해 주세요.", Toast.LENGTH_LONG).show(); return }
        @Suppress("DEPRECATION")
        val granted = audio.requestAudioFocus(focus, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return
        engine.voice = voice; engine.setSpeechRate(.9f)
        voiceGeneration++
        engine.speak(value, TextToSpeech.QUEUE_FLUSH, null, "selection-$voiceGeneration")
    }
    @Suppress("DEPRECATION")
    fun stopVoice() { voiceGeneration++; tts?.stop(); audio.abandonAudioFocus(focus) }
    fun suspend() { foreground = false; generation++; identity = ""; poll?.cancel(); poll = null; stopVoice() }
    fun disable() { preparationTimeout?.cancel(); enabled = false; suspend(); modelGeneration++; downloading = false; ready = false; translator?.close(); translator = null; source = ""; result = ""; pending = ""; selectionChanged(false); view.visibility = View.GONE }
    fun close() { disable(); disposed = true; activity.unregisterReceiver(noisy); tts?.shutdown(); tts = null }
}
