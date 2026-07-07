import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum SpotlightIndexer {
    private static let domainIdentifier = "shotty.screenshots"

    @MainActor
    static func index(_ records: [ScreenshotRecord]) async {
        guard !records.isEmpty else { return }

        for record in records {
            await index(record)
        }
    }

    @MainActor
    static func index(_ record: ScreenshotRecord) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
        attributeSet.displayName = record.displayFileName
        attributeSet.title = record.displayFileName
        attributeSet.contentDescription = searchableDescription(for: record)
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

    static func delete(localIdentifier: String) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [localIdentifier]) { _ in
                continuation.resume()
            }
        }
    }

    static func matchingIdentifiers(for query: String, limit: Int = 40) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard CSSearchableIndex.isIndexingAvailable() else { return [] }
        guard #available(iOS 16.0, *) else { return [] }

        return await withTaskGroup(of: [String].self) { group in
            group.addTask {
                await userQueryIdentifiers(for: trimmedQuery, limit: limit)
            }

            group.addTask {
                try? await Task.sleep(for: .milliseconds(600))
                return []
            }

            let identifiers = await group.next() ?? []
            group.cancelAll()
            return identifiers
        }
    }

    @available(iOS 16.0, *)
    private static func userQueryIdentifiers(for queryText: String, limit: Int) async -> [String] {
        let context = CSUserQueryContext()
        context.enableRankedResults = true
        context.maxResultCount = limit

        if #available(iOS 18.0, *) {
            context.disableSemanticSearch = false
            context.maxRankedResultCount = limit
        }

        let query = CSUserQuery(userQueryString: queryText, userQueryContext: context)
        var identifiers: [String] = []

        query.start()
        defer { query.cancel() }

        do {
            for try await response in query.responses {
                guard !Task.isCancelled else { break }

                if case let .item(result) = response,
                   result.item.domainIdentifier == domainIdentifier,
                   !identifiers.contains(result.item.uniqueIdentifier) {
                    identifiers.append(result.item.uniqueIdentifier)
                }

                if identifiers.count >= limit {
                    break
                }
            }
        } catch {
            return identifiers
        }

        return identifiers
    }

    @MainActor
    private static func searchableDescription(for record: ScreenshotRecord) -> String {
        [
            record.displayFileName,
            record.userTags.joined(separator: " "),
            record.visibleSuggestedTags.joined(separator: " "),
            record.extractedText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}
