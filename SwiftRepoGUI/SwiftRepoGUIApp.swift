import AppKit
import SwiftUI
import SwiftData

@main
struct SwiftRepoGUIApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BuildOperationRecord.self,
            SavedBuildProfile.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Logs Folder") {
                    NSWorkspace.shared.open(AppPaths.logsDirectory)
                }
                Button("Open Exports Folder") {
                    NSWorkspace.shared.open(AppPaths.exportsDirectory)
                }
            }
        }
    }
}