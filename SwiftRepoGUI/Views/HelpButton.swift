import SwiftUI

struct HelpButton: View {
    let descriptor: BuildOptionDescriptor

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Color.terminalGreen.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help(descriptor.title)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(descriptor.title)
                    .font(.monaco(size: 13, weight: .bold))
                Text(descriptor.summary)
                    .font(.monaco(size: 12))
                Divider()
                Text("Why it matters")
                    .font(.monaco(size: 11, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
                Text(descriptor.practicalAdvice)
                    .font(.monaco(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 320)
            .background(TerminalBackground())
            .terminalText()
        }
    }
}
