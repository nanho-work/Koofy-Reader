package com.koofylab.koofyreader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.unity3d.mediation.LevelPlayPrivacySettings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.koofylab.koofyreader/privacy")
            .setMethodCallHandler { call, result ->
                val personalized = call.argument<Boolean>("personalized")
                if (call.method != "configure" || personalized == null) {
                    result.notImplemented()
                } else {
                    LevelPlayPrivacySettings.setGDPRConsents(mapOf("UnityAds" to personalized, "IronSource" to personalized))
                    LevelPlayPrivacySettings.setCCPA(!personalized)
                    result.success(null)
                }
            }
    }
}
