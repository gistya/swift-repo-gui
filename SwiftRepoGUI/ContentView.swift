import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct ContentView: View {
    @State private var session = AppSession()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            List(AppSectionID.allCases, selection: Binding(
                get: { session.selectedSection },
                set: { if let section = $0 { session.selectSection(section) } }
            )) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch session.selectedSection {
            case .build:
                DashboardView(
                    session: session,
                    project: session.project,
                    settings: session.settings,
                    build: session.build
                )
            case .settings:
                BuildSettingsView(settings: session.settings)
            case .history:
                HistoryView(session: session)
            case .logs:
                LiveLogView(build: session.build)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            session.attach(modelContext: modelContext)
        }
        .onChange(of: session.settings.context) {
            session.persistLastUsedSettings()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BuildOperationRecord.self, SavedBuildProfile.self], inMemory: true)
}
