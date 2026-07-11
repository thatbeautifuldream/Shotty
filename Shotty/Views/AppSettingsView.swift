import SwiftUI

struct AppSettingsView: View {
    @AppStorage(AppPreferences.spotlightIncludesExtractedTextKey) private var spotlightIncludesExtractedText = true

    var body: some View {
        List {
            Section("Search") {
                Toggle("Include OCR text in Spotlight", isOn: $spotlightIncludesExtractedText)
                    .tint(.green)

                Text("When this is on, screenshot text extracted by Shotty can appear in iPhone system Spotlight results outside the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
