import SwiftUI

struct AddLayerSheet: View {
    let catalog: [ParsedPreset]
    let customPresets: [CustomPresetValue]
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var customNames: [String] { customPresets.map(\.name).sorted() }
    private var composed: [ParsedPreset] { filtered(catalog.filter { !$0.isMixin }) }
    private var mixins: [ParsedPreset] { filtered(catalog.filter { $0.isMixin }) }

    private func filtered(_ list: [ParsedPreset]) -> [ParsedPreset] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) }).sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADD LAYER").font(.monaco(size: 14, weight: .black)).foregroundStyle(Color.terminalGreen)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("Filter presets & mixins…", text: $search).textFieldStyle(.roundedBorder).font(.monaco(size: 11))
            List {
                if !customNames.isEmpty {
                    Section("Your custom") {
                        ForEach(customNames.filter { search.isEmpty || $0.lowercased().contains(search.lowercased()) }, id: \.self) { row($0, tag: "custom") }
                    }
                }
                Section("Mixins (\(mixins.count))") { ForEach(mixins) { row($0.name, tag: "mixin") } }
                Section("Composed presets (\(composed.count))") { ForEach(composed) { row($0.name, tag: nil) } }
            }
            .listStyle(.inset)
        }
        .padding(16)
        .frame(width: 520, height: 560)
        .background(TerminalBackground())
        .terminalText()
    }

    private func row(_ name: String, tag: String?) -> some View {
        Button { onAdd(name); dismiss() } label: {
            HStack {
                Text(name).font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen)
                if let tag { Text(tag).font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.swiftOrange) }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(Color.lcdGreen.opacity(0.7))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
