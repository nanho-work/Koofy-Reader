import Flutter
import UIKit
import IronSource
import AppTrackingTransparency

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let channel = FlutterMethodChannel(name: "com.koofylab.koofyreader/privacy",
      binaryMessenger: registrar(forPlugin: "KoofyPrivacy")!.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "configure", let args = call.arguments as? [String: Any],
            let requested = args["personalized"] as? Bool else {
        result(FlutterMethodNotImplemented); return
      }
      let allowed = requested && ATTrackingManager.trackingAuthorizationStatus == .authorized
      LPMPrivacySettings.setGDPRConsents(["UnityAds": NSNumber(value: allowed), "IronSource": NSNumber(value: allowed)])
      LPMPrivacySettings.setCCPA(!allowed)
      result(nil)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
