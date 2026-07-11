import Photos
import UIKit

enum PhotoImageLoader {
    static func image(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) async -> UIImage? {
        let requestState = PhotoImageRequestState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = false

                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    let hasError = info?[PHImageErrorKey] != nil
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true

                    if let image, !isDegraded {
                        requestState.resumeIfNeeded(with: image, continuation: continuation)
                        return
                    }

                    if wasCancelled || hasError || isInCloud {
                        requestState.resumeIfNeeded(with: nil, continuation: continuation)
                        return
                    }

                    guard image == nil, !isDegraded else { return }
                    requestState.resumeIfNeeded(with: nil, continuation: continuation)
                }

                requestState.requestID = requestID
            }
        } onCancel: {
            requestState.cancel()
        }
    }
}

private final class PhotoImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    var requestID: PHImageRequestID?

    func resumeIfNeeded(with image: UIImage?, continuation: CheckedContinuation<UIImage?, Never>) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }

        hasResumed = true
        lock.unlock()
        continuation.resume(returning: image)
    }

    func cancel() {
        lock.lock()
        let requestID = requestID
        lock.unlock()

        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }
}
