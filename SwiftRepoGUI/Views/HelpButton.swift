import SwiftUI

struct HelpButton: View {
    let descriptor: BuildOptionDescriptor

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(descriptor.title)
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(descriptor.title)
                    .font(.headline)
                Text(descriptor.summary)
                    .font(.subheadline)
                Divider()
                Text("Why it matters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(descriptor.practicalAdvice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 320)
        }
    }
}