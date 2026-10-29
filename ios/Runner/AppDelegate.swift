import Flutter
import UIKit
import IronSource
import AppTrackingTransparency
import UserMessagingPlatform

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  private let adConsent = ReaderAdConsent()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Flutter 3.35 creates the storyboard engine after the scene connects.
    // Register plugins against that engine, rather than an absent app window.
    pluginRegistrant = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    let channel = FlutterMethodChannel(name: "com.koofylab.koofyreader/privacy",
      binaryMessenger: registry.registrar(forPlugin: "KoofyPrivacy")!.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "prepareConsent" || call.method == "showConsentOptions" {
        guard let self else { result(FlutterError(code: "consent_unavailable", message: "App unavailable", details: nil)); return }
        self.adConsent.handle(options: call.method == "showConsentOptions", result: result)
        return
      }
      guard call.method == "configure", let args = call.arguments as? [String: Any],
            let requested = args["personalized"] as? Bool else {
        result(FlutterMethodNotImplemented); return
      }
      let allowed = requested && ATTrackingManager.trackingAuthorizationStatus == .authorized
      LPMPrivacySettings.setGDPRConsents(["UnityAds": NSNumber(value: allowed), "IronSource": NSNumber(value: allowed), "AdMob": NSNumber(value: allowed)])
      LPMPrivacySettings.setCCPA(!allowed)
      result(nil)
    }
  }
}


/// Kept in the Runner target: UMP presents UI but never initializes advertising.
private final class ReaderAdConsent {
  private var busy = false

  // Keep SDK failures visible in device logs, including release builds.
  // Do not log consent strings, identifiers, or the full NSError userInfo.
  private func diagnose(_ stage: String, error: Error? = nil) {
    let info = ConsentInformation.shared
    NSLog("KoofyAds consent stage=%@ canRequestAds=%@ status=%@ options=%@ active=%@ busy=%@",
      stage, String(info.canRequestAds), String(describing: info.consentStatus),
      String(describing: info.privacyOptionsRequirementStatus),
      String(UIApplication.shared.applicationState == .active), String(busy))
    if let error = error as NSError? {
      NSLog("KoofyAds consent error stage=%@ domain=%@ code=%@ message=%@",
        stage, error.domain, String(error.code), error.localizedDescription)
    }
  }

  func handle(options: Bool, result: @escaping FlutterResult, activationRetries: Int = 50) {
    // Flutter's resumed notification can precede UIKit's active scene briefly.
    if UIApplication.shared.applicationState != .active && activationRetries > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.handle(options: options, result: result, activationRetries: activationRetries - 1)
      }
      return
    }
    diagnose(options ? "options_start" : "prepare_start")
    guard !busy, UIApplication.shared.applicationState == .active,
      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      diagnose("presenter_unavailable")
      result(FlutterError(code: "consent_unavailable", message: "Consent screen unavailable", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    busy = true
    let info = ConsentInformation.shared
    var retryableFailure = false
    let finish: () -> Void = { [weak self] in
      self?.busy = false
      self?.diagnose("finish")
      result([
        "canRequestAds": info.canRequestAds,
        "retryableFailure": retryableFailure,
        "privacyOptionsRequired": info.privacyOptionsRequirementStatus == .required,
        // Obtained includes a refusal. Keep NPA in regions using a CMP.
        "permitsPersonalization": info.consentStatus == .notRequired && info.privacyOptionsRequirementStatus == .notRequired,
      ])
    }
    if options {
      ConsentForm.presentPrivacyOptionsForm(from: presenter) { error in
        retryableFailure = error != nil
        self.diagnose("options_complete", error: error)
        finish()
      }
    } else {
      info.requestConsentInfoUpdate(with: RequestParameters()) { error in
        retryableFailure = error != nil
        self.diagnose("info_update_complete", error: error)
        guard error == nil else { finish(); return }
        guard UIApplication.shared.applicationState == .active else {
          self.busy = false
          self.diagnose("app_inactive")
          result(FlutterError(code: "consent_unavailable", message: "App is not active", details: nil))
          return
        }
        self.diagnose("form_start")
        ConsentForm.loadAndPresentIfRequired(from: presenter) { error in
          retryableFailure = error != nil
          self.diagnose("form_complete", error: error)
          finish()
        }
      }
    }
  }
}
