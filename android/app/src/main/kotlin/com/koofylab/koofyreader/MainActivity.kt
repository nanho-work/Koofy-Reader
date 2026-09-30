package com.koofylab.koofyreader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.unity3d.mediation.LevelPlayPrivacySettings

class MainActivity : FlutterActivity() {
    private val adConsent by lazy { AdConsent(this) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.koofylab.koofyreader/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "prepareConsent" || call.method == "showConsentOptions") {
                    adConsent.handle(call.method == "showConsentOptions", result)
                    return@setMethodCallHandler
                }
                val personalized = call.argument<Boolean>("personalized")
                if (call.method != "configure" || personalized == null) {
                    result.notImplemented()
                } else {
                    LevelPlayPrivacySettings.setGDPRConsents(mapOf("UnityAds" to personalized, "IronSource" to personalized, "AdMob" to personalized))
                    LevelPlayPrivacySettings.setCCPA(!personalized)
                    result.success(null)
                }
            }
    }
}
