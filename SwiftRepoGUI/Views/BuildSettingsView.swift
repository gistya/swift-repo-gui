import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct BuildSettingsView: View {
    let settings: MachineStore<BuildSettingsMachine>
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedBuildProfile.updatedAt, order: .reverse) private var profiles: [SavedBuildProfile]

    @State private var profileName = ""
    @State private var showSaveSheet = false

    var body: some View {
        Form {
            if !profiles.isEmpty {
                Section("Saved Profiles") {
                    ForEach(profiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text(profile.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Load") { settings.send(.setOptions(profile.options)) }
                            Button(role: .destructive) {
                                modelContext.delete(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            ForEach(BuildOptionCategory.allCases) { category in
                Section(category.title) {
                    optionRows(for: category)
                }
            }

            Section {
                Button("Save Current Configuration…") { showSaveSheet = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Build Settings")
        .sheet(isPresented: $showSaveSheet) { saveProfileSheet }
    }

    @ViewBuilder
    private func optionRows(for category: BuildOptionCategory) -> some View {
        switch category {
        case .buildMode:
            boolRow("release")
            boolRow("releaseDebugInfo")
            boolRow("debug")
            boolRow("clean")
            boolRow("reconfigure")
            boolRow("assertions")
            boolRow("noAssertions")
        case .swiftComponents:
            boolRow("debugSwift")
            boolRow("debugSwiftStdlib")
            boolRow("debugLLVM")
            boolRow("skipBuildOSXStdlib")
        case .platformTargets:
            boolRow("skipBuildIOS")
            boolRow("skipBuildBenchmarks")
        case .performance:
            Stepper(value: settings.bind(\.options.jobs, send: { BuildSettingsEvent.setIntOption(key: "jobs", value: $0) }), in: 1...128) {
                HStack {
                    labeledRow("jobs")
                    Spacer()
                    Text("\(settings.context.options.jobs)")
                        .foregroundStyle(.secondary)
                }
            }
            boolRow("sccache")
            boolRow("distcc")
            boolRow("enableCaching")
            boolRow("lto")
            boolRow("ltoThin")
        case .sanitizers:
            boolRow("enableASAN")
            boolRow("enableUBSAN")
            boolRow("enableTSAN")
        case .testing:
            boolRow("test")
            boolRow("validationTests")
        case .installation:
            boolRow("swiftPM")
            boolRow("llbuild")
            boolRow("lldb")
            boolRow("swiftDriver")
            boolRow("installSwift")
            boolRow("installLLVM")
        case .advanced:
            boolRow("swiftDisableDeadStripping")
            boolRow("verboseBuild")
            boolRow("dryRun")
            presetPicker
            TextField(
                "Build subdirectory",
                text: settings.bind(\.options.buildSubdir, send: { BuildSettingsEvent.setStringOption(key: "buildSubdir", value: $0) })
            )
            TextField(
                "Extra arguments (one per line)",
                text: settings.bind(\.options.extraArguments, send: { BuildSettingsEvent.setStringOption(key: "extraArguments", value: $0) }),
                axis: .vertical
            )
            .lineLimit(3...8)
        }
    }

    private var presetPicker: some View {
        HStack {
            labeledRow("preset")
            Spacer()
            Picker(
                "Preset",
                selection: settings.bind(\.options.preset, send: { BuildSettingsEvent.setStringOption(key: "preset", value: $0) })
            ) {
                Text("None").tag("")
                Text("buildbot_incremental").tag("buildbot_incremental")
                Text("asan").tag("asan")
            }
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private func boolRow(_ id: String) -> some View {
        HStack {
            labeledRow(id)
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { boolValue(for: id) },
                    set: { settings.send(.setBoolOption(key: id, value: $0)) }
                )
            )
            .labelsHidden()
        }
    }

    private func boolValue(for id: String) -> Bool {
        let options = settings.context.options
        switch id {
        case "release": return options.release
        case "releaseDebugInfo": return options.releaseDebugInfo
        case "debug": return options.debug
        case "clean": return options.clean
        case "reconfigure": return options.reconfigure
        case "assertions": return options.assertions
        case "noAssertions": return options.noAssertions
        case "debugSwift": return options.debugSwift
        case "debugSwiftStdlib": return options.debugSwiftStdlib
        case "debugLLVM": return options.debugLLVM
        case "skipBuildOSXStdlib": return options.skipBuildOSXStdlib
        case "skipBuildIOS": return options.skipBuildIOS
        case "skipBuildBenchmarks": return options.skipBuildBenchmarks
        case "sccache": return options.sccache
        case "distcc": return options.distcc
        case "enableCaching": return options.enableCaching
        case "lto": return options.lto
        case "ltoThin": return options.ltoThin
        case "enableASAN": return options.enableASAN
        case "enableUBSAN": return options.enableUBSAN
        case "enableTSAN": return options.enableTSAN
        case "test": return options.test
        case "validationTests": return options.validationTests
        case "swiftPM": return options.swiftPM
        case "llbuild": return options.llbuild
        case "lldb": return options.lldb
        case "swiftDriver": return options.swiftDriver
        case "installSwift": return options.installSwift
        case "installLLVM": return options.installLLVM
        case "swiftDisableDeadStripping": return options.swiftDisableDeadStripping
        case "verboseBuild": return options.verboseBuild
        case "dryRun": return options.dryRun
        default: return false
        }
    }

    private func labeledRow(_ id: String) -> some View {
        HStack(spacing: 6) {
            if let descriptor = BuildOptionCatalog.descriptor(for: id) {
                Text(descriptor.title)
                HelpButton(descriptor: descriptor)
            } else {
                Text(id)
            }
        }
    }

    private var saveProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Build Profile")
                .font(.title2)
            TextField("Profile name", text: $profileName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }
                Button("Save") {
                    let profile = SavedBuildProfile(name: profileName, options: settings.context.options)
                    modelContext.insert(profile)
                    profileName = ""
                    showSaveSheet = false
                }
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}