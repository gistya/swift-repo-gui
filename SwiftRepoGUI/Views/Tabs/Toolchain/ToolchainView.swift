import Matrix
import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct ToolchainView: View {
    let session: AppSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToolchainRecipe.updatedAt, order: .reverse) private var recipes: [ToolchainRecipe]
    @Query(sort: \CustomPreset.name) private var customPresets: [CustomPreset]

    @State private var showAddLayer = false
    @State private var editingCustom: CustomPreset?
    @State private var showNewCustom = false

    private var store: MachineStore<ToolchainMachine> { session.toolchain }
    private var draft: ToolchainRecipeDraft { store.context.draft }
    private var isBuilding: Bool { session.build.matches(.running) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recipeBar
                if store.matches(.failed) {
                    banner(store.context.lastError ?? "build-presets.ini could not be read.", isError: true)
                } else if store.matches(.loading) {
                    HStack(spacing: 8) {
                        MatrixLoader(.fun(.snake), size: 30.0, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
                        Text("Parsing build-presets.ini…").foregroundStyle(Color.terminalGreen.opacity(0.75))
                    }
                }
                identitySection
                flagsSection
                layersSection
                overridesSection
                customPresetsSection
                previewSection
                buildBar
            }
            .padding(18)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .onAppear { session.loadToolchainCatalog() }
        .onChange(of: session.project.context.projectInfo?.swiftDirectory) { session.loadToolchainCatalog() }
        .sheet(isPresented: $showAddLayer) {
            AddLayerSheet(catalog: store.context.catalog, customPresets: customPresets.map(\.value)) { name in
                mutate { $0.selectedMixins.append(name) }
            }
        }
        .sheet(isPresented: $showNewCustom) {
            CustomPresetEditor(existing: nil) { value in
                modelContext.insert(CustomPreset(name: value.name, mixins: value.mixins, optionLines: value.optionLines))
            }
        }
        .sheet(item: $editingCustom) { preset in
            CustomPresetEditor(existing: preset.value) { value in preset.apply(value) }
        }
    }

    // MARK: Sections

    private var recipeBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill").foregroundStyle(Color.swiftOrange)
            Text("TOOLCHAIN BUILDER").font(.monaco(size: 16, weight: .black))
            Spacer()
            if !recipes.isEmpty {
                TerminalMenu(
                    selection: draft.recipeID ?? UUID(),
                    options: recipes.map { TerminalMenuOption($0.id, $0.name) },
                    onSelect: { id in
                        if let recipe = recipes.first(where: { $0.id == id }) { store.send(.loadRecipe(recipe.draft)) }
                    },
                    placeholder: "Load recipe…",
                    width: 200
                )
            }
            Button("New") { store.send(.newRecipe) }
            Button("Save Recipe") { saveRecipe() }
            ActionHelpButton("action.buildToolchain")
        }
    }

    private var identitySection: some View {
        GroupBox("Identity") {
            VStack(alignment: .leading, spacing: 8) {
                labeledField("Recipe name", text: fieldBinding(\.name))
                HStack(spacing: 4) {
                    labeledField("Bundle tag", text: fieldBinding(\.bundleTag), width: 180)
                    ActionHelpButton("action.toolchainTag")
                }
                HStack(spacing: 4) {
                    labeledField("Preset prefix", text: fieldBinding(\.presetPrefix), width: 180)
                    ActionHelpButton("action.presetPrefix")
                }
            }
            .padding(6)
        }
    }

    private var flagsSection: some View {
        GroupBox("build-toolchain flags") {
            VStack(alignment: .leading, spacing: 8) {
                let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(ToolchainFlag.allCases) { flag in
                        Toggle(flag.title, isOn: flagBinding(flag))
                            .font(.monaco(size: 11))
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    Text("Resolves to preset:").font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.7))
                    Text(ToolchainPresetWriter.composedPresetName(prefix: draft.presetPrefix, flags: draft.flags))
                        .font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                        .textSelection(.enabled)
                }
                Text("mixes in stock  \(ToolchainPresetWriter.stockBaseName(flags: draft.flags))  +  your layers below")
                    .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
            }
            .padding(6)
        }
    }

    private var layersSection: some View {
        GroupBox("Layered presets & mixins") {
            VStack(alignment: .leading, spacing: 8) {
                if draft.selectedMixins.isEmpty {
                    Text("No extra layers — just the stock toolchain preset. Add presets/mixins to compose.")
                        .font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                } else {
                    ForEach(Array(draft.selectedMixins.enumerated()), id: \.offset) { index, name in
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10)).foregroundStyle(Color.swiftOrange.opacity(0.8))
                            Text(name).font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                            if customPresets.contains(where: { $0.name == name }) {
                                Text("custom").font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.swiftOrange)
                            } else if !store.context.catalog.contains(where: { $0.name == name }) {
                                Text("unknown").font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.terminalFailureRed)
                            }
                            Spacer()
                            Button { mutate { $0.selectedMixins.remove(at: index) } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Color.terminalFailureRed.opacity(0.8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { showAddLayer = true } label: {
                    Label("Add layer…", systemImage: "plus.circle").font(.monaco(size: 11, weight: .bold))
                }
            }
            .padding(6)
        }
    }

    private var overridesSection: some View {
        GroupBox("Option overrides (win last)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("build-script long options, one per line — bare flag or key=value (no leading --).")
                    .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                TextEditor(text: extraOptionsBinding)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.lcdGreen)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.terminalGreen.opacity(0.3), lineWidth: 1)))
            }
            .padding(6)
        }
    }

    private var customPresetsSection: some View {
        GroupBox("Your custom presets & mixins") {
            VStack(alignment: .leading, spacing: 6) {
                if customPresets.isEmpty {
                    Text("Define reusable building blocks that show up in “Add layer”.")
                        .font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                }
                ForEach(customPresets) { preset in
                    HStack {
                        Text(preset.name).font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                        Text("\(preset.mixins.count) mixins · \(preset.optionLines.count) options")
                            .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                        Spacer()
                        Button("Add") { mutate { $0.selectedMixins.append(preset.name) } }
                        Button("Edit") { editingCustom = preset }
                        Button(role: .destructive) { modelContext.delete(preset) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { showNewCustom = true } label: {
                    Label("New custom preset…", systemImage: "plus.circle").font(.monaco(size: 11, weight: .bold))
                }
                ActionHelpButton("action.toolchainOverride")
            }
            .padding(6)
        }
    }

    private var previewSection: some View {
        GroupBox("Generated ~/\(draft.bundleTag)-presets.ini") {
            ScrollView(.vertical) {
                Text(ToolchainPresetWriter.overlay(draft: draft, customPresets: customPresets.map(\.value)))
                    .font(.monaco(size: 10))
                    .foregroundStyle(Color.terminalGreen.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(6)
        }
    }

    private var buildBar: some View {
        HStack {
            ActionHelpButton("action.basePresetFile")
            Spacer()
            Button {
                let current = draft
                Task { await session.buildToolchain(current) }
            } label: {
                Label("Build Toolchain", systemImage: "shippingbox.fill").font(.monaco(size: 13, weight: .bold))
            }
            .buttonStyle(RetroMetalButtonStyle())
            .disabled(isBuilding || !session.project.context.isValid)
        }
    }

    // MARK: Helpers

    private func banner(_ text: String, isError: Bool) -> some View {
        Text(text).font(.monaco(size: 11))
            .foregroundStyle(isError ? Color.terminalFailureRed : Color.terminalGreen)
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        HStack {
            Text(label).font(.monaco(size: 11, weight: .semibold)).foregroundStyle(Color.terminalGreen.opacity(0.8)).frame(width: 110, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.monaco(size: 11))
                .frame(width: width)
        }
    }

    private func mutate(_ change: (inout ToolchainRecipeDraft) -> Void) {
        var d = store.context.draft
        change(&d)
        store.send(.updateDraft(d))
    }

    private func fieldBinding(_ keyPath: WritableKeyPath<ToolchainRecipeDraft, String>) -> Binding<String> {
        Binding(get: { store.context.draft[keyPath: keyPath] }, set: { v in mutate { $0[keyPath: keyPath] = v } })
    }

    private func flagBinding(_ flag: ToolchainFlag) -> Binding<Bool> {
        Binding(
            get: { store.context.draft.flags.contains(flag) },
            set: { on in mutate { if on { $0.flags.insert(flag) } else { $0.flags.remove(flag) } } }
        )
    }

    private var extraOptionsBinding: Binding<String> {
        Binding(
            get: { store.context.draft.extraOptions.joined(separator: "\n") },
            set: { text in mutate { $0.extraOptions = text.components(separatedBy: .newlines) } }
        )
    }

    private func saveRecipe() {
        if let id = draft.recipeID, let existing = recipes.first(where: { $0.id == id }) {
            existing.draft = draft
        } else {
            let recipe = ToolchainRecipe(draft: draft)
            modelContext.insert(recipe)
            store.send(.loadRecipe(recipe.draft))
        }
    }
}
