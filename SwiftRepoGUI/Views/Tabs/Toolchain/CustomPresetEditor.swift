import SwiftUI

struct CustomPresetEditor: View {
    let existing: CustomPresetValue?
    let onSave: (CustomPresetValue) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var mixinsText: String = ""
    @State private var optionsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(existing == nil ? "NEW CUSTOM PRESET" : "EDIT CUSTOM PRESET")
                .font(.monaco(size: 14, weight: .black)).foregroundStyle(Color.terminalGreen)
                .accessibilityLabel(existing == nil ? "New Custom Preset" : "Edit Custom Preset")
                .accessibilityAddTraits(.isHeader)
            field("Name (e.g. mixin_my_asserts)", text: $name)
                .accessibilityLabel("Preset name")
            Text("mixin-preset names (one per line):").font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.7))
                .accessibilityHidden(true)
            editor($mixinsText)
                .accessibilityLabel("Mixin-preset names")
                .accessibilityHint("Enter mixin-preset names, one per line")
            Text("option lines (bare flag or key=value):").font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.7))
                .accessibilityHidden(true)
            editor($optionsText)
                .accessibilityLabel("Option lines")
                .accessibilityHint("Enter option lines, one per line, as a bare flag or key equals value")
            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityHint("Closes the editor without saving")
                Spacer()
                Button("Save") {
                    onSave(CustomPresetValue(
                        id: existing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        mixins: lines(mixinsText),
                        optionLines: lines(optionsText)
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityHint("Saves this custom preset")
            }
        }
        .padding(16)
        .frame(width: 480, height: 460)
        .background(TerminalBackground())
        .terminalText()
        .onAppear {
            name = existing?.name ?? ""
            mixinsText = (existing?.mixins ?? []).joined(separator: "\n")
            optionsText = (existing?.optionLines ?? []).joined(separator: "\n")
        }
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.monaco(size: 11))
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.monaco(size: 11)).foregroundStyle(Color.lcdGreen).scrollContentBackground(.hidden)
            .frame(minHeight: 70)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.terminalGreen.opacity(0.3), lineWidth: 1)))
    }
}
