import Foundation
import Flutter

/// Whitelisted, portable listening records. Existing device preferences win.
enum SpeechBackupChannel {
    static func handle(_ call: FlutterMethodCall, defaults: UserDefaults = .standard, result: @escaping FlutterResult) {
        let prefix = "reader.speech."
        do {
            switch call.method {
            case "exportSpeech":
                var settings: [String: Any] = [:]
                for key in ["voice", "speed", "follow", "alwaysShow"] { settings[key] = defaults.object(forKey: prefix + key) }
                var positions: [String: String] = [:]
                for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix + "position.") {
                    guard JSONSerialization.isValidJSONObject(value) else { continue }
                    positions[String(key.dropFirst((prefix + "position.").count))] = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
                }
                result(["platform": "ios", "settings": settings, "positions": positions])
            case "mergeSpeech":
                guard let data = call.arguments as? [String: Any] else { throw BackupError.invalid }
                let settings = data["settings"] as? [String: Any] ?? [:]
                var pending: [String: Any] = [:]
                if let speed = settings["speed"] as? NSNumber {
                    guard speed.doubleValue.isFinite, (0.5...2).contains(speed.doubleValue) else { throw BackupError.invalid }
                    pending[prefix + "speed"] = speed.doubleValue
                }
                if let always = settings["alwaysShow"] as? Bool { pending[prefix + "alwaysShow"] = always }
                if let follow = settings["follow"] as? Bool { pending[prefix + "follow"] = follow }
                if data["platform"] as? String == "ios", let voice = settings["voice"] as? String { pending[prefix + "voice"] = voice }
                for (id, raw) in data["positions"] as? [String: String] ?? [:] {
                    guard id.count <= 200, raw.utf8.count <= 128000,
                          let value = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                          let revision = value["revision"] as? String, !revision.isEmpty,
                          let locator = value["locator"] as? String,
                          let location = try JSONSerialization.jsonObject(with: Data(locator.utf8)) as? [String: Any],
                          let href = location["href"] as? String, !href.isEmpty else { throw BackupError.invalid }
                    pending[prefix + "position." + id] = value
                }
                for (key, value) in pending where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        } catch { result(FlutterError(code: "speech_backup_failed", message: "듣기 기록을 백업·복원하지 못했습니다.", details: nil)) }
    }
    private enum BackupError: Error { case invalid }
}
