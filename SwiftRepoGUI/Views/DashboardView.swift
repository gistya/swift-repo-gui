import AppKit
import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct DashboardView: View {
    let session: AppSession
    let project: MachineStore<ProjectMachine>
    let settings: MachineStore<BuildSettingsMachine>
    let build: MachineStore<BuildOperationsMachine>

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                projectHeader
                quickActions
                BuildProgressPanel(build: build)
                repositorySection
            }
            .padding()
        }
        .background(TerminalBackground())
        .terminalText()
        .navigationTitle("Swift Build")
        .onAppear {
            session.attach(modelContext: modelContext)
        }
        .alert("Error", isPresented: Binding(
            get: { session.lastErrorMessage != nil },
            set: { if !$0 { session.clearLastError() } }
        )) {
            Button("OK") { session.clearLastError() }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
    }

    private var projectHeader: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Swift Project")
                        .font(.monaco(size: 13, weight: .bold))
                    Spacer()
                    Button("Choose…") { chooseProjectDirectory() }
                    ActionHelpButton("action.chooseProject")
                }

                TextField(
                    "Path to swift-project directory",
                    text: project.bind(\.projectPath, send: ProjectEvent.setPath)
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { project.send(.refresh) }

                if project.matches(.loading) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                        Text("Discovering repositories…")
                            .font(.monaco(size: 13))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                    }
                } else if let message = project.context.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(project.matches(.error) ? Color.terminalFailureRed : Color.terminalGreen)
                        .font(.monaco(size: 13))
                } else if let info = project.context.projectInfo {
                    HStack(spacing: 16) {
                        Label("\(info.repositories.count) repos", systemImage: "folder")
                        if let swift = info.repositories.first(where: \.isPrimary)?.currentRevision {
                            Label("swift @ \(swift)", systemImage: "swift")
                        }
                    }
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))

                    if !info.detectedBuildSubdirs.isEmpty {
                        HStack {
                            Text("Build directory")
                                .font(.monaco(size: 11, weight: .semibold))
                                .foregroundStyle(Color.terminalGreen.opacity(0.8))
                            Spacer()
                            TerminalMenu(
                                selection: project.context.selectedBuildSubdir,
                                options: info.detectedBuildSubdirs.map { TerminalMenuOption($0, $0) },
                                onSelect: { project.send(.setBuildSubdir($0)) },
                                width: 260
                            )
                        }
                    }

                    checkoutSchemeSection(info: info)
                }
            }
        }
    }

    @ViewBuilder
    private func checkoutSchemeSection(info: SwiftProjectInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Checkout scheme")
                    .font(.monaco(size: 11, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.8))
                Spacer()
                TerminalMenu(
                    selection: project.context.checkoutSchemeOverride,
                    options: [TerminalMenuOption("", "Auto (\(info.checkoutScheme))")]
                        + info.availableCheckoutSchemes.map { TerminalMenuOption($0, $0) },
                    onSelect: { project.send(.setCheckoutSchemeOverride($0)) },
                    width: 260
                )
            }

            Text("Branch `\(info.swiftBranch)` → scheme `\(info.checkoutScheme)` for update-checkout.")
                .font(.monaco(size: 11))
                .foregroundStyle(Color.terminalGreen.opacity(0.75))

            Text(info.schemeResolutionSource.explanation)
                .font(.monaco(size: 11))
                .foregroundStyle(Color.terminalGreen.opacity(0.75))
        }
    }

    private var quickActions: some View {
        GroupBox("Build Actions") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                actionButton(title: "Incremental Frontend", subtitle: "ninja bin/swift-frontend", symbol: "swift", help: "action.incrementalFrontend", kind: .incrementalFrontend)
                actionButton(title: "Incremental Swift Repo", subtitle: "Rebuild all swift/ targets", symbol: "arrow.triangle.2.circlepath", help: "action.incrementalSwiftRepo", kind: .incrementalSwiftRepo)
                actionButton(title: "Incremental Everything", subtitle: "ninja entire build tree", symbol: "square.stack.3d.up", help: "action.incrementalEverything", kind: .incrementalEverything)
                actionButton(title: "Full Build Script", subtitle: "Uses settings below", symbol: "gearshape.2", help: "action.buildScript", kind: .buildScript)
                actionButton(title: "Fresh Rebuild", subtitle: "Clean + build script", symbol: "trash.circle", help: "action.freshBuild", kind: .freshBuild)
                actionButton(title: "Fresh Dependency", subtitle: "ninja clean + rebuild selected repo", symbol: "arrow.clockwise.circle", help: "action.freshDependency", action: {
                    Task { try? await session.startFreshDependency() }
                })
                actionButton(title: "Update Dependencies", subtitle: "update-checkout --scheme … --match-timestamp", symbol: "arrow.down.circle", help: "action.updateDependencies", kind: .updateDependencies)
                actionButton(title: "Update & Rebuild Changed", subtitle: "Sync deps, ninja changed repos", symbol: "arrow.triangle.merge", help: "action.updateAndRebuild", action: {
                    Task { await session.runUpdateThenRebuild() }
                })
            }
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        help: String,
        kind: BuildOperationKind? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let action {
                action()
            } else if let kind {
                Task { try? await session.startBuild(kind: kind) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.monaco(size: 13, weight: .bold))
                    .lineLimit(1)
                    .padding(.trailing, 18)
                Text(subtitle)
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    // Reserve two lines for every subtitle so buttons keep a uniform height
                    // regardless of how far each caption wraps.
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(RetroActionButtonStyle())
        .disabled(!project.context.isValid || project.matches(.loading) || build.matches(.running))
        // Help stays tappable even while the action is disabled (build running / no project).
        .overlay(alignment: .topTrailing) {
            ActionHelpButton(help)
                .padding(8)
        }
    }

    private var repositorySection: some View {
        GroupBox("Target Repository") {
            if project.matches(.loading) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                    Text("Loading repository list…")
                        .foregroundStyle(Color.terminalGreen.opacity(0.75))
                }
            } else if let repos = project.context.projectInfo?.repositories {
                HStack {
                    Text("Repository")
                        .font(.monaco(size: 11, weight: .semibold))
                        .foregroundStyle(Color.terminalGreen.opacity(0.8))
                    Spacer()
                    TerminalMenu(
                        selection: settings.context.selectedRepository,
                        options: repos.map { TerminalMenuOption($0.name, $0.name) },
                        onSelect: { settings.send(.setRepository($0)) },
                        width: 260
                    )
                }
                Text("Used for dependency-specific fresh/incremental builds.")
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            } else {
                Text("Select a project to list repositories.")
                    .foregroundStyle(Color.terminalGreen.opacity(0.75))
            }
        }
    }

    private func chooseProjectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your swift-project directory"
        if panel.runModal() == .OK, let url = panel.url {
            session.setProjectPath(url.path)
        }
    }
}
