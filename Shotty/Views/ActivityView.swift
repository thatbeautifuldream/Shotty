import Photos
import SwiftUI

struct ScreenshotThumbnail: View {
    let localIdentifier: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .symbolRenderingMode(.monochrome)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
        .task(id: localIdentifier) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }

        image = await PhotoImageLoader.image(
            for: asset,
            targetSize: CGSize(width: 220, height: 300),
            contentMode: .aspectFill
        )
    }
}
