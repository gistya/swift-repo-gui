import Ox0badf00dAVFoundation
import SwiftUI

struct InsertRackPopup: View {
    let slots: [SoundtrackInsertSlot]
    let availableEffects: [AudioComponentRef]
    let onSetInsert: (Int, AudioComponentRef?) -> Void
    let onToggleBypass: (Int) -> Void
    let makeInsertEditor: (Int) async -> NSViewController?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.swiftOrange)
                    .shadow(color: Color.swiftOrange.opacity(0.7), radius: 6)
                    .accessibilityHidden(true)
                Text("EFFECT INSERTS")
                    .font(.monaco(size: 15, weight: .black))
                    .foregroundStyle(Color.terminalGreen)
                Spacer()
            }

            VStack(spacing: 10) {
                ForEach(slots.indices, id: \.self) { index in
                    slotRow(index)
                }
            }

            HStack {
                Text(availableEffects.isEmpty ? "Scanning AudioUnits…" : "\(availableEffects.count) effects available")
                    .font(.monaco(size: 9, weight: .bold))
                    .foregroundStyle(Color.terminalDimGreen)
                Spacer()
                Text("OX0BADF00D → LIMITER")
                    .font(.monaco(size: 9, weight: .black))
                    .foregroundStyle(Color.terminalDimGreen)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background {
            ZStack {
                Color.terminalBlack
                LinearGradient(
                    colors: [
                        Color.swiftOrange.opacity(0.14),
                        Color.terminalGreen.opacity(0.07),
                        Color.black.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                BrushedMetalLines()
                    .opacity(0.07)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.swiftOrange.opacity(0.5), lineWidth: 1)
        }
    }

    /// Opens the AU's own editor in a real floating macOS window. Re-opening a slot reveals the window
    /// already up; a slot with no assigned insert does nothing.
    private func openEditor(_ index: Int) {
        guard slots.indices.contains(index), let component = slots[index].component else { return }
        let title = component.name
        if AudioUnitEditorWindowManager.shared.reveal(slot: index) { return }
        Task {
            let controller: NSViewController = await makeInsertEditor(index)
                ?? NSHostingController(rootView: NoPluginInterfaceView(title: title))
            AudioUnitEditorWindowManager.shared.show(slot: index, title: title, controller: controller)
        }
    }

    private func slotRow(_ index: Int) -> some View {
        let slot = slots[index]
        return HStack(spacing: 8) {
            Text("INS \(index + 1)")
                .font(.monaco(size: 10, weight: .black))
                .foregroundStyle(Color.terminalGreen)
                .frame(width: 40, alignment: .leading)

            TerminalMenu<AudioComponentRef?>(
                selection: slot.component,
                options: [TerminalMenuOption<AudioComponentRef?>(nil, "— None —")]
                    + availableEffects.map { TerminalMenuOption<AudioComponentRef?>($0, $0.name) },
                onSelect: { component in
                    onSetInsert(index, component)
                    AudioUnitEditorWindowManager.shared.close(slot: index)
                },
                placeholder: "— empty —"
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Effect insert \(index + 1)")

            SoundtrackIconButton(
                systemName: slot.isBypassed ? "circle.slash" : "circle.fill",
                help: slot.isBypassed ? "Enable insert" : "Bypass insert",
                isNotEngaged: !(!slot.isBypassed && !slot.isEmpty),
                isDisabled: slot.isEmpty,
                action: { onToggleBypass(index) }
            )
            SoundtrackIconButton(
                systemName: "slider.horizontal.below.rectangle",
                help: "Open plugin editor",
                isNotEngaged: false,
                isDisabled: slot.isEmpty,
                action: { openEditor(index) }
            )
        }
        .opacity(slot.isBypassed ? 0.6 : 1)
    }
}
