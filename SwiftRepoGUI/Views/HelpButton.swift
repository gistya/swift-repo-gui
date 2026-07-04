import SwiftUI

/// Anything that can populate a `HelpButton` popover — a build-setting option or an action button.
protocol HelpDescribing {
    var title: String { get }
    var summary: String { get }
    var practicalAdvice: String { get }
}

struct HelpButton: View {
    let descriptor: any HelpDescribing

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
