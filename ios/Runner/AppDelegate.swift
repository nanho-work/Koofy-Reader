import Flutter
import UIKit
import IronSource
import AppTrackingTransparency
import UserMessagingPlatform

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let adConsent = ReaderAdConsent()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let channel = FlutterMethodChannel(name: "com.koofylab.koofyreader/privacy",
      binaryMessenger: registrar(forPlugin: "KoofyPrivacy")!.messenger())
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}


/// Kept in the Runner target: UMP presents UI but never initializes advertising.
private final class ReaderAdConsent {
  private var busy = false

  func handle(options: Bool, result: @escaping FlutterResult) {
    guard !busy, UIApplication.shared.applicationState == .active,
      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "consent_unavailable", message: "Consent screen unavailable", details: nil))
      return
    }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    busy = true
    let info = ConsentInformation.shared
    let finish: () -> Void = { [weak self] in
      self?.busy = false
      result([
        "canRequestAds": info.canRequestAds,
        "privacyOptionsRequired": info.privacyOptionsRequirementStatus == .required,
        // Obtained includes a refusal. Keep NPA in regions using a CMP.
        "permitsPersonalization": info.consentStatus == .notRequired && info.privacyOptionsRequirementStatus == .notRequired,
      ])
    }
    if options {
      ConsentForm.presentPrivacyOptionsForm(from: presenter) { _ in finish() }
    } else {
      info.requestConsentInfoUpdate(with: RequestParameters()) { error in
        guard error == nil else { finish(); return }
        guard UIApplication.shared.applicationState == .active else {
          self.busy = false
          result(FlutterError(code: "consent_unavailable", message: "App is not active", details: nil))
          return
        }
        ConsentForm.loadAndPresentIfRequired(from: presenter) { _ in finish() }
      }
    }
  }
}
