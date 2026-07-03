import SwiftUI
#if canImport(AppKit)
import AppKit

/// Hosts an AudioUnit's own editor view controller in a sheet. The controller is requested lazily
/// from the audio engine (`makeController`) when the sheet appears and released when it closes, so
/// the app never holds a reference to the live AU across presentations.
struct AudioUnitEditorSheet: View {
    let slotIndex: Int
    let title: String
    let makeController: (Int) async -> NSViewController?

    @Environment(\.dismiss) private var dismiss
    @State private var controller: NSViewController?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.monaco(size: 12, weight: .black))
                    .foregroundStyle(Color.terminalGreen)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            Divider()

            Group {
                if let controller {
                    AUViewControllerHost(controller: controller)
                } else if isLoading {
                    ProgressView("Loading plugin UI…")
                        .controlSize(.small)
                        .padding(40)
                } else {
                    Text("This AudioUnit has no custom interface.")
                        .font(.monaco(size: 11))
                        .foregroundStyle(Color.terminalDimGreen)
                        .padding(40)
                }
            }
            .frame(minWidth: 440, minHeight: 280)
        }
        .frame(minWidth: 480)
        .background(Color.terminalBlack)
        .task {
            controller = await makeController(slotIndex)
            isLoading = false
        }
    }
}

private struct AUViewControllerHost: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#endif
