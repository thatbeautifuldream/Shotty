import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum SpotlightIndexer {
    private static let domainIdentifier = "shotty.screenshots"

    @MainActor
    static func index(_ records: [ScreenshotRecord]) async {
        let includeExtractedText = AppPreferences.spotlightIncludesExtractedText
        guard !records.isEmpty else { return }

        for record in records {
            await index(record, includeExtractedText: includeExtractedText)
        }
    }

    @MainActor
    static func index(_ record: ScreenshotRecord, includeExtractedText: Bool = AppPreferences.spotlightIncludesExtractedText) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
        attributeSet.displayName = record.displayFileName
        attributeSet.title = record.displayFileName
        attributeSet.contentDescription = searchableDescription(for: record, includeExtractedText: includeExtractedText)
        attributeSet.keywords = Array(Set(record.searchableTags)).sorted()
        attributeSet.contentCreationDate = record.capturedAt
        attributeSet.contentModificationDate = record.indexedAt
        attributeSet.metadataModificationDate = record.indexedAt
        attributeSet.kind = "Screenshot"
        attributeSet.containerDisplayName = "Shotty"
        attributeSet.userCreated = true
        attributeSet.userOwned = true

        let item = CSSearchableItem(
            uniqueIdentifier: record.localIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture

        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems([item]) { _ in
                continuation.resume()
            }
        }
    }

    static func deleteAll() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
                continuation.resume()
            }
        }
    }

    static func delete(localIdentifier: String) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [localIdentifier]) { _ in
                continuation.resume()
            }
        }
    }

    @MainActor
    private static func searchableDescription(for record: ScreenshotRecord, includeExtractedText: Bool) -> String {
        var components = [
            record.displayFileName,
            record.userTags.joined(separator: " "),
            record.visibleSuggestedTags.joined(separator: " ")
        ]

        if includeExtractedText {
            components.append(record.extractedText)
        }

        return components
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
