import AppKit
import SwiftRepoCore
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
                                    .font(.monaco(size: 11))
                                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            }
                            .accessibilityElement(children: .combine)
                            Spacer()
                            Button("Load") { settings.send(.setOptions(profile.options)) }
                                .accessibilityLabel("Load profile \(profile.name)")
                                .accessibilityHint("Replaces the current build settings with this saved profile.")
                            Button(role: .destructive) {
                                modelContext.delete(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete profile \(profile.name)")
                            .accessibilityHint("Permanently removes this saved profile.")
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
                HStack {
                    Button("Save Current Configuration…") { showSaveSheet = true }
                        .accessibilityLabel("Save Current Configuration")
                        .accessibilityHint("Saves the current build settings as a named profile.")
                    ActionHelpButton("action.saveProfile")
                        .accessibilityLabel("Help about Save Current Configuration")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(TerminalBackground())
        .terminalText()
        .navigationTitle("Build Settings")
        .sheet(isPresented: $showSaveSheet) { saveProfileSheet }
        .background(TerminalBackground())
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
            boolRow("buildNinja")
            boolRow("useMake")
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
                        .font(.monaco(size: 11))
                        .foregroundStyle(Color.terminalGreen.opacity(0.75))
                }
            }
            .accessibilityLabel(displayTitle(for: "jobs"))
            .accessibilityValue("\(settings.context.options.jobs)")
            .accessibilityHint("Adjusts the number of parallel build jobs.")
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
            Stepper(value: settings.bind(\.options.litJobs, send: { BuildSettingsEvent.setIntOption(key: "litJobs", value: $0) }), in: 0...128) {
                HStack {
                    labeledRow("litJobs")
                    Spacer()
                    Text("\(settings.context.options.litJobs)")
                        .font(.monaco(size: 11))
                        .foregroundStyle(Color.terminalGreen.opacity(0.75))
                }
            }
            .accessibilityLabel(displayTitle(for: "litJobs"))
            .accessibilityValue("\(settings.context.options.litJobs)")
            .accessibilityHint("Adjusts the number of parallel lit test jobs.")
        case .products:
            boolRow("installablePackage")
            if settings.context.options.installablePackage {
                pathRow(
                    "installablePackagePath",
                    kind: .saveFile(defaultName: "swift-installable-package.tar.gz"),
                    prompt: "Exports/swift-installable-package.tar.gz"
                )
            }
            boolRow("foundation")
            boolRow("libDispatch")
            boolRow("xctest")
            boolRow("swiftPM")
            boolRow("llbuild")
            boolRow("lldb")
            boolRow("swiftDriver")
            boolRow("swiftTesting")
            boolRow("swiftTestingMacros")
            boolRow("swiftSyntax")
            boolRow("sourceKitLSP")
            boolRow("indexStoreDB")
        case .installation:
            boolRow("installSwift")
            boolRow("installLLVM")
            boolRow("installSwiftPM")
            boolRow("installLLDB")
            boolRow("installSwiftDriver")
            boolRow("installSwiftTesting")
            boolRow("installSwiftTestingMacros")
            boolRow("installSwiftSyntax")
            boolRow("installSourceKitLSP")
            boolRow("installAll")
        case .deployment:
            textRow("swiftDarwinSupportedArchs", prompt: ProjectService.machineArch)
            textRow("hostTarget", prompt: "\(ProjectService.platformName)-\(ProjectService.machineArch)")
            textRow("stdlibDeploymentTargets", prompt: "\(ProjectService.platformName)-\(ProjectService.machineArch)")
            textRow("buildStdlibDeploymentTargets", prompt: "\(ProjectService.platformName)-\(ProjectService.machineArch)")
            boolRow("buildSwiftDynamicStdlib")
            boolRow("buildSwiftDynamicSDKOverlay")
            boolRow("buildSwiftStaticStdlib")
            boolRow("buildSwiftStaticSDKOverlay")
        case .paths:
            pathRow("installPrefix", kind: .directory, prompt: "/usr")
            pathRow("installDestdir", kind: .directory)
            pathRow("installSymroot", kind: .directory)
            textRow("darwinXCRunToolchain")
            pathRow("cmake", kind: .file)
            pathRow("hostCC", kind: .file)
            pathRow("hostCXX", kind: .file)
            textRow("llvmTargetsToBuild", prompt: "AArch64;X86")
            textRow("buildArgs")
            textRow("litArgs")
            textRow("extraCMakeOptions", multiline: true)
            textRow("extraSwiftCMakeOptions", multiline: true)
            textRow("llvmCMakeOptions", multiline: true)
            textRow("extraLLVMCMakeOptions", multiline: true)
            textRow("extraSwiftArgs", multiline: true)
        case .advanced:
            boolRow("useCustomBuildScriptArguments")
            textRow("customBuildScriptArguments", multiline: true)
            boolRow("swiftDisableDeadStripping")
            boolRow("verboseBuild")
            boolRow("dryRun")
            presetPicker
            textRow("buildSubdir", prompt: "macos-arm64")
            textRow("extraArguments", multiline: true)
        }
    }

    private var presetPicker: some View {
        HStack {
            labeledRow("preset")
            Spacer()
            TerminalMenu(
                selection: settings.context.options.preset,
                options: [
                    TerminalMenuOption("", "None"),
                    TerminalMenuOption("buildbot_incremental", "buildbot_incremental"),
                    TerminalMenuOption("asan", "asan"),
                ],
                onSelect: { settings.send(.setStringOption(key: "preset", value: $0)) },
                width: 220
            )
            .accessibilityLabel(displayTitle(for: "preset"))
            .accessibilityHint("Selects a build preset.")
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
            .toggleStyle(
                ChipToggleStyle(
                    onColor: .toggleTint,
                    offColor: .toggleTint.opacity(0.3),
                    thumbColor: .toggleThumb
                )
            )
            // The visible label sits in a separate view, so name the toggle for VoiceOver.
            .accessibilityLabel(displayTitle(for: id))
        }
    }
    
    struct ChipToggleStyle: ToggleStyle {
        var onColor: Color = .green
        var offColor: Color = .gray
        var thumbColor: Color = .white

        func makeBody(configuration: ToggleStyle.Configuration) -> some View {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    configuration.isOn.toggle()
                }
            } label: {
                HStack {
                    configuration.label

                    Spacer()

                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(configuration.isOn ? onColor : offColor)
                            .frame(width: 48, height: 28)

                        Circle()
                            .fill(thumbColor)
                            .shadow(radius: 1)
                            .padding(3)
                            .frame(width: 28, height: 28)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
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
        case "buildNinja": return options.buildNinja
        case "useMake": return options.useMake
        case "swiftTesting": return options.swiftTesting
        case "swiftTestingMacros": return options.swiftTestingMacros
        case "swiftSyntax": return options.swiftSyntax
        case "sourceKitLSP": return options.sourceKitLSP
        case "indexStoreDB": return options.indexStoreDB
        case "foundation": return options.foundation
        case "libDispatch": return options.libDispatch
        case "xctest": return options.xctest
        case "installablePackage": return options.installablePackage
        case "installAll": return options.installAll
        case "installSwiftPM": return options.installSwiftPM
        case "installLLDB": return options.installLLDB
        case "installSwiftDriver": return options.installSwiftDriver
        case "installSwiftTesting": return options.installSwiftTesting
        case "installSwiftTestingMacros": return options.installSwiftTestingMacros
        case "installSwiftSyntax": return options.installSwiftSyntax
        case "installSourceKitLSP": return options.installSourceKitLSP
        case "buildSwiftDynamicStdlib": return options.buildSwiftDynamicStdlib
        case "buildSwiftDynamicSDKOverlay": return options.buildSwiftDynamicSDKOverlay
        case "buildSwiftStaticStdlib": return options.buildSwiftStaticStdlib
        case "buildSwiftStaticSDKOverlay": return options.buildSwiftStaticSDKOverlay
        case "useCustomBuildScriptArguments": return options.useCustomBuildScriptArguments
        default: return false
        }
    }

    @ViewBuilder
    private func textRow(_ id: String, prompt: String = "", multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labeledRow(id)
            if multiline {
                TextField(
                    prompt,
                    text: stringBinding(for: id),
                    axis: .vertical
                )
                .lineLimit(2...8)
                .accessibilityLabel(displayTitle(for: id))
            } else {
                TextField(
                    prompt,
                    text: stringBinding(for: id)
                )
                .accessibilityLabel(displayTitle(for: id))
            }
        }
    }

    private func stringBinding(for id: String) -> Binding<String> {
        Binding(
            get: { settings.context.options[keyPath: stringKeyPath(for: id)] },
            set: { settings.send(.setStringOption(key: id, value: $0)) }
        )
    }

    private func stringValue(for id: String) -> String {
        settings.context.options[keyPath: stringKeyPath(for: id)]
    }

    /// What kind of open/save panel a path row should present.
    private enum PathPickerKind {
        /// Pick an existing directory (install destinations, prefixes).
        case directory
        /// Pick an existing file (cmake / compiler executables).
        case file
        /// Choose a destination file to write (the installable-package tarball).
        case saveFile(defaultName: String)
    }

    /// A path option rendered like `textRow` but with a "Choose…" button that opens a native
    /// open/save panel. The text field stays editable, so a path can still be typed or pasted, and
    /// the trailing clear button resets it to the default (empty).
    @ViewBuilder
    private func pathRow(_ id: String, kind: PathPickerKind, prompt: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                labeledRow(id)
                Spacer()
                Button("Choose…") { choosePath(for: id, kind: kind) }
                    .accessibilityLabel("Choose \(displayTitle(for: id))")
                    .accessibilityHint("Opens a file dialog to set this path.")
            }
            HStack(spacing: 6) {
                TextField(prompt, text: stringBinding(for: id))
                    .accessibilityLabel(displayTitle(for: id))
                if !stringValue(for: id).isEmpty {
                    Button {
                        settings.send(.setStringOption(key: id, value: ""))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.terminalGreen.opacity(0.6))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear")
                    .accessibilityLabel("Clear \(displayTitle(for: id))")
                }
            }
        }
    }

    /// Present the native panel for `kind` and store the chosen path via `.setStringOption`.
    private func choosePath(for id: String, kind: PathPickerKind) {
        let current = stringValue(for: id).trimmingCharacters(in: .whitespaces)
        let existing = current.isEmpty ? nil : URL(fileURLWithPath: (current as NSString).expandingTildeInPath)

        switch kind {
        case .directory, .file:
            let panel = NSOpenPanel()
            if case .directory = kind {
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
            } else {
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
            }
            panel.allowsMultipleSelection = false
            panel.message = NSLocalizedString("Choose a location", comment: "Prompt shown in the open panel for a build-settings path")
            if let existing { panel.directoryURL = existing }
            if panel.runModal() == .OK, let url = panel.url {
                settings.send(.setStringOption(key: id, value: url.path))
            }
        case .saveFile(let defaultName):
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.message = NSLocalizedString("Choose where to write the file", comment: "Prompt shown in the save panel for a build-settings output path")
            if let existing {
                panel.directoryURL = existing.deletingLastPathComponent()
                panel.nameFieldStringValue = existing.lastPathComponent
            } else {
                panel.nameFieldStringValue = defaultName
            }
            if panel.runModal() == .OK, let url = panel.url {
                settings.send(.setStringOption(key: id, value: url.path))
            }
        }
    }

    private func stringKeyPath(for id: String) -> WritableKeyPath<BuildOptions, String> {
        switch id {
        case "preset": return \.preset
        case "buildSubdir": return \.buildSubdir
        case "extraArguments": return \.extraArguments
        case "customBuildScriptArguments": return \.customBuildScriptArguments
        case "swiftDarwinSupportedArchs": return \.swiftDarwinSupportedArchs
        case "hostTarget": return \.hostTarget
        case "stdlibDeploymentTargets": return \.stdlibDeploymentTargets
        case "buildStdlibDeploymentTargets": return \.buildStdlibDeploymentTargets
        case "installablePackagePath": return \.installablePackagePath
        case "installPrefix": return \.installPrefix
        case "installDestdir": return \.installDestdir
        case "installSymroot": return \.installSymroot
        case "darwinXCRunToolchain": return \.darwinXCRunToolchain
        case "cmake": return \.cmake
        case "hostCC": return \.hostCC
        case "hostCXX": return \.hostCXX
        case "llvmTargetsToBuild": return \.llvmTargetsToBuild
        case "buildArgs": return \.buildArgs
        case "litArgs": return \.litArgs
        case "extraCMakeOptions": return \.extraCMakeOptions
        case "extraSwiftCMakeOptions": return \.extraSwiftCMakeOptions
        case "llvmCMakeOptions": return \.llvmCMakeOptions
        case "extraLLVMCMakeOptions": return \.extraLLVMCMakeOptions
        case "extraSwiftArgs": return \.extraSwiftArgs
        default: return \.extraArguments
        }
    }

    /// Natural-language name for an option id — the catalog title when available, else the raw id.
    private func displayTitle(for id: String) -> String {
        BuildOptionCatalog.descriptor(for: id)?.title ?? id
    }

    private func labeledRow(_ id: String) -> some View {
        HStack(spacing: 6) {
            if let descriptor = BuildOptionCatalog.descriptor(for: id) {
                Text(descriptor.title)
                HelpButton(descriptor: descriptor)
                    .accessibilityLabel("Help about \(descriptor.title)")
            } else {
                Text(id)
            }
        }
    }

    private var saveProfileSheet: some View {
        SaveProfileSheet(profileName: $profileName, showSaveSheet: $showSaveSheet, settings: settings)
    }
}
