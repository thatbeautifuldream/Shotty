import NaturalLanguage
import Photos
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScreenshotRecord.capturedAt, order: .reverse) private var records: [ScreenshotRecord]

    @StateObject private var indexer = ScreenshotIndexer()
    @State private var searchText = ""

    private var searchResults: [ScreenshotSearchResult] {
        ScreenshotSearch.rank(records, query: searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                titleSection
                summarySection
                inboxSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search screenshots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await indexer.indexScreenshots(in: modelContext) }
                    } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                    .disabled(indexer.state.isIndexing)
                }
            }
            .task {
                if indexer.hasPhotoAccess && records.isEmpty {
                    await indexer.indexScreenshots(in: modelContext)
                }
            }
            .task(id: records.map(\.localIdentifier).joined(separator: "|")) {
                await SpotlightIndexer.index(records)
            }
        }
    }

    private var titleSection: some View {
        Text("Shotty")
            .font(.largeTitle.weight(.bold))
            .fontWidth(.expanded)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: indexer.hasPhotoAccess ? "lock.shield.fill" : "photo.badge.plus")
                        .symbolRenderingMode(.monochrome)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private screenshot index")
                            .font(.headline)

                        Text(summaryText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if !records.isEmpty {
                        CountBadge(count: records.count)
                    }
                }

                statusRow

                if !indexer.hasPhotoAccess {
                    Button {
                        Task { await indexer.requestAccess() }
                    } label: {
                        Label("Allow Photos Access", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .controlSize(.regular)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var inboxSection: some View {
        Section("Inbox") {
            if searchResults.isEmpty {
                ContentUnavailableView(
                    records.isEmpty ? "No Screenshots Indexed" : "No Matches",
                    systemImage: records.isEmpty ? "photo.stack" : "magnifyingglass",
                    description: Text(records.isEmpty ? "Allow Photos access, then scan to build a private local index." : "Try another search term or tag.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(searchResults) { result in
                    NavigationLink {
                        ScreenshotDetailView(record: result.record)
                    } label: {
                        ScreenshotRow(record: result.record, matchReason: result.reason)
                    }
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if indexer.state.isIndexing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: indexer.hasPhotoAccess ? "checkmark.circle.fill" : "info.circle")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }

            Text(indexer.state.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryText: String {
        if indexer.hasPhotoAccess {
            "Screenshots are scanned with on-device OCR and stored in a local index."
        } else {
            "Allow Photos access when you are ready to scan screenshots on this device."
        }
    }

}

private extension ScreenshotIndexer.State {
    var isIndexing: Bool {
        if case .indexing = self { return true }
        if case .requestingAccess = self { return true }
        return false
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.headline.monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tertiary, in: Capsule())
            .accessibilityLabel("\(count) indexed screenshots")
    }
}

private struct ScreenshotSearchResult: Identifiable {
    let record: ScreenshotRecord
    let score: Int
    let reason: String?

    var id: String { record.localIdentifier }
}

private enum ScreenshotSearch {
    static func rank(_ records: [ScreenshotRecord], query: String) -> [ScreenshotSearchResult] {
        let normalizedQuery = normalize(query)

        guard !normalizedQuery.isEmpty else {
            return records.map {
                ScreenshotSearchResult(record: $0, score: 0, reason: nil)
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
                    record: record,
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
                    return left.record.capturedAt > right.record.capturedAt
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

    private static func tokenScore(for record: ScreenshotRecord, queryTokens: Set<String>) -> Int {
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

#Preview {
    ContentView()
        .modelContainer(for: ScreenshotRecord.self, inMemory: true)
}
