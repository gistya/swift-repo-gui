import SwiftRepoCore
import SwiftUI

struct TerminalTabButton: View {
    let section: AppSectionID
    let isSelected: Bool
    let onSelect: (AppSectionID) -> Void
    let onDetach: (AppSectionID) -> Void
    @State private var dragArmed = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        // A plain (non-Button) surface: on macOS a Button's built-in press tracking swallows a
        // `.gesture(DragGesture)` so `onChanged` never streams (you'd only get `onEnded`), which is
        // why the dragged tab used to be invisible until release. One DragGesture drives everything —
        // a near-zero move is a click (select); a real drag offsets the tab live and can tear off.
        Label(section.title.uppercased(), systemImage: section.symbolName)
            .font(.monaco(size: 12, weight: .bold))
            .foregroundStyle(isSelected ? Color.terminalGreen : Color.terminalGreen.opacity(0.42))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: 118)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 7)
                    .fill(Color.tabFill.opacity(isSelected ? 0.72 : 0.42))
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 7)
                            .stroke(isSelected ? Color.terminalGreen.opacity(0.9) : Color.terminalGreen.opacity(0.25), lineWidth: 1)
                    }
                    .shadow(color: isSelected ? Color.terminalGreen.opacity(0.45) : .clear, radius: 8)
            }
            .contentShape(Rectangle())
            .offset(dragOffset)
            .overlay(alignment: .topLeading) {
                if dragArmed {
                    detachedWindowPreview
                        .offset(x: dragOffset.width + 8, y: dragOffset.height + 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .topLeading)))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(dragArmed ? 1.04 : 1)
            .zIndex(dragArmed ? 10 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.74), value: dragArmed)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragOffset = value.translation
                        dragArmed = abs(value.translation.height) > 18 || abs(value.translation.width) > 40
                    }
                    .onEnded { value in
                        let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                        let shouldDetach = abs(value.translation.height) > 44 || abs(value.translation.width) > 160
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            dragArmed = false
                            dragOffset = .zero
                        }
                        if shouldDetach {
                            onDetach(section)
                        } else if !moved {
                            onSelect(section)
                        }
                    }
            )
            .help("Click to open \(section.title); drag away to open it in a separate window")
            // Accessibility: keep button semantics even though this is no longer a `Button`. Announce
            // the natural-case title + selected state (the visible label is uppercased, which
            // VoiceOver reads letter-by-letter), and route activation back to `onSelect`.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(section.title)
            .accessibilityHint("Shows the \(section.title) tab. Drag away to open it in its own window.")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelect(section) }
    }

    private var detachedWindowPreview: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [
                        Color.terminalButtonTop.opacity(0.96),
                        Color.terminalBlack.opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.terminalGreen.opacity(0.82), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: section.symbolName)
                    Text(section.title.uppercased())
                }
                .font(.monaco(size: 11, weight: .bold))
                .foregroundStyle(Color.terminalGreen)
                .padding(10)
            }
            .shadow(color: Color.swiftOrange.opacity(0.35), radius: 16)
            .shadow(color: Color.terminalGreen.opacity(0.32), radius: 12)
            .frame(width: dragArmed ? 190 : 120, height: dragArmed ? 126 : 42)
    }
}
