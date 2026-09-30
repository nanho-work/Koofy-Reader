package com.koofy.reader.bridge

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class SpeechBackupChannelTest {
    @Test fun exportsOnlySpeechAndMergesWithoutReplacingExistingOrForeignVoice() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val prefs = context.getSharedPreferences("reader_speech", Context.MODE_PRIVATE)
        prefs.edit().clear().putFloat("speed", 1.25f).putString("unrelated", "not-exported").commit()
        val messenger = LocalMessenger()
        instrumentation.runOnMainSync {
            val channel = SpeechBackupChannel(context, messenger)
            try {
                val item = JSONObject().put("revision", "body-v1").put("locator", "{\"href\":\"body.xhtml\"}").toString()
                messenger.call("mergeSpeech", mapOf("platform" to "ios", "settings" to mapOf("voice" to "apple-only", "speed" to 2.0, "follow" to false), "positions" to mapOf("book" to item)))
                assertEquals(1.25f, prefs.getFloat("speed", 0f), 0f)
                assertFalse(prefs.contains("voice"))
                assertFalse(prefs.getBoolean("follow", true))
                assertEquals(item, prefs.getString("position.book", null))
                messenger.call("mergeSpeech", mapOf("platform" to "android", "settings" to mapOf("voice" to "local-voice"), "positions" to mapOf("book" to item.replace("body-v1", "older"))))
                val exported = messenger.call("exportSpeech", null) as Map<*, *>
                assertFalse(exported.toString().contains("not-exported"))
                assertEquals("local-voice", (exported["settings"] as Map<*, *>)["voice"])
                assertEquals(item, (exported["positions"] as Map<*, *>)["book"])
            } finally { channel.dispose(); prefs.edit().clear().commit() }
        }
    }
    private class LocalMessenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        override fun send(channel: String, message: ByteBuffer?) = error("Not used")
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = error("Not used")
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) { this.handler = handler }
        fun call(method: String, arguments: Any?): Any? {
            var value: Any? = null
            val input = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments)).apply { flip() }
            handler!!.onMessage(input) { reply -> value = StandardMethodCodec.INSTANCE.decodeEnvelope(reply!!.apply { flip() }) }
            return value
        }
    }
}
