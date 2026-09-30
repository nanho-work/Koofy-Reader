package com.koofy.reader.bridge

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Closed-reader maintenance only. Never exports advertising or account data. */
internal class SpeechBackupChannel(context: Context, messenger: BinaryMessenger) {
    private val prefs = context.getSharedPreferences("reader_speech", Context.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "koofy_reader/maintenance")
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                check(ReaderRuntime.session == null) { "Close the reader before backup" }
                when (call.method) {
                    "exportSpeech" -> result.success(mapOf(
                        "platform" to "android",
                        "settings" to buildMap<String, Any> {
                            if (prefs.contains("speed")) put("speed", prefs.getFloat("speed", 1f).toDouble())
                            if (prefs.contains("voice")) prefs.getString("voice", null)?.let { put("voice", it) }
                            if (prefs.contains("alwaysShow")) put("alwaysShow", prefs.getBoolean("alwaysShow", false))
                            if (prefs.contains("follow")) put("follow", prefs.getBoolean("follow", true))
                        },
                        "positions" to prefs.all.filter { it.key.startsWith("position.") && it.value is String }
                            .mapKeys { it.key.removePrefix("position.") }
                    ))
                    "mergeSpeech" -> {
                        val data = call.arguments as Map<*, *>
                        val edit = prefs.edit()
                        val settings = data["settings"] as? Map<*, *> ?: emptyMap<Any, Any>()
                        val speed = (settings["speed"] as? Number)?.toDouble()
                        require(speed == null || speed.isFinite() && speed in .5..2.0)
                        if (!prefs.contains("speed") && speed != null) edit.putFloat("speed", speed.toFloat())
                        if (!prefs.contains("alwaysShow")) (settings["alwaysShow"] as? Boolean)?.let { edit.putBoolean("alwaysShow", it) }
                        if (!prefs.contains("follow")) (settings["follow"] as? Boolean)?.let { edit.putBoolean("follow", it) }
                        if (data["platform"] == "android" && !prefs.contains("voice")) (settings["voice"] as? String)?.let { edit.putString("voice", it) }
                        val positions = data["positions"] as? Map<*, *> ?: emptyMap<Any, Any>()
                        for ((id, raw) in positions) {
                            require(id is String && id.length <= 200 && raw is String && raw.length <= 128000)
                            val item = JSONObject(raw)
                            require(item.getString("revision").isNotEmpty() && JSONObject(item.getString("locator")).getString("href").isNotEmpty())
                            if (!prefs.contains("position.$id")) edit.putString("position.$id", raw)
                        }
                        check(edit.commit()) { "Could not save speech backup" }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("speech_backup_failed", "듣기 기록을 백업·복원하지 못했습니다. 독서 화면을 닫고 다시 시도해 주세요.", null) }
        }
    }
    fun dispose() = channel.setMethodCallHandler(null)
}
