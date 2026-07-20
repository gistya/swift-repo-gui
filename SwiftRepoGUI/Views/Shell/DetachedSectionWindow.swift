import SwiftData
import SwiftUI

struct DetachedSectionWindow: View {
    let session: AppSession
    let section: AppSectionID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // A torn-off tab shows ONLY its section content — no retro title bar (LED/LCD/music/brand).
        ZStack {
            TerminalBackground()
                .ignoresSafeArea()
                .accessibilityHidden(true)
            AppSectionContent(session: session, section: section)
        }
        .frame(minWidth: 960, minHeight: 520)
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .tint(.terminalGreen)
        .buttonStyle(RetroMetalButtonStyle())
        .navigationTitle(section.title)
        .onAppear {
            session.attach(modelContext: modelContext)
            // Hide this section's tab from the main window while its own window is open.
            session.markDetached(section)
        }
        .onDisappear {
            // Window closed → its tab returns to the main bar.
            session.markAttached(section)
        }
    }
}
