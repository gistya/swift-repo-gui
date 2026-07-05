import SwiftUI

struct DetachedSectionWindow: View {
    let session: AppSession
    let section: AppSectionID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(
                build: session.build,
                soundtrackDeck: nil
            )
            ZStack {
                TerminalBackground()
                    .ignoresSafeArea()
                AppSectionContent(session: session, section: section)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .tint(.terminalGreen)
        .buttonStyle(RetroMetalButtonStyle())
        .onAppear {
            session.attach(modelContext: modelContext)
        }
    }
}
