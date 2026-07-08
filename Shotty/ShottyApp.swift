import SwiftUI
import SwiftData

@main
struct ShottyApp: App {
    private let modelContainer = ModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.primary)
        }
        .modelContainer(modelContainer)
    }
}

private enum ModelContainerFactory {
    static func make() -> ModelContainer {
        createApplicationSupportDirectory()

        do {
            return try ModelContainer(for: ScreenshotRecord.self)
        } catch {
            resetDefaultStore()
            return try! ModelContainer(for: ScreenshotRecord.self)
        }
    }

    private static func createApplicationSupportDirectory() {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    private static func resetDefaultStore() {
        let fileManager = FileManager.default

        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        for fileName in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fileManager.removeItem(at: supportDirectory.appendingPathComponent(fileName))
        }
    }
}
