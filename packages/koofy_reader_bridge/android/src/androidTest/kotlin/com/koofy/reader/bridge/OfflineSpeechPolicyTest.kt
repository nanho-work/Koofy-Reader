package com.koofy.reader.bridge

import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OfflineSpeechPolicyTest {
    @Test fun downloadedOfflineVoiceIsRequiredEvenWhenNetworkVoiceHasHigherQuality() {
        fun voice(network: Boolean, features: Set<String>) = Voice("ko-test", Locale.KOREAN,
            Voice.QUALITY_VERY_HIGH, Voice.LATENCY_NORMAL, network, features)
        assertTrue(isOfflineSpeechVoice(voice(false, emptySet())))
        assertFalse(isOfflineSpeechVoice(voice(true, emptySet())))
        assertFalse(isOfflineSpeechVoice(voice(false, setOf(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))))
    }
    @Test fun longSentenceChunksPreserveEveryCharacterAndUtf16Offsets() {
        val original = "가".repeat(2999) + "📚" + "나".repeat(8000) + "\n마지막 문장."
        val pieces = speechPieces(original).toList()
        assertEquals(original, pieces.joinToString("") { it.second })
        var offset = 0
        pieces.forEach { (start, text) ->
            assertEquals(offset, start)
            assertTrue(text.length <= 3000)
            assertFalse(text.first().isLowSurrogate())
            assertFalse(text.last().isHighSurrogate())
            offset += text.length
        }
        assertTrue(speechPieces("").none())
    }
}
