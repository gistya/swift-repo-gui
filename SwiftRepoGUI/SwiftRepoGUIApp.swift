import AppKit
import SwiftUI
import SwiftData
import OSLog

@main
struct SwiftRepoGUIApp: App {
    // `AppSession.shared` (a lazily-created `static let`) is constructed exactly once, so re-inits of
    // this App struct can't spin up extra audio engines. See `AppSession.shared`.
    @State private var session = AppSession.shared
    private var log: Logger = .init(subsystem: "app", category: "log")
    
    init() {
        log.debug("initializing app")
    }

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
