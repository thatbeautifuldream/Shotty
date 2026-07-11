import Foundation
import NaturalLanguage

struct ScreenshotSearchResult: Identifiable, Equatable, Sendable {
    let recordID: String
    let score: Int
    let reason: String?

    var id: String { recordID }
}

struct ScreenshotSearchSnapshot: Sendable, Equatable {
    let localIdentifier: String
    let displayFileName: String
    let extractedText: String
    let capturedAt: Date
    let userTags: [String]
    let visibleSuggestedTags: [String]

    init(record: ScreenshotRecord) {
        localIdentifier = record.localIdentifier
        displayFileName = record.displayFileName
        extractedText = record.extractedText
        capturedAt = record.capturedAt
        userTags = record.userTags
        visibleSuggestedTags = record.visibleSuggestedTags
    }
}

enum ScreenshotSearch {
    static func rank(_ records: [ScreenshotRecord], query: String) -> [ScreenshotSearchResult] {
        rank(records.map(ScreenshotSearchSnapshot.init), query: query)
    }

    static func rank(_ records: [ScreenshotSearchSnapshot], query: String) -> [ScreenshotSearchResult] {
        let normalizedQuery = normalize(query)
        let captureDatesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.localIdentifier, $0.capturedAt) })

        guard !normalizedQuery.isEmpty else {
            return records.map {
                ScreenshotSearchResult(recordID: $0.localIdentifier, score: 0, reason: nil)
            }
        }

        let queryTokens = tokens(in: normalizedQuery)

        return records
            .compactMap { record -> ScreenshotSearchResult? in
                let userTagScore = score(tags: record.userTags, query: normalizedQuery, exact: 120, partial: 90)
                let fileNameScore = normalize(record.displayFileName).contains(normalizedQuery) ? 80 : 0
                let suggestedTagScore = score(tags: record.visibleSuggestedTags, query: normalizedQuery, exact: 70, partial: 50)
                let ocrScore = normalize(record.extractedText).contains(normalizedQuery) ? 25 : 0
                let tokenScore = tokenScore(for: record, queryTokens: queryTokens)
                let totalScore = userTagScore + fileNameScore + suggestedTagScore + ocrScore + tokenScore

                guard totalScore > 0 else { return nil }

                return ScreenshotSearchResult(
                    recordID: record.localIdentifier,
                    score: totalScore,
                    reason: reason(
                        userTagScore: userTagScore,
                        fileNameScore: fileNameScore,
                        suggestedTagScore: suggestedTagScore,
                        ocrScore: ocrScore,
                        tokenScore: tokenScore
                    )
                )
            }
            .sorted { left, right in
                if left.score == right.score {
                    return captureDatesByID[left.recordID, default: .distantPast] > captureDatesByID[right.recordID, default: .distantPast]
                }
                return left.score > right.score
            }
    }

    private static func score(tags: [String], query: String, exact: Int, partial: Int) -> Int {
        tags.reduce(0) { result, tag in
            let normalizedTag = normalize(tag)
            if normalizedTag == query {
                return result + exact
            }
            if normalizedTag.contains(query) {
                return result + partial
            }
            return result
        }
    }

    private static func tokenScore(for record: ScreenshotSearchSnapshot, queryTokens: Set<String>) -> Int {
        guard !queryTokens.isEmpty else { return 0 }

        let tagText = (record.userTags + record.visibleSuggestedTags).joined(separator: " ")
        let filenameMatches = queryTokens.intersection(tokens(in: record.displayFileName)).count
        let tagMatches = queryTokens.intersection(tokens(in: tagText)).count
        let textMatches = queryTokens.intersection(tokens(in: record.extractedText)).count

        return min(filenameMatches * 12 + tagMatches * 16 + textMatches * 4, 44)
    }

    private static func reason(
        userTagScore: Int,
        fileNameScore: Int,
        suggestedTagScore: Int,
        ocrScore: Int,
        tokenScore: Int
    ) -> String {
        if userTagScore > 0 { return "Tag match" }
        if fileNameScore > 0 { return "Filename match" }
        if suggestedTagScore > 0 { return "Suggested tag match" }
        if ocrScore > 0 { return "Text match" }
        if tokenScore > 0 { return "Word match" }
        return "Match"
    }

    private static func tokens(in value: String) -> Set<String> {
        let normalizedValue = normalize(value)
        guard !normalizedValue.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalizedValue

        var result = Set<String>()
        tokenizer.enumerateTokens(in: normalizedValue.startIndex..<normalizedValue.endIndex) { range, attributes in
            let token = String(normalizedValue[range])
            if token.count > 1 || attributes.contains(.numeric) {
                result.insert(token)
            }
            return true
        }

        return result
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
