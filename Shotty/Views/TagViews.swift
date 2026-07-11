import SwiftUI

enum TagChipTone {
    case owned
    case suggested

    var iconName: String {
        switch self {
        case .owned: "tag.fill"
        case .suggested: "sparkles"
        }
    }

    var foregroundStyle: AnyShapeStyle {
        switch self {
        case .owned: AnyShapeStyle(.primary)
        case .suggested: AnyShapeStyle(.secondary)
        }
    }

    var backgroundStyle: AnyShapeStyle {
        switch self {
        case .owned: AnyShapeStyle(Color(.tertiarySystemFill))
        case .suggested: AnyShapeStyle(Color(.secondarySystemBackground))
        }
    }

    var borderStyle: AnyShapeStyle {
        switch self {
        case .owned: AnyShapeStyle(.white.opacity(0.06))
        case .suggested: AnyShapeStyle(.white.opacity(0.08))
        }
    }
}

struct TagChip: View {
    let title: String
    let tone: TagChipTone
    var accessorySystemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tone.iconName)
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.monochrome)

            Text(title)
                .lineLimit(1)

            if let accessorySystemImage {
                Image(systemName: accessorySystemImage)
                    .font(.caption2.weight(.bold))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foregroundStyle)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.backgroundStyle, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tone.borderStyle, lineWidth: 1)
        }
        .shadow(color: .black.opacity(tone == .owned ? 0.1 : 0.06), radius: tone == .owned ? 8 : 5, y: 2)
    }
}
