import Foundation
import SwiftData

@Model
final class ScreenshotRecord {
    @Attribute(.unique) var localIdentifier: String
    var fileName: String = ""
    var extractedText: String = ""
    var capturedAt: Date = Date.distantPast
    var indexedAt: Date = Date.now
    var userTags: [String] = []
    var suggestedTags: [String] = []
    var hiddenSuggestedTags: [String] = []
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0

    init(
        localIdentifier: String,
        fileName: String,
        extractedText: String,
        capturedAt: Date,
        indexedAt: Date = .now,
        userTags: [String] = [],
        suggestedTags: [String] = [],
        hiddenSuggestedTags: [String] = [],
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.localIdentifier = localIdentifier
        self.fileName = fileName
        self.extractedText = extractedText
        self.capturedAt = capturedAt
        self.indexedAt = indexedAt
        self.userTags = userTags
        self.suggestedTags = suggestedTags
        self.hiddenSuggestedTags = hiddenSuggestedTags
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var previewText: String {
        extractedText.isEmpty ? "No text detected." : extractedText
    }

    var displayFileName: String {
        if !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fileName
        }

        return "Screenshot \(capturedAt.formatted(date: .numeric, time: .shortened))"
    }

    var primaryMetadata: String {
        capturedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var secondaryMetadata: String {
        "\(pixelWidth) by \(pixelHeight) · Indexed \(indexedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    var visibleSuggestedTags: [String] {
        suggestedTags.filter { !hiddenSuggestedTags.contains($0) && !userTags.contains($0) }
    }

    var searchableTags: [String] {
        Array(Set(userTags).union(visibleSuggestedTags)).sorted()
    }
}
