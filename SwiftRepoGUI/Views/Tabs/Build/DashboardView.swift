import AppKit
import Matrix
import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct DashboardView: View {
    let session: AppSession
    let project: MachineStore<ProjectMachine>
    let settings: MachineStore<BuildSettingsMachine>
    let build: MachineStore<BuildOperationsMachine>

    @Environment(\.modelContext) private var modelContext
    @State private var pendingAction: PendingBuildAction?
    /// Opt-in update-checkout `--match-timestamp` (off by default). Persisted, and read back in
    /// `AppSession.makeRequest` via the same key so the flag reaches the command.
    @AppStorage(AppSession.matchTimestampDefaultsKey) private var matchTimestamp = false

    /// A build action awaiting an "are you sure?" confirmation — the destructive ones (clean rebuilds,
    /// update-checkout, which can discard local branch state).
    private struct PendingBuildAction: Identifiable {
        let id = UUID()
        let title: String
        let confirmLabel: String
        let message: String
        let run: () -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                projectHeader
                ciXcodeBanner
                quickActions
                BuildProgressPanel(build: build)
            }
            .padding()
        }
        .background(TerminalBackground())
        .terminalText()
        .navigationTitle("Swift Build")
        .onAppear {
            session.attach(modelContext: modelContext)
            session.checkCIXcode()
        }
        .alert("Error", isPresented: Binding(
            get: { session.lastErrorMessage != nil },
            set: { if !$0 { session.clearLastError() } }
        )) {
            Button("OK") { session.clearLastError() }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel, role: .destructive) {
                action.run()
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.message)
        }
    }

    private var projectHeader: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Swift Project")
                        .font(.monaco(size: 13, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Choose…") { chooseProjectDirectory() }
                        .accessibilityLabel("Choose Swift project")
                        .accessibilityHint("Opens a folder picker to set the Swift project root directory.")
                    ActionHelpButton("action.chooseProject")
                        .accessibilityLabel("Help about Choose Swift project")
                }

                TextField(
                    "Path to swift-project directory",
                    text: project.bind(\.projectPath, send: ProjectEvent.setPath)
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { project.send(.refresh) }
                .accessibilityLabel("Swift project directory path")
                .accessibilityHint("Enter the path to your swift-project directory. Press return to refresh.")

                if project.matches(.loading) {
                    HStack(spacing: 8) {
                        MatrixLoader(.fun(.snake), size: 30, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
                            .accessibilityHidden(true)
                        Text("Discovering repositories…")
                            .font(.monaco(size: 13))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                    }
                } else if let message = project.context.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(project.matches(.error) ? Color.terminalFailureRed : Color.terminalGreen)
                        .font(.monaco(size: 13))
                } else if let info = project.context.projectInfo {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                Label("\(info.repositories.count) repos", systemImage: "folder")
                                if let swift = info.repositories.first(where: \.isPrimary)?.currentRevision {
                                    Label("swift @ \(swift)", systemImage: "swift")
                                }
                            }
                            .font(.monaco(size: 11))
                            .foregroundStyle(Color.terminalGreen.opacity(0.75))
                            .accessibilityElement(children: .combine)

                            if !info.detectedBuildSubdirs.isEmpty {
                                HStack {
                                    Text("Build directory")
                                        .font(.monaco(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.terminalGreen.opacity(0.8))
                                    TerminalMenu(
                                        selection: project.context.selectedBuildSubdir,
                                        options: info.detectedBuildSubdirs.map { TerminalMenuOption($0, $0) },
                                        onSelect: { project.send(.setBuildSubdir($0)) },
                                        width: 260
                                    )
                                    .accessibilityLabel("Build directory")
                                    .accessibilityValue(project.context.selectedBuildSubdir)
                                    .accessibilityHint("Choose which detected build directory to use.")
                                }
                            }
                            checkoutSchemeSection(info: info)
                        }
                        Spacer()
                        repositorySection
                    }

                    Text(updateCheckoutSummary(info: info))
                        .font(.monaco(size: 11))
                        .foregroundStyle(Color.terminalGreen.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func checkoutSchemeSection(info: SwiftProjectInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Checkout scheme")
                    .font(.monaco(size: 11, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.8))
                TerminalMenu(
                    selection: project.context.checkoutSchemeOverride,
                    options: [TerminalMenuOption("", "Auto (skip swift)")]
                        + info.availableCheckoutSchemes.map { TerminalMenuOption($0, $0) },
                    onSelect: { project.send(.setCheckoutSchemeOverride($0)) },
                    width: 260
                )
                .accessibilityLabel("Checkout scheme")
                .accessibilityHint("Auto keeps your swift branch and skips it; pick a scheme to pin the sibling repos to a known branch scheme.")
            }
            Toggle(isOn: $matchTimestamp) {
                Text("Match timestamp")
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.8))
            }
            .toggleStyle(.checkbox)
            .help("Pin the sibling repos to each one's commit at your swift branch's HEAD date (update-checkout --match-timestamp), instead of their latest. Off by default.")
            .accessibilityLabel("Match timestamp")
            .accessibilityHint("When on, update-checkout pins the sibling repos to your swift branch's commit date instead of their latest.")
        }
    }

    /// Plain-language description of what the update-checkout buttons will do given the current scheme
    /// selection and the match-timestamp toggle. Deliberately never claims the branch couldn't be read —
    /// it always leaves the swift repo alone.
    private func updateCheckoutSummary(info: SwiftProjectInfo) -> String {
        let override = project.context.checkoutSchemeOverride.trimmingCharacters(in: .whitespaces)
        let branch = info.swiftBranch.isEmpty ? "its current branch" : info.swiftBranch
        var flags = ["--skip-repository swift"]
        if !override.isEmpty { flags.append("--scheme \(override)") }
        if matchTimestamp { flags.append("--match-timestamp") }
        let timing = matchTimestamp ? "at your swift branch's commit date" : "to their latest"
        let flagList = flags.joined(separator: " ")
        return "update-checkout leaves the swift repo on \(branch) and updates the other repos \(timing) (\(flagList))."
    }

    /// Warns when the Xcode this app builds with differs from what the ci.swift.org nodes run (and
    /// quietly confirms when it matches). Silent while the first check is in flight; a FAILED check
    /// still renders, because the Recheck button is the only way to recover from a network blip.
    @ViewBuilder
    private var ciXcodeBanner: some View {
        switch session.ciXcodeCheck {
        case .idle, .checking:
            EmptyView()
        case .failed:
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Color.terminalGreen.opacity(0.7))
                    .accessibilityHidden(true)
                Text("Couldn't reach ci.swift.org to compare your Xcode against CI.")
                    .font(.monaco(size: 11))
                    .foregroundStyle(Color.terminalGreen.opacity(0.8))
                Spacer()
                Button("Recheck") { session.recheckCIXcode() }
                    .font(.monaco(size: 11))
                    .accessibilityHint("Retries the ci.swift.org Xcode comparison.")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.terminalGreen.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.terminalGreen.opacity(0.25)))
            .accessibilityElement(children: .combine)
        case .loaded(let status):
            let accent = status.matches ? Color.terminalGreen : Color.swiftOrange
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.matches ? "Xcode \(status.localVersion) matches CI" : "Local Xcode differs from CI")
                        .font(.monaco(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Text(ciXcodeDetail(status))
                        .font(.monaco(size: 11))
                        .foregroundStyle(Color.terminalGreen.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ciFleetPicker
                Button("Recheck") { session.recheckCIXcode() }
                    .font(.monaco(size: 11))
                    .accessibilityHint("Re-checks ci.swift.org and your selected Xcode.")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.45)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.matches
                ? "Local Xcode \(status.localVersion) matches CI"
                : "Warning: local Xcode \(status.localVersion) differs from CI \(status.primaryCIVersion)")
        }
    }

    /// Chooses which ci.swift.org machine pool to compare against. The pools run different Xcodes,
    /// so this is a real question with no default-correct answer — it starts on this machine's own
    /// architecture and re-runs the check on change.
    private var ciFleetPicker: some View {
        TerminalMenu(
            selection: session.ciFleet,
            options: CIFleet.allCases.map { TerminalMenuOption($0, $0.display) },
            onSelect: { session.ciFleet = $0 },
            width: 170
        )
        .accessibilityLabel("CI fleet to compare against")
    }

    private func ciXcodeDetail(_ status: CIXcodeStatus) -> String {
        let localFull = status.localBuild.map { "\(status.localVersion) (\($0))" } ?? status.localVersion
        let precision = status.comparedAtMajorOnly ? ", major version only from CI labels" : ""
        var detail = "Local Xcode \(localFull); ci.swift.org \(status.fleet.display) nodes run \(status.primaryCIVersion)\(precision)."
        if !status.matches {
            detail += " Building with a different Xcode than CI can produce results that differ from CI."
        }
        if status.ciVersions.count > 1 {
            detail += " (That fleet: \(status.ciVersions.joined(separator: ", ")).)"
        }
        // The published blurb is the project's stated recommendation and the fleets don't always
        // agree with it — surface the difference rather than letting it look like a wrong reading.
        if let published = status.publishedVersion, status.publishedDiffersFromFleet {
            let host = status.publishedHostOS.map { " on macOS \($0)" } ?? ""
            detail += " Note: the ci.swift.org dashboard states Xcode \(published)\(host)."
        }
        return detail
    }

    private var quickActions: some View {
        GroupBox("Build Actions") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                // Swift-level builds (require the primary `swift` repo — disabled when a dependency is selected).
                actionButton(title: "Incremental Frontend", subtitle: "ninja bin/swift-frontend", symbol: "swift", help: "action.incrementalFrontend", kind: .incrementalFrontend)
                actionButton(title: "Incremental Swift Repo", subtitle: "Rebuild all swift/ targets", symbol: "arrow.triangle.2.circlepath", help: "action.incrementalSwiftRepo", kind: .incrementalSwiftRepo)
                actionButton(title: "Incremental Everything", subtitle: "ninja entire build tree", symbol: "square.stack.3d.up", help: "action.incrementalEverything", kind: .incrementalEverything)
                actionButton(title: "Full Build Script", subtitle: "Uses settings below", symbol: "gearshape.2", help: "action.buildScript", kind: .buildScript)
                actionButton(title: "Fresh Rebuild", subtitle: "Clean + build script", symbol: "trash.circle", help: "action.freshBuild", kind: .freshBuild,
                             destructive: true,
                             confirmMessage: "This deletes the current build and runs a full clean build script from scratch — it can take a very long time.")
                // Dependency-scoped — valid for whichever repo is selected.
                actionButton(title: "Fresh Dependency", subtitle: "ninja clean + rebuild selected repo", symbol: "arrow.clockwise.circle", help: "action.freshDependency",
                             requiresPrimaryRepo: false,
                             destructive: true,
                             confirmMessage: "This runs `ninja clean` on the selected dependency and rebuilds it from scratch.",
                             action: { Task { try? await session.startFreshDependency() } })
                // Checkout management — repo-agnostic, but mutates git state, so confirm.
                actionButton(title: "Update Dependencies", subtitle: "Sync sibling repos, keep swift branch", symbol: "arrow.down.circle", help: "action.updateDependencies", kind: .updateDependencies,
                             requiresPrimaryRepo: false,
                             destructive: true,
                             confirmMessage: "This runs update-checkout to sync the sibling repos. Your swift branch is left untouched (--skip-repository swift).")
                actionButton(title: "Update & Rebuild Changed", subtitle: "Sync siblings, ninja changed repos", symbol: "arrow.triangle.merge", help: "action.updateAndRebuild",
                             requiresPrimaryRepo: false,
                             destructive: true,
                             confirmMessage: "This syncs the sibling repos (update-checkout, keeping your swift branch), then rebuilds the repos that changed.",
                             action: { Task { await session.runUpdateThenRebuild() } })
                actionButton(title: "Update & Clean Tree", subtitle: "Sync repos + wipe active build dir", symbol: "trash.slash.circle", help: "action.updateAndClean",
                             requiresPrimaryRepo: false,
                             destructive: true,
                             confirmMessage: "This runs update-checkout to sync the sibling repos (your swift branch is left untouched), then DELETES the build sub-directory build/\(session.effectiveBuildSubdir). No build is started.",
                             action: { Task { await session.updateAndCleanBuildTree(subdir: session.effectiveBuildSubdir) } })
            }
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        help: String,
        kind: BuildOperationKind? = nil,
        requiresPrimaryRepo: Bool = true,
        destructive: Bool = false,
        confirmMessage: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let perform: () -> Void = {
            if let action {
                action()
            } else if let kind {
                Task { try? await session.startBuild(kind: kind) }
            }
        }
        // A swift-level build makes no sense while a dependency is the target: gray it out and say why.
        let dependencySelected = settings.context.selectedRepository != "swift"
        let blockedByRepo = requiresPrimaryRepo && dependencySelected
        let isDisabled = !project.context.isValid || project.matches(.loading) || build.matches(.running) || blockedByRepo
        let opacity = isDisabled ? 0.3 : 1.0

        return Button {
            if destructive {
                // Built as String and fed to confirmationDialog/Button/Text (which don't auto-localize a
                // String variable), so localize explicitly via runtime-key lookup against the catalog.
                pendingAction = PendingBuildAction(
                    title: String(format: NSLocalizedString("Run “%@”?", comment: "Confirm-run dialog title"),
                                  NSLocalizedString(title, comment: "Build action name")),
                    confirmLabel: NSLocalizedString(title, comment: "Build action name"),
                    message: NSLocalizedString(confirmMessage ?? "This can modify or delete build state and may take a while.",
                                               comment: "Destructive build action confirmation"),
                    run: perform
                )
            } else {
                perform()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey(title), systemImage: symbol)
                    .font(.monaco(size: 13, weight: .bold))
                    .lineLimit(1)
                    .padding(.trailing, 18)
                Text(LocalizedStringKey(subtitle))
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
        .disabled(isDisabled)
        .opacity(opacity)
        .help(blockedByRepo
            ? LocalizedStringKey("This is a swift-level build — select the swift repository to run it.")
            : LocalizedStringKey(subtitle))
        // VoiceOver: a single labeled/hinted button element (it announces the disabled state itself).
        .accessibilityLabel(LocalizedStringKey(title))
        .accessibilityHint(Self.accessibilityHint(subtitle: subtitle, destructive: destructive, blockedByRepo: blockedByRepo))
        // Help stays tappable even while the action is disabled (build running / no project / wrong repo).
        .overlay(alignment: .topTrailing) {
            ActionHelpButton(help)
                .padding(8)
                .accessibilityLabel("Help about \(title)")
        }
    }

    private static func accessibilityHint(subtitle: String, destructive: Bool, blockedByRepo: Bool) -> String {
        // Returned as String to `.accessibilityHint`, which won't localize a variable — so resolve
        // the pieces through the catalog here.
        let sub = NSLocalizedString(subtitle, comment: "Build action subtitle")
        if blockedByRepo {
            return String(format: NSLocalizedString("%@. Disabled — select the swift repository to enable this swift-level build.", comment: ""), sub)
        }
        if destructive {
            return String(format: NSLocalizedString("%@. Asks for confirmation before running.", comment: ""), sub)
        }
        return sub
    }

    private var repositorySection: some View {
        GroupBox("Target Repository") {
            if project.matches(.loading) {
                HStack(spacing: 8) {
                    MatrixLoader(.fun(.snake), size: 30.0, color: .terminalGreen, speed: 10.0, bloom: true, halo: 4.0)
                        .accessibilityHidden(true)
                    Text("Loading repository list…")
                        .foregroundStyle(Color.terminalGreen.opacity(0.75))
                }
            } else if let repos = project.context.projectInfo?.repositories {
                HStack {
                    Text("Repository")
                        .font(.monaco(size: 11, weight: .semibold))
                        .foregroundStyle(Color.terminalGreen.opacity(0.8))
                    TerminalMenu(
                        selection: settings.context.selectedRepository,
                        options: repos.map { TerminalMenuOption($0.name, $0.name) },
                        onSelect: { settings.send(.setRepository($0)) },
                        width: 260
                    )
                    .accessibilityLabel("Target repository")
                    .accessibilityValue(settings.context.selectedRepository)
                    .accessibilityHint("Choose which repository dependency-specific builds act on.")
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
        panel.message = NSLocalizedString("Select your swift-project directory", comment: "Prompt shown in the folder picker for choosing the Swift project root")
        if panel.runModal() == .OK, let url = panel.url {
            session.selectProjectDirectory(url)
        }
    }
}
