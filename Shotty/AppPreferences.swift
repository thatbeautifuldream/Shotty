import Foundation

enum AppPreferences {
    static let spotlightIncludesExtractedTextKey = "spotlight.includeExtractedText"

    static var spotlightIncludesExtractedText: Bool {
        UserDefaults.standard.bool(forKey: spotlightIncludesExtractedTextKey)
    }
}
