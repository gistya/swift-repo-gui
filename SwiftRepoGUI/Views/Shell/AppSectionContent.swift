import SwiftUI
import SwiftXStateInspectorUI

struct AppSectionContent: View {
    let session: AppSession
    let section: AppSectionID

    var body: some View {
        switch section {
        case .build:
            DashboardView(
                session: session,
                project: session.project,
                settings: session.settings,
                build: session.build
            )
        case .settings:
            BuildSettingsView(settings: session.settings)
        case .toolchain:
            ToolchainView(session: session)
        case .history:
            HistoryView(session: session)
        case .logs:
            LiveLogView(build: session.build)
        case .inspector:
            MachineInspectorView(store: session.inspector)
                .inspectorStyle(.dark)
        case .style:
            StyleView(session: session)
        }
    }
}
