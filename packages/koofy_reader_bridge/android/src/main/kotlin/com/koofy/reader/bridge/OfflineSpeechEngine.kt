@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.readium.navigator.media.tts.TtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.shared.util.Language

internal fun isOfflineSpeechVoice(voice: android.speech.tts.Voice): Boolean =
    !voice.isNetworkConnectionRequired && !voice.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)

internal fun speechPieces(text: String): Sequence<Pair<Int, String>> = sequence {
    var offset = 0
    while (offset < text.length) {
        var end = minOf(offset + 3000, text.length)
        if (end < text.length && text[end - 1].isHighSurrogate()) end--
        yield(offset to text.substring(offset, end))
        offset = end
    }
}

/** Explicit installed voice on every request: never fall back to setLanguage/network synthesis. */
internal class OfflineSpeechEngine private constructor(private val native: TextToSpeech) :
    TtsEngine<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice> {
    companion object {
        suspend fun create(context: Context): OfflineSpeechEngine? {
            val ready = CompletableDeferred<Boolean>()
            val tts = TextToSpeech(context) { ready.complete(it == TextToSpeech.SUCCESS) }
            try {
                if (ready.await()) return OfflineSpeechEngine(tts)
            } catch (error: Exception) { tts.shutdown(); throw error }
            tts.shutdown()
            return null
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private var listener: TtsEngine.Listener<AndroidTtsEngine.Error>? = null
    private var closed = false
    var onPreviewFinished: (() -> Unit)? = null
    private var previewId: String? = null
    private var serial = 0L
    private data class Piece(val request: TtsEngine.RequestId, val offset: Int, val first: Boolean, val last: Boolean)
    private val pending = mutableMapOf<String, Piece>()
    override val voices: Set<AndroidTtsEngine.Voice> get() = native.voices.orEmpty()
        .filter { isOfflineSpeechVoice(it) }
        .map { AndroidTtsEngine.Voice(AndroidTtsEngine.Voice.Id(it.name), Language(it.locale), requiresNetwork = false) }.toSet()
    override val settings = MutableStateFlow(AndroidTtsSettings(Language("ko"), true, 1.0, 1.0, emptyMap()))

    init {
        native.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        native.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String) { main.post { pending[id]?.let { if (it.first) listener?.onStart(it.request) } } }
            override fun onDone(id: String) { main.post { if (id == previewId) { previewId = null; onPreviewFinished?.invoke() }; pending.remove(id)?.let { if (it.last) listener?.onDone(it.request) } } }
            @Deprecated("Platform callback") override fun onError(id: String) = onError(id, TextToSpeech.ERROR)
            override fun onError(id: String, errorCode: Int) { main.post {
                if (id == previewId) { previewId = null; onPreviewFinished?.invoke() }
                pending[id]?.let { piece ->
                    pending.clear()
                    native.stop()
                    listener?.onError(piece.request, AndroidTtsEngine.Error.Synthesis)
                }
            } }
            override fun onRangeStart(id: String, start: Int, end: Int, frame: Int) { main.post {
                pending[id]?.let { listener?.onRange(it.request, (it.offset + start) until (it.offset + end)) }
            } }
        })
    }
    override fun submitPreferences(preferences: AndroidTtsPreferences) {
        settings.value = AndroidTtsSettings(preferences.language ?: Language("ko"), true, 1.0,
            (preferences.speed ?: 1.0).coerceIn(.5, 2.0), preferences.voices.orEmpty())
    }
    override fun setListener(listener: TtsEngine.Listener<AndroidTtsEngine.Error>?) { this.listener = listener }
    override fun speak(requestId: TtsEngine.RequestId, text: String, language: Language?) {
        if (closed) return
        val selected = settings.value.voices.values.firstOrNull()?.value
        val voice = native.voices.orEmpty().firstOrNull {
            it.name == selected && isOfflineSpeechVoice(it)
        }
        if (voice == null || native.setVoice(voice) != TextToSpeech.SUCCESS) {
            listener?.onError(requestId, AndroidTtsEngine.Error.LanguageMissingData(settings.value.language))
            return
        }
        native.setSpeechRate(settings.value.speed.toFloat())
        // Bound very long sentences without losing characters or splitting UTF-16 surrogate pairs.
        for ((offset, piece) in speechPieces(text)) {
            val id = "koofy-${++serial}"
            pending[id] = Piece(requestId, offset, offset == 0, offset + piece.length == text.length)
            val result = native.speak(piece, TextToSpeech.QUEUE_ADD, Bundle().apply {
                putString(TextToSpeech.Engine.KEY_FEATURE_EMBEDDED_SYNTHESIS, "true")
            }, id)
            if (result != TextToSpeech.SUCCESS) {
                pending.clear()
                native.stop()
                listener?.onError(requestId, AndroidTtsEngine.Error.Synthesis)
                return
            }
        }
    }
    fun preview(id: String, speed: Double): Boolean {
        stop()
        val voice = native.voices.orEmpty().firstOrNull { it.name == id && isOfflineSpeechVoice(it) } ?: return false
        if (native.setVoice(voice) != TextToSpeech.SUCCESS) return false
        native.setSpeechRate(speed.toFloat())
        val preview = "preview-${++serial}"
        previewId = preview
        return native.speak("안녕하세요. 쿠피리더에서 편안하게 책을 들어 보세요.", TextToSpeech.QUEUE_FLUSH,
            Bundle().apply { putString(TextToSpeech.Engine.KEY_FEATURE_EMBEDDED_SYNTHESIS, "true") }, preview) == TextToSpeech.SUCCESS
    }
    override fun stop() {
        previewId = null
        val requests = pending.values.map { it.request }.distinct()
        pending.clear()
        native.stop()
        requests.forEach { listener?.onInterrupted(it) }
    }
    override fun close() { if (!closed) { closed = true; stop(); listener = null; native.shutdown() } }
}
