import SwiftUI
import SwiftData

@main
struct ShottyApp: App {
    private let appState = AppLaunchState.make()

    var body: some Scene {
        WindowGroup {
            switch appState {
            case let .ready(modelContainer):
                ContentView()
                    .tint(.primary)
                    .modelContainer(modelContainer)

            case let .failed(errorDescription):
                StartupFailureView(errorDescription: errorDescription)
            }
        }
    }
}

private enum AppLaunchState {
    case ready(ModelContainer)
    case failed(String)

    static func make() -> AppLaunchState {
        AppPreferences.registerDefaults()
        createApplicationSupportDirectory()

        do {
            return .ready(try ModelContainer(for: ScreenshotRecord.self))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func createApplicationSupportDirectory() {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }
}

private struct StartupFailureView: View {
    let errorDescription: String

    var body: some View {
        ContentUnavailableView(
            "Shotty Could Not Start",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("The local screenshot index could not be opened. Existing on-device data was left untouched.\n\n\(errorDescription)")
        )
        .padding()
    }
}
