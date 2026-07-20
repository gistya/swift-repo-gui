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
        FontLoader.registerFonts()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BuildOperationRecord.self,
            SavedBuildProfile.self,
            ToolchainRecipe.self,
            CustomPreset.self,
        ])
        // Pin an explicit, app-namespaced store URL. SwiftData's default store for an UNSANDBOXED
        // app is the un-namespaced ~/Library/Application Support/default.store — shared by every
        // SwiftData app on the machine, so sibling apps clobbered each other's data (why History and
        // Logs kept turning up empty). Our own file under the app's Application Support subdirectory
        // fixes that without relying on the App Sandbox, which can't run the Homebrew build tools.
        let modelConfiguration: ModelConfiguration
        
        do {
            let storeDirectory = try AppPaths.applicationSupportDirectory()
            
            modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeDirectory.appendingPathComponent("SwiftRepoGUI.store")
            )
        } catch let error {
            // TODO: use real logger
            print("Error caught: \(error)")
            
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

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
