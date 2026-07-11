import Photos
import SwiftData
import SwiftUI
import UIKit

struct ScreenshotDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: ScreenshotRecord

    @State private var image: UIImage?
    @State private var isShowingFullscreenImage = false
    @State private var newTag = ""
    @State private var copiedText = false
    @State private var isShowingDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        List {
            screenshotPreview
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section("Details") {
                LabeledContent("File", value: record.displayFileName)
                LabeledContent("Captured", value: record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Indexed", value: record.indexedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Size", value: "\(record.pixelWidth) by \(record.pixelHeight)")
            }

            Section("Your Tags") {
                EditableTagList(tags: record.userTags, emptyText: "No tags yet.") { tag in
                    removeUserTag(tag)
                }

                HStack(spacing: 8) {
                    TextField("Add tag", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addTag)

                    Button("Add", action: addTag)
                        .buttonStyle(.bordered)
                        .disabled(normalizedNewTag.isEmpty)
                }
            }

            if !record.visibleSuggestedTags.isEmpty {
                Section("Suggested Tags") {
                    SuggestedTagList(tags: record.visibleSuggestedTags) { tag in
                        acceptSuggestedTag(tag)
                    } onHide: { tag in
                        hideSuggestedTag(tag)
                    }
                }
            }

            Section {
                Text(record.extractedText.isEmpty ? "No text detected." : record.extractedText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                HStack {
                    Text("Extracted Text")
                    Spacer()
                    Button(copiedText ? "Copied" : "Copy", action: copyExtractedText)
                        .font(.caption)
                        .disabled(record.extractedText.isEmpty)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(record.displayFileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete Screenshot", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete Screenshot?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Screenshot", role: .destructive) {
                Task { await deleteScreenshotAndIndex() }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the screenshot from Photos and deletes its local index in this app.")
        }
        .alert("Could Not Delete Screenshot", isPresented: deleteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "The screenshot could not be deleted.")
        }
        .task(id: record.localIdentifier) {
            await loadImage()
        }
        .fullScreenCover(isPresented: $isShowingFullscreenImage) {
            FullscreenScreenshotView(image: image)
        }
    }

    private var screenshotPreview: some View {
        Button {
            isShowingFullscreenImage = true
        } label: {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 320, maxHeight: 520)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open screenshot fullscreen")
    }

    private func loadImage() async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }

        image = await PhotoImageLoader.image(
            for: asset,
            targetSize: CGSize(width: 1200, height: 1600)
        )
    }

    private var normalizedNewTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { isPresented in
                if !isPresented {
                    deleteError = nil
                }
            }
        )
    }

    private func addTag() {
        let tag = normalizedNewTag
        guard !tag.isEmpty, !record.userTags.contains(tag) else { return }

        record.userTags.append(tag)
        record.userTags.sort()
        record.suggestedTags.removeAll { $0 == tag }
        record.hiddenSuggestedTags.removeAll { $0 == tag }
        newTag = ""
        try? modelContext.save()
    }

    private func removeUserTag(_ tag: String) {
        record.userTags.removeAll { $0 == tag }
        try? modelContext.save()
    }

    private func acceptSuggestedTag(_ tag: String) {
        guard !record.userTags.contains(tag) else { return }

        record.userTags.append(tag)
        record.userTags.sort()
        record.suggestedTags.removeAll { $0 == tag }
        record.hiddenSuggestedTags.removeAll { $0 == tag }
        try? modelContext.save()
    }

    private func hideSuggestedTag(_ tag: String) {
        record.suggestedTags.removeAll { $0 == tag }
        if !record.hiddenSuggestedTags.contains(tag) {
            record.hiddenSuggestedTags.append(tag)
            record.hiddenSuggestedTags.sort()
        }
        try? modelContext.save()
    }

    private func copyExtractedText() {
        UIPasteboard.general.string = record.extractedText
        copiedText = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                copiedText = false
            }
        }
    }

    private func deleteScreenshotAndIndex() async {
        let localIdentifier = record.localIdentifier
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)

        do {
            if let asset = assets.firstObject {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets([asset] as NSArray)
                }
            }

            modelContext.delete(record)
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct EditableTagList: View {
    let tags: [String]
    let emptyText: String
    let onRemove: (String) -> Void

    var body: some View {
        if tags.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            onRemove(tag)
                        } label: {
                            TagChip(title: tag, tone: .owned, accessorySystemImage: "xmark")
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

private struct SuggestedTagList: View {
    let tags: [String]
    let onAccept: (String) -> Void
    let onHide: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Button {
                            onAccept(tag)
                        } label: {
                            TagChip(title: tag, tone: .suggested, accessorySystemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityLabel("Accept suggested tag \(tag)")

                        Button {
                            onHide(tag)
                        } label: {
                            Image(systemName: "eye.slash")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color(.secondarySystemBackground), in: Circle())
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityLabel("Hide suggested tag \(tag)")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

private struct FullscreenScreenshotView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage?

    @State private var scale = 1.0
    @State private var lastScale = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { proxy in
                    zoomableImage(image, in: proxy.size)
                }
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .simultaneousGesture(dismissGesture)
    }

    private func zoomableImage(_ image: UIImage, in containerSize: CGSize) -> some View {
        let fittedSize = fittedImageSize(image.size, in: containerSize)
        let activeOffset = clampedOffset(
            CGSize(width: offset.width + dragPreview.width, height: offset.height + dragPreview.height),
            imageSize: fittedSize,
            containerSize: containerSize,
            scale: scale
        )

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: containerSize.width, height: containerSize.height)
            .scaleEffect(scale)
            .offset(activeOffset)
            .contentShape(Rectangle())
            .gesture(zoomGesture(imageSize: fittedSize, containerSize: containerSize))
            .simultaneousGesture(panGesture(imageSize: fittedSize, containerSize: containerSize))
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.22)) {
                    if scale > 1.01 {
                        resetZoom()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }

    @GestureState private var dragPreview = CGSize.zero

    private func zoomGesture(imageSize: CGSize, containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 6)
                offset = clampedOffset(offset, imageSize: imageSize, containerSize: containerSize, scale: scale)
            }
            .onEnded { _ in
                if scale < 1.05 {
                    withAnimation(.snappy(duration: 0.22)) {
                        resetZoom()
                    }
                } else {
                    lastScale = scale
                    lastOffset = clampedOffset(offset, imageSize: imageSize, containerSize: containerSize, scale: scale)
                    offset = lastOffset
                }
            }
    }

    private func panGesture(imageSize: CGSize, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragPreview) { value, state, _ in
                guard scale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1 else { return }

                let proposedOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposedOffset, imageSize: imageSize, containerSize: containerSize, scale: scale)
                lastOffset = offset
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard scale <= 1.01 else { return }

                let isMostlyVertical = abs(value.translation.height) > abs(value.translation.width)
                let movedDown = value.translation.height > 120 || value.predictedEndTranslation.height > 220

                if isMostlyVertical && movedDown {
                    dismiss()
                }
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func fittedImageSize(_ imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)

        return CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
    }

    private func clampedOffset(
        _ proposedOffset: CGSize,
        imageSize: CGSize,
        containerSize: CGSize,
        scale: Double
    ) -> CGSize {
        guard scale > 1 else { return .zero }

        let maxX = max((imageSize.width * scale - containerSize.width) / 2, 0)
        let maxY = max((imageSize.height * scale - containerSize.height) / 2, 0)

        return CGSize(
            width: min(max(proposedOffset.width, -maxX), maxX),
            height: min(max(proposedOffset.height, -maxY), maxY)
        )
    }
}
