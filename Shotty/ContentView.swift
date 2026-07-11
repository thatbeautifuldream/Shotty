import Photos
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScreenshotRecord.capturedAt, order: .reverse) private var records: [ScreenshotRecord]

    @AppStorage(AppPreferences.spotlightIncludesExtractedTextKey) private var spotlightIncludesExtractedText = true
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                await refreshInboxFromPhotos()
            }
            .task(id: spotlightIncludesExtractedText) {
                await SpotlightIndexer.index(records)
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
                        Task {
                            await indexer.requestAccess()
                            await refreshInboxFromPhotos()
                        }
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
                    description: Text(records.isEmpty ? "Allow Photos access and Shotty will automatically build your private local index." : "Try another search term or tag.")
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
            "New screenshots are indexed automatically on this device and stored in a local searchable inbox."
        } else {
            "Allow Photos access to automatically index screenshots on this device."
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
