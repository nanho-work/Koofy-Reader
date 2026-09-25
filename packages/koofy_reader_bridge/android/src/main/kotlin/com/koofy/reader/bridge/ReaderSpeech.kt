@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.content.BroadcastReceiver
import android.content.SharedPreferences
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import org.readium.navigator.media.tts.*
import org.readium.navigator.media.tts.android.*
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.getOrElse

internal typealias ReaderSpeechEngine = TtsEngine<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>

/** Foreground-only owner; the visual reader's checkpoint is deliberately not the audio checkpoint. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class ReaderSpeech(
    private val host: AppCompatActivity,
    private val publication: Publication,
    private val request: ReaderLaunchRequest,
    private val visible: suspend () -> Locator?,
    private val available: () -> Boolean,
    private val changed: () -> Unit,
    private val located: (Locator?) -> Unit,
    private val prefs: SharedPreferences = host.getSharedPreferences("reader_speech", Context.MODE_PRIVATE),
    private val createEngine: suspend () -> ReaderSpeechEngine? = { OfflineSpeechEngine.create(host) },
) {
    private val audio = host.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var engine: ReaderSpeechEngine? = null
    private val prepareLock = Mutex()
    private var navigator: AndroidTtsNavigator? = null
    private var job: Job? = null
    private var observer: Job? = null
    private var timer: Job? = null
    private var utteranceOrdinal = -1
    private var utteranceMarker: String? = null
    private var utteranceStep = 1
    private var seeking = true
    private var skipRemaining = 0
    private var serial = 0
    private var closed = false
    private var active = false
    var busy = false; private set
    var playing = false; private set
    var used = false; private set
    var current: Locator? = null; private set
    var fromVisible = true; private set
    var voiceId: String? = prefs.getString("voice", null); private set
    var speed: Double = prefs.getFloat("speed", 1f).toDouble().let { if (it.isFinite()) it.coerceIn(.5, 2.0) else 1.0 }; private set
    var follow: Boolean = prefs.getBoolean("follow", true); private set
    var timerMinutes = 0; private set
    val voices get() = engine?.voices.orEmpty().filter { it.language.locale.language == "ko" }.sortedBy { it.id.value }
    val hasSaved get() = saved() != null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { if (it < 0) pause() }
    private val focusRequest by lazy {
        if (Build.VERSION.SDK_INT >= 26) AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener(focusListener).setWillPauseWhenDucked(true).build() else null
    }
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { pause() }
    }
    init {
        ContextCompat.registerReceiver(host, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    fun foreground(value: Boolean) { active = value; if (!value) pause() }
    fun toggle() {
        if (playing || busy) { pause(); return }
        start()
    }
    fun start(savedPosition: Boolean = false) {
        if (closed || !active || !available()) return
        busy = true; used = true; changed()
        val generation = ++serial
        job = host.lifecycleScope.launch {
            try {
                withTimeout(15_000) {
                    val reposition = savedPosition || fromVisible || navigator == null
                    val target = if (savedPosition) saved() else if (fromVisible) visible() else current
                    val start = if (reposition) target?.let { speechStart(publication, it) } else null
                    if (reposition) prepareLock.withLock {
                        observer?.cancel(); observer = null
                        navigator?.close(); navigator = null
                        engine?.close(); engine = null
                    }
                    val nav = prepare(start?.locator) ?: run {
                        message("기기의 음성 엔진을 사용할 수 없습니다. 음성 설치 상태를 확인해 주세요.")
                        return@withTimeout
                    }
                    if (generation != serial || !active || closed) return@withTimeout
                    val voice = voices.firstOrNull { it.id.value == voiceId }
                    if (voice == null) {
                        message("로컬 한국어 음성을 선택해 주세요. 듣기 설정에서 음성을 확인할 수 있습니다.")
                        return@withTimeout
                    }
                    if (!requestFocus()) { message("다른 소리 재생이 끝난 뒤 다시 눌러 주세요."); return@withTimeout }
                    nav.submitPreferences(preferences())
                    if (generation != serial || !active || closed) { releaseFocus(); return@withTimeout }
                    seeking = true
                    skipRemaining = start?.skip ?: 0
                    utteranceOrdinal = if (reposition) skipRemaining - 1 else utteranceOrdinal - 1
                    utteranceMarker = null
                    utteranceStep = 1
                    // A new navigator already starts at the requested locator. Calling
                    // go() followed by play() races two Readium jobs and consumes a
                    // skipped sentence twice. In-memory resume keeps its paused cursor.
                    fromVisible = false
                    playing = true
                    nav.play()
                }
            } catch (_: kotlinx.coroutines.CancellationException) {
                // A stop while initialization is pending must never become delayed playback.
                if (generation == serial) message("음성 준비 시간이 초과되었습니다. 다시 시도해 주세요.")
            } catch (_: Exception) { message("음성을 준비하지 못했습니다. 기기의 음성 설정을 확인해 주세요.") }
            finally { if (generation == serial) { if (!playing) busy = false; changed() } }
        }
    }
    suspend fun prepare(initial: Locator? = null): AndroidTtsNavigator? = prepareLock.withLock {
        if (closed) return@withLock null
        navigator?.let { return@withLock it }
        val offline = engine ?: createEngine()?.also { engine = it } ?: return@withLock null
        if (closed) { offline.close(); return@withLock null }
        (offline as? OfflineSpeechEngine)?.onPreviewFinished = { if (!playing) releaseFocus() }
        if (voiceId == null) {
            voiceId = voices.firstOrNull()?.id?.value
            voiceId?.let { prefs.edit().putString("voice", it).apply() }
        }
        val delegate = AndroidTtsEngineProvider(host)
        val provider = object : TtsEngineProvider<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsPreferencesEditor, AndroidTtsEngine.Error, AndroidTtsEngine.Voice> by delegate {
            override suspend fun createEngine(publication: Publication, initialPreferences: AndroidTtsPreferences): Try<TtsEngine<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>, org.readium.r2.shared.util.Error> {
                offline.submitPreferences(initialPreferences)
                val gated = object : ReaderSpeechEngine by offline {
                    private var callback: TtsEngine.Listener<AndroidTtsEngine.Error>? = null
                    override fun setListener(listener: TtsEngine.Listener<AndroidTtsEngine.Error>?) { callback = listener; offline.setListener(listener) }
                    override fun speak(requestId: TtsEngine.RequestId, text: String, language: Language?) {
                        if (!playing || !active || closed) callback?.onInterrupted(requestId)
                        else if (skipRemaining > 0) {
                            skipRemaining--
                            host.lifecycleScope.launch {
                                kotlinx.coroutines.yield()
                                if (playing && active && !closed) callback?.onDone(requestId) else callback?.onInterrupted(requestId)
                            }
                        } else {
                            seeking = false; busy = false; changed()
                            host.lifecycleScope.launch {
                                kotlinx.coroutines.yield()
                                if (playing && active && !closed) navigator?.location?.value?.utteranceLocator?.let(::recordUtterance)
                            }
                            offline.speak(requestId, text, language)
                        }
                    }
                }
                return Try.success(gated)
            }
        }
        val factory = TtsNavigatorFactory(host.application, publication, provider, tokenizerFactory = {
            org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer(
                org.readium.r2.shared.util.tokenizer.TextUnit.Sentence, Language("ko"))
        }) ?: return@withLock null
        val nav = factory.createNavigator(object : TtsNavigator.Listener {
            override fun onStopRequested() { pause() }
        }, initialLocator = initial ?: visible()?.let { speechStart(publication, it).locator }, initialPreferences = preferences()).getOrElse {
            message("이 책의 읽을 본문을 준비하지 못했습니다."); return@withLock null
        }
        if (closed) { nav.close(); return@withLock null }
        // 3.1.2 ignores Media3's handleAudioFocus=false and keeps playing during a
        // transient focus loss. Disable focus ONLY on its control adapter using its
        // no-focus usage. Actual TextToSpeech output stays USAGE_MEDIA/SPEECH.
        // This reader owns focus so every loss pauses without automatic resumption.
        nav.asMedia3Player().setAudioAttributes(androidx.media3.common.AudioAttributes.Builder()
            .setUsage(androidx.media3.common.C.USAGE_VOICE_COMMUNICATION_SIGNALLING).build(), false)
        navigator = nav
        observer = host.lifecycleScope.launch {
            nav.playback.collect { state ->
                when (state.state) {
                    TtsNavigator.State.Ended -> {
                        if (playing) message("책 읽기가 끝났습니다.")
                        pause()
                    }
                    is TtsNavigator.State.Failure -> { pause(); message("음성을 재생하지 못했습니다. 오프라인 음성 설치 상태를 확인해 주세요.") }
                    else -> {
                        if (playing && !busy && !state.playWhenReady) pause()
                    }
                }
            }
        }
        nav
    }
    private fun recordUtterance(location: Locator) {
        val marker = location.href.toString() + ":" + location.locations.otherLocations["cssSelector"]
        utteranceOrdinal = when {
            utteranceMarker == null -> utteranceOrdinal + 1
            utteranceMarker != marker -> if (utteranceStep < 0) -1 else 0
            utteranceOrdinal < 0 -> -1
            else -> (utteranceOrdinal + utteranceStep).coerceAtLeast(0)
        }
        utteranceStep = 1
        utteranceMarker = marker
        current = if (utteranceOrdinal < 0) location else location.copy(locations = location.locations.copy(
            otherLocations = location.locations.otherLocations + ("koofySpeechOrdinal" to utteranceOrdinal)))
        save(); located(current)
    }
    private fun preferences() = AndroidTtsPreferences(language = Language("ko"), speed = speed,
        voices = voiceId?.let { mapOf(Language("ko") to AndroidTtsEngine.Voice.Id(it)) }.orEmpty())
    fun preview() {
        pause()
        if (!active || closed || !requestFocus()) return
        val id = voiceId
        if (id == null || (engine as? OfflineSpeechEngine)?.preview(id, speed) != true) { releaseFocus(); message("설치된 로컬 음성을 먼저 선택해 주세요.") }
    }
    fun stopPreview() { if (!playing) { engine?.stop(); releaseFocus() } }
    fun pause() {
        serial++; job?.cancel(); job = null
        seeking = true; busy = false; playing = false
        navigator?.pause()
        engine?.stop()
        save(); releaseFocus(); changed()
    }
    fun userNavigation() { pause(); fromVisible = true; located(null) }
    fun skip(forward: Boolean) {
        val nav = navigator ?: return
        if (closed || !active || !available() || !playing || busy) return
        fromVisible = false
        utteranceStep = if (forward) 1 else -1
        if (forward) nav.skipToNextUtterance() else nav.skipToPreviousUtterance()
        // The engine callback records the resolved sentence after Readium advances.
    }
    fun selectVoice(id: String) { pause(); voiceId = id; prefs.edit().putString("voice", id).apply(); navigator?.submitPreferences(preferences()) }
    fun setSpeed(value: Double) { pause(); speed = value.coerceIn(.5, 2.0); prefs.edit().putFloat("speed", speed.toFloat()).apply(); navigator?.submitPreferences(preferences()) }
    fun setFollow(value: Boolean) { follow = value; prefs.edit().putBoolean("follow", value).apply() }
    fun setTimer(minutes: Int) {
        timer?.cancel(); timerMinutes = minutes
        if (minutes > 0) timer = host.lifecycleScope.launch { delay(minutes * 60_000L); timerMinutes = 0; pause(); message("설정한 시간이 되어 듣기를 멈췄습니다.") }
    }
    private fun save() {
        val position = current ?: return
        prefs.edit().putString("position.${request.publicationId}", JSONObject().put("revision", request.contentRevision)
            .put("locator", position.toJSON()).toString()).apply()
    }
    private fun saved(): Locator? = runCatching {
        val json = JSONObject(prefs.getString("position.${request.publicationId}", null) ?: return null)
        if (json.optString("revision") != request.contentRevision) return null
        Locator.fromJSON(json.getJSONObject("locator"))?.takeIf { publication.linkWithHref(it.href) != null }
    }.getOrNull()
    @Suppress("DEPRECATION") private fun requestFocus(): Boolean =
        (if (Build.VERSION.SDK_INT >= 26) audio.requestAudioFocus(focusRequest!!) else
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    @Suppress("DEPRECATION") private fun releaseFocus() {
        if (Build.VERSION.SDK_INT >= 26) audio.abandonAudioFocusRequest(focusRequest!!) else audio.abandonAudioFocus(focusListener)
    }
    fun close() {
        if (closed) return
        pause(); closed = true; timer?.cancel(); observer?.cancel()
        navigator?.close(); navigator = null; engine?.close(); engine = null
        runCatching { host.unregisterReceiver(noisy) }
    }
    fun installVoice() { pause(); AndroidTtsEngine.requestInstallVoice(host) }
    private fun message(value: String) { if (!closed && active) Toast.makeText(host, value, Toast.LENGTH_LONG).show() }
}
