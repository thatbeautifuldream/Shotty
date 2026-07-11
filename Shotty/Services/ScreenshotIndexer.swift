import Foundation
import Photos
import SwiftData
import SwiftUI
import UIKit
import Vision
import VisionKit

@MainActor
final class ScreenshotIndexer: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingAccess
        case indexing(current: Int, total: Int)
        case complete(indexed: Int)
        case denied
        case failed(String)

        var message: String {
            switch self {
            case .idle: "Watching for new screenshots"
            case .requestingAccess: "Requesting Photos access"
            case let .indexing(current, total): "Indexing \(current) of \(total)"
            case let .complete(indexed): indexed == 0 ? "Everything is up to date" : "Indexed \(indexed) new screenshots"
            case .denied: "Photos access is needed to build your inbox"
            case let .failed(message): message
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let classifier = ScreenshotClassifier()

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        guard !state.isIndexing else { return }

        if hasPhotoAccess {
            if case .denied = state {
                state = .idle
            }
        } else {
            state = .denied
        }
    }

    func requestAccess() async {
        state = .requestingAccess
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        if !hasPhotoAccess {
            state = .denied
        } else {
            state = .idle
        }
    }

    func reconcileLibrary(in context: ModelContext) async {
        refreshAuthorizationStatus()

        do {
            let existingRecords = try context.fetch(FetchDescriptor<ScreenshotRecord>())

            guard !existingRecords.isEmpty else { return }

            if !hasPhotoAccess {
                for record in existingRecords {
                    context.delete(record)
                }
                try context.save()
                return
            }

            let accessibleAssets = PHAsset.fetchAssets(
                withLocalIdentifiers: existingRecords.map(\.localIdentifier),
                options: nil
            )

            var accessibleIDs = Set<String>()
            accessibleAssets.enumerateObjects { asset, _, _ in
                accessibleIDs.insert(asset.localIdentifier)
            }

            let inaccessibleRecords = existingRecords.filter { !accessibleIDs.contains($0.localIdentifier) }
            guard !inaccessibleRecords.isEmpty else { return }

            for record in inaccessibleRecords {
                context.delete(record)
            }

            try context.save()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func indexScreenshots(in context: ModelContext) async {
        guard !state.isIndexing else { return }

        guard hasPhotoAccess else {
            await requestAccess()
            guard hasPhotoAccess else { return }
            return await indexScreenshots(in: context)
        }

        do {
            let existingRecords = try context.fetch(FetchDescriptor<ScreenshotRecord>())
            refreshExistingRecords(existingRecords)
            try context.save()

            let existingIDs = Set(existingRecords.map(\.localIdentifier))
            let assets = fetchScreenshotAssets().filter { !existingIDs.contains($0.localIdentifier) }

            guard !assets.isEmpty else {
                state = .complete(indexed: 0)
                return
            }

            var indexedCount = 0

            for (offset, asset) in assets.enumerated() {
                state = .indexing(current: offset + 1, total: assets.count)

                let fileName = asset.fileName
                let record = ScreenshotRecord(
                    localIdentifier: asset.localIdentifier,
                    fileName: fileName,
                    extractedText: "",
                    capturedAt: asset.creationDate ?? .distantPast,
                    suggestedTags: classifier.suggestTags(for: "", fileName: fileName).tags,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )

                context.insert(record)
                try context.save()
                indexedCount += 1

                let image = await PhotoImageLoader.image(
                    for: asset,
                    targetSize: CGSize(width: 1800, height: 1800)
                )
                let text: String
                if let image {
                    text = await extractText(in: image)
                } else {
                    text = ""
                }
                let suggestion = classifier.suggestTags(for: text, fileName: fileName)

                record.extractedText = text
                record.suggestedTags = suggestion.tags
                record.indexedAt = .now
                try context.save()
            }

            state = .complete(indexed: indexedCount)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var hasPhotoAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    private func fetchScreenshotAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtype & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private func refreshExistingRecords(_ records: [ScreenshotRecord]) {
        guard !records.isEmpty else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: records.map(\.localIdentifier), options: nil)
        var fileNamesByID: [String: String] = [:]
        assets.enumerateObjects { asset, _, _ in
            fileNamesByID[asset.localIdentifier] = asset.fileName
        }

        for record in records {
            if let fileName = fileNamesByID[record.localIdentifier] {
                record.fileName = fileName
            }

            let suggestion = classifier.suggestTags(for: record.extractedText, fileName: record.displayFileName)
            record.suggestedTags = suggestion.tags.filter { tag in
                !record.userTags.contains(tag) && !record.hiddenSuggestedTags.contains(tag)
            }
        }
    }

    private func extractText(in image: UIImage) async -> String {
        if let text = try? await recognizeText(in: image), !text.isEmpty {
            return text
        }

        if let text = try? await analyzeLiveText(in: image), !text.isEmpty {
            return text
        }

        return ""
    }

    private nonisolated func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }

        return try await Task.detached(priority: .userInitiated) {
            if #available(iOS 18.0, *) {
                var request = RecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true

                let observations = try await request.perform(on: cgImage)
                let recognizedText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                if !recognizedText.isEmpty {
                    return recognizedText
                }
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            return request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
        }.value
    }

    private func analyzeLiveText(in image: UIImage) async throws -> String {
        guard #available(iOS 16.0, *), ImageAnalyzer.isSupported else { return "" }

        var configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
        configuration.locales = ImageAnalyzer.supportedTextRecognitionLanguages

        let analysis = try await ImageAnalyzer().analyze(image, configuration: configuration)
        return analysis.transcript
    }
}

private extension PHAsset {
    var fileName: String {
        if let fileName = value(forKey: "filename") as? String, !fileName.isEmpty {
            return fileName
        }

        if let creationDate {
            return "Screenshot \(creationDate.formatted(date: .numeric, time: .shortened))"
        }

        return "Screenshot"
    }
}

extension ScreenshotIndexer.State {
    var isIndexing: Bool {
        if case .indexing = self { return true }
        if case .requestingAccess = self { return true }
        return false
    }
}
