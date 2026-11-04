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
                if (call.method == "notificationSettings") {
                    try {
                        val intent = if (android.os.Build.VERSION.SDK_INT >= 26)
                            android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        else android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("settings_unavailable", "Notification settings unavailable", null)
                    }
                    return@setMethodCallHandler
                }
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
