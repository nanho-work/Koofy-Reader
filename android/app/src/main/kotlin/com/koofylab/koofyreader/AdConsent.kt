package com.koofylab.koofyreader

import android.app.Activity
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import io.flutter.plugin.common.MethodChannel

/** UMP is the authority for whether an ad request is allowed, not our local choice. */
class AdConsent(private val activity: Activity) {
    private val info = UserMessagingPlatform.getConsentInformation(activity)
    private var busy = false

    fun handle(options: Boolean, result: MethodChannel.Result) {
        if (busy || activity.isFinishing || activity.isDestroyed) {
            result.error("consent_unavailable", "Consent screen unavailable", null)
            return
        }
        busy = true
        fun finish() {
            busy = false
            result.success(mapOf(
                "canRequestAds" to info.canRequestAds(),
                "privacyOptionsRequired" to (info.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED),
                // 'OBTAINED' can mean reject. In CMP regions retain NPA rather
                // than inventing vendor consent from this aggregate status.
                "permitsPersonalization" to (info.consentStatus == ConsentInformation.ConsentStatus.NOT_REQUIRED && info.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.NOT_REQUIRED)
            ))
        }
        if (options) {
            UserMessagingPlatform.showPrivacyOptionsForm(activity) { finish() }
        } else {
            info.requestConsentInfoUpdate(activity, ConsentRequestParameters.Builder().build(), {
                if (activity.isFinishing || activity.isDestroyed) {
                    busy = false
                    result.error("consent_unavailable", "Activity no longer available", null)
                } else {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { finish() }
                }
            }, { finish() })
        }
    }
}
