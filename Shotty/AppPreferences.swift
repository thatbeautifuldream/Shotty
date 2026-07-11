import Foundation

enum AppPreferences {
    static let spotlightIncludesExtractedTextKey = "spotlight.includeExtractedText"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            spotlightIncludesExtractedTextKey: true
        ])
    }

    static var spotlightIncludesExtractedText: Bool {
        if UserDefaults.standard.object(forKey: spotlightIncludesExtractedTextKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: spotlightIncludesExtractedTextKey)
    }
}
