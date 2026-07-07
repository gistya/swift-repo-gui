import SwiftUI

/// A drop-in replacement for SwiftUI `Menu`/`Picker` whose popup honors the retro-terminal theme
/// (Monaco font, terminal-green on black), since native macOS menu/picker popups can't be font/color
/// themed. Shows the current selection as a themed button; tapping opens a themed, scrollable list.
struct TerminalMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }

    init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }
}

struct TerminalMenu<Value: Hashable>: View {
    let selection: Value
    let options: [TerminalMenuOption<Value>]
    let onSelect: (Value) -> Void
    var placeholder: String = "—"
    var width: CGFloat? = nil

    @State private var isOpen = false

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? placeholder
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .font(.monaco(size: 11, weight: .bold))
                    .foregroundStyle(Color.lcdGreen)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.controlSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.terminalGreen.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selection")
        .accessibilityValue(selectedLabel)
        .accessibilityHint("Opens a menu.")
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(options) { option in
                        TerminalMenuRow(
                            label: option.label,
                            isSelected: option.value == selection
                        ) {
                            onSelect(option.value)
                            isOpen = false
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: max(width ?? 220, 200), maxHeight: 340)
            .background(TerminalBackground())
        }
    }
}

private struct TerminalMenuRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.lcdGreen)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.monaco(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.lcdGreen : Color.terminalGreen)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.terminalGreen.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
    }
}
