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

    private var filteredCustomNames: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? customNames : customNames.filter { $0.lowercased().contains(q) }
    }

    private func filtered(_ list: [ParsedPreset]) -> [ParsedPreset] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) }).sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADD LAYER").font(.monaco(size: 14, weight: .black)).foregroundStyle(Color.terminalGreen)
                    .accessibilityLabel("Add Layer")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .accessibilityHint("Closes without adding a layer")
            }
            TextField("Filter presets & mixins…", text: $search).textFieldStyle(.roundedBorder).font(.monaco(size: 11))
                .accessibilityLabel("Filter presets and mixins")
                .accessibilityHint("Type to narrow the list below")
            // Rendered as a ScrollView + LazyVStack instead of a `List`, because macOS `List` draws
            // its own material behind section headers that no `.background()` can override. Here the
            // headers are ordinary views, so their background is fully under our control.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !filteredCustomNames.isEmpty {
                        Section {
                            ForEach(filteredCustomNames, id: \.self) { row($0, tag: "custom") }
                        } header: {
                            sectionHeader("Your custom")
                        }
                    }
                    Section {
                        ForEach(mixins) { row($0.name, tag: "mixin") }
                    } header: {
                        sectionHeader("Mixins (\(mixins.count))")
                    }
                    Section {
                        ForEach(composed) { row($0.name, tag: nil) }
                    } header: {
                        sectionHeader("Composed presets (\(composed.count))")
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 520, height: 560)
        .background(TerminalBackground())
        .terminalText()
    }

    /// A section header whose background is fully controllable (a plain view, not a `List` header).
    /// The header is pinned to the top while scrolling, so its background must be OPAQUE — a
    /// translucent color would let the scrolling rows show through it.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.monaco(size: 10, weight: .bold))
            .foregroundStyle(Color.terminalGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(white: 0.86)) // ← header background: set this to whatever color you want
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ name: String, tag: String?) -> some View {
        Button { onAdd(name); dismiss() } label: {
            HStack {
                Text(name).font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen)
                if let tag { Text(tag).font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.swiftOrange) }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(Color.lcdGreen.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(tag == nil ? "Add \(name)" : "Add \(name), \(tag!)")
        .accessibilityHint("Adds this layer and closes the picker")
    }
}

#Preview {
    AddLayerSheet(catalog: [.init(name: "Preset", mixins: ["mixin", "mixin"],
                     options: [.init(name: "asdf", value: "asdf")])],
     customPresets: [.init(name: "asdf")],
     onAdd: {_ in })
}
