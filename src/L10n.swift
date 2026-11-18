import Foundation

enum L10n {
    private static let language: String = {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") != nil,
           let localization = Bundle.main.preferredLocalizations.first {
            return localization
        }
        // Standalone swiftc tools have no bundle metadata.
        return Bundle.preferredLocalizations(
            from: ["zh-Hant", "en"],
            forPreferences: Locale.preferredLanguages + ["zh-Hant"]
        ).first ?? "zh-Hant"
    }()

    static func text(_ zh: String, _ en: String) -> String {
        language == "en" ? en : zh
    }
}
