import UIKit

internal enum ReaderTheme {
    static func style(_ theme: String) -> UIUserInterfaceStyle {
        if theme == "app", !["light", "sepia", "dark"].contains(UserDefaults.standard.string(forKey: "flutter.app_theme_v1") ?? "system") { return .unspecified }
        return resolve(theme) == "dark" ? .dark : .light
    }
    static func resolve(_ theme: String) -> String {
        guard theme == "app" else { return theme }
        let mode = UserDefaults.standard.string(forKey: "flutter.app_theme_v1")
        if mode == "light" || mode == "dark" || mode == "sepia" { return mode! }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
    }
}
