import Photos
import UIKit

enum PhotoImageLoader {
    static func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let hasError = info?[PHImageErrorKey] != nil

                if let image, !isDegraded {
                    didResume = true
                    continuation.resume(returning: image)
                    return
                }

                if wasCancelled || hasError {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                guard image == nil, !isDegraded else { return }
                didResume = true
                continuation.resume(returning: nil)
            }
        }
    }
}
