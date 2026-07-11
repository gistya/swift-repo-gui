import Matrix
import SwiftRepoCore
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
    @State private var showUpdateCleanConfirm = false

    private var store: MachineStore<ToolchainMachine> { session.toolchain }
    private var draft: ToolchainRecipeDraft { store.context.draft }
    private var isBuilding: Bool { session.build.matches(.running) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recipeBar
                if store.matches(.failed) {
                    banner(store.context.lastError ?? NSLocalizedString("build-presets.ini could not be read.", comment: "Toolchain tab error banner when the presets file cannot be loaded"), isError: true)
                } else if store.matches(.loading) {
                    HStack(spacing: 8) {
                        MatrixLoader(.fun(.snake), size: 30.0, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
                            .accessibilityHidden(true)
                        Text("Parsing build-presets.ini…").foregroundStyle(Color.terminalGreen.opacity(0.75))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Parsing build-presets.ini")
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
                .accessibilityHidden(true)
            Text("TOOLCHAIN BUILDER").font(.monaco(size: 16, weight: .black))
                .accessibilityLabel("Toolchain Builder")
                .accessibilityAddTraits(.isHeader)
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
                .accessibilityLabel("Load saved recipe")
                .accessibilityHint("Choose a previously saved toolchain recipe to load its settings")
            }
            Button("New") { store.send(.newRecipe) }
                .accessibilityLabel("New recipe")
                .accessibilityHint("Clears the form to start a new toolchain recipe")
            Button("Save Recipe") { saveRecipe() }
                .accessibilityHint("Saves the current settings as a reusable recipe")
            ActionHelpButton("action.buildToolchain")
                .accessibilityLabel("Help about Build Toolchain")
        }
    }

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledField("Recipe name", text: fieldBinding(\.name))
                HStack(spacing: 4) {
                    labeledField("Bundle tag", text: fieldBinding(\.bundleTag), width: 180)
                    ActionHelpButton("action.toolchainTag")
                        .accessibilityLabel("Help about Toolchain Tag")
                }
                HStack(spacing: 4) {
                    labeledField("Preset prefix", text: fieldBinding(\.presetPrefix), width: 180)
                    ActionHelpButton("action.presetPrefix")
                        .accessibilityLabel("Help about Preset Prefix")
                }
            }
            .padding(6)
        } label: {
            Text("Identity").accessibilityAddTraits(.isHeader)
        }
    }

    private var flagsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(ToolchainFlag.allCases) { flag in
                        Toggle(flag.title, isOn: flagBinding(flag))
                            .font(.monaco(size: 11))
                            .accessibilityLabel(flag.title)
                            .accessibilityHint("Toggles the \(flag.title) build-toolchain flag")
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    Text("Resolves to preset:").font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.7))
                    Text(ToolchainPresetWriter.composedPresetName(prefix: draft.presetPrefix, flags: draft.flags))
                        .font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                Text("mixes in stock  \(ToolchainPresetWriter.stockBaseName(flags: draft.flags))  +  your layers below")
                    .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                    .accessibilityLabel("Mixes in stock \(ToolchainPresetWriter.stockBaseName(flags: draft.flags)) plus your layers below")
            }
            .padding(6)
        } label: {
            Text("build-toolchain flags").accessibilityAddTraits(.isHeader)
        }
    }

    private var layersSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if draft.selectedMixins.isEmpty {
                    Text("No extra layers — just the stock toolchain preset. Add presets/mixins to compose.")
                        .font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                } else {
                    ForEach(Array(draft.selectedMixins.enumerated()), id: \.offset) { index, name in
                        HStack {
                            HStack {
                                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10)).foregroundStyle(Color.swiftOrange.opacity(0.8))
                                    .accessibilityHidden(true)
                                Text(name).font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                                if customPresets.contains(where: { $0.name == name }) {
                                    Text("custom").font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.swiftOrange)
                                } else if !store.context.catalog.contains(where: { $0.name == name }) {
                                    Text("unknown").font(.monaco(size: 8, weight: .bold)).foregroundStyle(Color.terminalFailureRed)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(layerAccessibilityLabel(name))
                            Spacer()
                            Button { mutate { $0.selectedMixins.remove(at: index) } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Color.terminalFailureRed.opacity(0.8))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Remove layer \(name)")
                                .accessibilityHint("Removes this preset or mixin from the composed toolchain")
                        }
                    }
                }
                Button { showAddLayer = true } label: {
                    Label("Add layer…", systemImage: "plus.circle").font(.monaco(size: 11, weight: .bold))
                }
                .accessibilityLabel("Add layer")
                .accessibilityHint("Opens a picker to add a preset or mixin layer")
            }
            .padding(6)
        } label: {
            Text("Layered presets & mixins").accessibilityAddTraits(.isHeader)
        }
    }

    private func layerAccessibilityLabel(_ name: String) -> String {
        if customPresets.contains(where: { $0.name == name }) {
            return String(format: NSLocalizedString("%@, custom preset", comment: "Accessibility label for a layer row backed by a user-defined custom preset"), name)
        } else if !store.context.catalog.contains(where: { $0.name == name }) {
            return String(format: NSLocalizedString("%@, unknown preset", comment: "Accessibility label for a layer row whose preset is not found in the catalog"), name)
        }
        return name
    }

    private var overridesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("build-script long options, one per line — bare flag or key=value (no leading --).")
                    .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                TextEditor(text: extraOptionsBinding)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.lcdGreen)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.controlSurface.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.terminalGreen.opacity(0.3), lineWidth: 1)))
                    .accessibilityLabel("Option overrides")
                    .accessibilityHint("Enter build-script long options, one per line, as a bare flag or key equals value without leading dashes")
            }
            .padding(6)
        } label: {
            Text("Option overrides (win last)").accessibilityAddTraits(.isHeader)
        }
    }

    private var customPresetsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if customPresets.isEmpty {
                    Text("Define reusable building blocks that show up in “Add layer”.")
                        .font(.monaco(size: 11)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                }
                ForEach(customPresets) { preset in
                    HStack {
                        HStack {
                            Text(preset.name).font(.monaco(size: 11, weight: .bold)).foregroundStyle(Color.lcdGreen)
                            Text("\(preset.mixins.count) mixins · \(preset.optionLines.count) options")
                                .font(.monaco(size: 10)).foregroundStyle(Color.terminalGreen.opacity(0.6))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(preset.name), \(preset.mixins.count) mixins, \(preset.optionLines.count) options")
                        Spacer()
                        Button("Add") { mutate { $0.selectedMixins.append(preset.name) } }
                            .accessibilityLabel("Add \(preset.name)")
                            .accessibilityHint("Adds this custom preset as a layer")
                        Button("Edit") { editingCustom = preset }
                            .accessibilityLabel("Edit \(preset.name)")
                            .accessibilityHint("Opens the editor for this custom preset")
                        Button(role: .destructive) { modelContext.delete(preset) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(preset.name)")
                            .accessibilityHint("Permanently removes this custom preset")
                    }
                }
                Button { showNewCustom = true } label: {
                    Label("New custom preset…", systemImage: "plus.circle").font(.monaco(size: 11, weight: .bold))
                }
                .accessibilityLabel("New custom preset")
                .accessibilityHint("Opens the editor to define a reusable preset or mixin")
                ActionHelpButton("action.toolchainOverride")
                    .accessibilityLabel("Help about Toolchain Override Profile")
            }
            .padding(6)
        } label: {
            Text("Your custom presets & mixins").accessibilityAddTraits(.isHeader)
        }
    }

    private var previewSection: some View {
        GroupBox {
            ScrollView(.vertical) {
                Text(ToolchainPresetWriter.overlay(draft: draft, customPresets: customPresets.map(\.value)))
                    .font(.monaco(size: 10))
                    .foregroundStyle(Color.terminalGreen.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Generated preset file preview")
            }
            .frame(maxHeight: 220)
            .padding(6)
        } label: {
            Text("Generated ~/\(draft.bundleTag)-presets.ini").accessibilityAddTraits(.isHeader)
        }
    }

    private var buildBar: some View {
        HStack {
            ActionHelpButton("action.basePresetFile")
                .accessibilityLabel("Help about Base Preset File")
            Spacer()
            Button {
                showUpdateCleanConfirm = true
            } label: {
                Label("Update & Clean", systemImage: "trash.slash.circle").font(.monaco(size: 13, weight: .bold))
            }
            .buttonStyle(RetroMetalButtonStyle())
            .disabled(isBuilding || !session.project.context.isValid)
            .accessibilityLabel("Update and clean toolchain build tree")
            .accessibilityHint("Runs update-checkout on the sibling repos (your swift branch is left untouched), then deletes build/\(AppSession.toolchainBuildSubdir). No build is started.")
            .confirmationDialog("Update & Clean?", isPresented: $showUpdateCleanConfirm, titleVisibility: .visible) {
                Button("Update & Clean", role: .destructive) {
                    Task { await session.updateAndCleanBuildTree(subdir: AppSession.toolchainBuildSubdir) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This runs update-checkout to sync the sibling repos (your swift branch is left untouched), then DELETES build/\(AppSession.toolchainBuildSubdir). No build is started.")
            }
            Button {
                let current = draft
                Task { await session.buildToolchain(current) }
            } label: {
                Label("Build Toolchain", systemImage: "shippingbox.fill").font(.monaco(size: 13, weight: .bold))
            }
            .buttonStyle(RetroMetalButtonStyle())
            .disabled(isBuilding || !session.project.context.isValid)
            .accessibilityLabel("Build Toolchain")
            .accessibilityHint("Runs build-toolchain to produce an installable toolchain bundle")
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
                .accessibilityHidden(true)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.monaco(size: 11))
                .frame(width: width)
                .accessibilityLabel(label)
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
