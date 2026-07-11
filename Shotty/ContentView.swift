import Photos
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScreenshotRecord.capturedAt, order: .reverse) private var records: [ScreenshotRecord]

    @StateObject private var indexer = ScreenshotIndexer()
    @State private var searchText = ""
    @State private var rankedResults: [ScreenshotSearchResult] = []

    private var searchResults: [DisplayedSearchResult] {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.localIdentifier, $0) })

        return rankedResults.compactMap { result in
            guard let record = recordsByID[result.recordID] else { return nil }
            return DisplayedSearchResult(record: record, reason: result.reason)
        }
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
            .task {
                await refreshInboxFromPhotos()
            }
            .task(id: SearchRefreshKey(query: searchText, snapshots: records.map(ScreenshotSearchSnapshot.init))) {
                await refreshSearchResults()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await refreshInboxFromPhotos() }
            }
        }
    }

    private var titleSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Shotty")
                .font(.largeTitle.weight(.bold))
                .fontWidth(.expanded)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if !records.isEmpty {
                CountBadge(count: records.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var summarySection: some View {
        Section {
            Group {
                if indexer.hasPhotoAccess {
                    indexedSummaryCard
                } else {
                    permissionSummaryCard
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var indexedSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
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
            }

            statusRow(message: indexer.state.message)
        }
    }

    private var permissionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.tertiary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Private screenshot index")
                        .font(.headline)

                    Text("Give Shotty access to your screenshots to build a fast, private index on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task {
                    await indexer.requestAccess()
                    await refreshInboxFromPhotos()
                }
            } label: {
                Text("Allow Photos Access")
                    .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(permissionFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var inboxSection: some View {
        if !searchResults.isEmpty {
            Section("Inbox") {
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

    private func statusRow(message: String) -> some View {
        HStack(spacing: 8) {
            if indexer.state.isIndexing {
                ProgressView()
                    .controlSize(.small)
            } else if case .failed = indexer.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionFootnote: String {
        switch indexer.state {
        case .requestingAccess:
            return "Requesting Photos access"
        case .denied:
            return "Photos access is needed to build your inbox"
        case let .failed(message):
            return message
        default:
            return "Shotty only indexes screenshots you allow it to read."
        }
    }

    private var summaryText: String {
        if indexer.hasPhotoAccess {
            "New screenshots are indexed automatically on this device and stored in a local searchable inbox."
        } else {
            "Give Shotty access to start indexing screenshots on this device."
        }
    }

    @MainActor
    private func refreshInboxFromPhotos() async {
        indexer.refreshAuthorizationStatus()
        await indexer.reconcileLibrary(in: modelContext)

        guard indexer.hasPhotoAccess else { return }
        await indexer.indexScreenshots(in: modelContext)
    }

    @MainActor
    private func refreshSearchResults() async {
        let snapshots = records.map(ScreenshotSearchSnapshot.init)
        let query = searchText

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await Task.sleep(for: .milliseconds(120))
        }

        let results = await Task.detached(priority: .userInitiated) {
            ScreenshotSearch.rank(snapshots, query: query)
        }.value

        guard !Task.isCancelled else { return }
        rankedResults = results
    }

}

private struct CountBadge: View {
    let count: Int

    private var compactCount: String {
        switch count {
        case 0..<1_000:
            return String(count)
        case 1_000..<10_000:
            let value = Double(count) / 1_000
            let rounded = (value * 10).rounded() / 10
            return rounded.formatted(.number.precision(.fractionLength(0...1))) + "k"
        case 10_000..<1_000_000:
            return String((Double(count) / 1_000).rounded()) + "k"
        default:
            let value = Double(count) / 1_000_000
            let rounded = value >= 10 ? value.rounded() : (value * 10).rounded() / 10
            return rounded.formatted(.number.precision(.fractionLength(0...1))) + "m"
        }
    }

    var body: some View {
        Text(compactCount)
            .font(.title3.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText(value: Double(count)))
            .foregroundStyle(.secondary)
            .animation(.snappy(duration: 0.28), value: count)
            .accessibilityLabel("\(count) indexed screenshots")
    }
}

private struct DisplayedSearchResult: Identifiable {
    let record: ScreenshotRecord
    let reason: String?

    var id: String { record.localIdentifier }
}

private struct SearchRefreshKey: Equatable {
    let query: String
    let snapshots: [ScreenshotSearchSnapshot]
}

#Preview {
    ContentView()
        .modelContainer(for: ScreenshotRecord.self, inMemory: true)
}
