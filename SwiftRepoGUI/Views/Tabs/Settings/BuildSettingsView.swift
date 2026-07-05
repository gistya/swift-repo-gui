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
                HStack {
                    Button("Save Current Configuration…") { showSaveSheet = true }
                    ActionHelpButton("action.saveProfile")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(TerminalBackground())
        .terminalText()
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
        case .products:
            boolRow("installablePackage")
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
            textRow("installPrefix", prompt: "/usr")
            textRow("installDestdir")
            textRow("installSymroot")
            textRow("darwinXCRunToolchain")
            textRow("cmake")
            textRow("hostCC")
            textRow("hostCXX")
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
            } else {
                TextField(
                    prompt,
                    text: stringBinding(for: id)
                )
            }
        }
    }

    private func stringBinding(for id: String) -> Binding<String> {
        Binding(
            get: { settings.context.options[keyPath: stringKeyPath(for: id)] },
            set: { settings.send(.setStringOption(key: id, value: $0)) }
        )
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
                .font(.monaco(size: 18, weight: .bold))
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
