import SwiftUI

struct ScreenshotRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: ScreenshotRecord
    let matchReason: String?

    init(record: ScreenshotRecord, matchReason: String? = nil) {
        self.record = record
        self.matchReason = matchReason
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenshotThumbnail(localIdentifier: record.localIdentifier)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 72 : 60, height: dynamicTypeSize.isAccessibilitySize ? 96 : 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            content
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.displayFileName)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.primaryMetadata)
                    .lineLimit(1)

                Text(record.secondaryMetadata)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let matchReason {
                Text(matchReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !record.userTags.isEmpty || !record.visibleSuggestedTags.isEmpty {
                TagList(userTags: Array(record.userTags.prefix(4)), suggestedTags: Array(record.visibleSuggestedTags.prefix(3)))
            }
        }
    }
}

private struct TagList: View {
    let userTags: [String]
    let suggestedTags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
            ForEach(userTags, id: \.self) { tag in
                TagChip(title: tag, tone: .owned)
            }

            ForEach(suggestedTags, id: \.self) { tag in
                TagChip(title: tag, tone: .suggested)
            }
        }
        }
    }
}

#Preview {
    ScreenshotRow(record: ScreenshotRecord(
        localIdentifier: "preview",
        fileName: "IMG_1423.PNG",
        extractedText: "Receipt total $24.18 paid by card",
        capturedAt: .now,
        userTags: ["work"],
        suggestedTags: ["receipt", "amount"],
        pixelWidth: 1170,
        pixelHeight: 2532
    ))
}
