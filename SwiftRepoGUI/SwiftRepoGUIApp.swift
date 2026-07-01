import AppKit
import SwiftUI
import SwiftData

@main
struct SwiftRepoGUIApp: App {
    @State private var session = AppSession()

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
            ContentView(session: session)
        }
        .modelContainer(sharedModelContainer)

        WindowGroup("SwiftBuilder Tab", for: AppSectionID.self) { $section in
            if let section {
                DetachedSectionWindow(session: session, section: section)
                    .modelContainer(sharedModelContainer)
            }
        }
        .defaultSize(width: 920, height: 680)

        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Logs Folder") {
                    AppFolderActions.openLogsFolder()
                }
                Button("Open Exports Folder") {
                    AppFolderActions.openExportsFolder()
                }
            }
        }
    }
}
