import Foundation
import Observation
import Ox0badf00dAVFoundation
import SwiftData
import SwiftRepoCore
import SwiftXState
import SwiftXStateInspectorUI
import SwiftXStateSwiftUI
#if canImport(AppKit)
import AppKit
#endif

nonisolated enum SessionWaitError: Error, LocalizedError, Sendable {
    case projectLoadTimedOut(seconds: Int)
    case buildTimedOut(seconds: Int)
    case projectInvalid(message: String)

    var errorDescription: String? {
        switch self {
        case let .projectLoadTimedOut(seconds):
            "Project discovery timed out after \(seconds) seconds."
        case let .buildTimedOut(seconds):
            "Build timed out after \(seconds) seconds."
        case let .projectInvalid(message):
            message
        }
    }
}

/// The app's view model: a `MainStore` collating typed machines on the main actor.
/// Persistence (SwiftData) and panel/file dialogs live here; machines stay pure interpreters.
@MainActor
@Observable
final class AppSession {
    /// The one app-lifetime session. `@State private var session = AppSession()` re-evaluates its
    /// default expression every time the `App` (or a view) struct is re-initialized — unlike
    /// `@StateObject`, whose initializer is autoclosured and runs once. Each re-eval would spin up
    /// another `SoundtrackEffectDriver` + `TrackerAudioEngine` (+ `AVAudioEngine`), and multiple live
    /// engines fighting over the audio HAL is what floods CoreAudio. Referencing this `static let`
    /// (created exactly once, lazily, on first access) guarantees a single session/engine no matter
    /// how many times SwiftUI re-creates the App struct.
    static let shared = AppSession()

    static let projectLoadTimeout: Duration = .seconds(120)
    static let buildTimeout: Duration = .seconds(86_400)

    let store: MainStore
    let inspector: InspectorStore

    let navigation: MachineStore<AppNavigationMachine>
    let project: MachineStore<ProjectMachine>
    let settings: MachineStore<BuildSettingsMachine>
    let build: MachineStore<BuildOperationsMachine>
    let soundtrack: MachineStore<SoundtrackMachine>
    let toolchain: MachineStore<ToolchainMachine>
    let appearance: MachineStore<AppearanceMachine>

    @ObservationIgnored private weak var modelContext: ModelContext?
    @ObservationIgnored private let settingsDefaults: UserDefaults
    @ObservationIgnored private var soundtrackDriver: SoundtrackEffectDriver?
    @ObservationIgnored private var trackedRecords: [UUID: BuildOperationRecord] = [:]
    @ObservationIgnored private var didStartEffectsLoad = false
    @ObservationIgnored private var toolchainWarmupTask: Task<Void, Never>?
    @ObservationIgnored private var buildSoundtrackBridge: Task<Void, Never>?
    @ObservationIgnored private(set) var lastErrorMessage: String?
    @ObservationIgnored private var ciXcodeTask: Task<Void, Never>?
    /// Result of comparing the locally selected Xcode against the ci.swift.org build fleet. `nil` until
    /// the first check completes (or if it couldn't be determined). Observed by the Build tab banner.
    private(set) var ciXcodeStatus: CIXcodeStatus?

    /// Installed AudioUnit effects the user can drop into a soundtrack insert slot. Populated lazily
    /// by `ensureAudioEffectsLoaded()` the first time the effects rack is opened — never at launch.
    /// Observed, so the deck's slot picker fills in when the (off-main) enumeration completes.
    private(set) var availableAudioEffects: [AudioComponentRef] = []

    var selectedSection: AppSectionID { navigation.context.section }

    /// Sections currently torn off into their own window. They're hidden from the main tab bar until
    /// that window closes. Observed, so the tab bar re-lays-out the moment a tab detaches/reattaches.
    private(set) var detachedSections: Set<AppSectionID> = []

    /// The sections still shown in the main window's tab bar (everything not torn off).
    var attachedSections: [AppSectionID] {
        AppSectionID.allCases.filter { !detachedSections.contains($0) }
    }

    /// Security-scoped access to the user-chosen project root, so a sandboxed build can reach it —
    /// and the git/ninja/build-script subprocesses it spawns inherit that access — across launches.
    @ObservationIgnored private let projectAccess = ProjectAccessBookmark()

    init(modelContext: ModelContext? = nil, settingsDefaults: UserDefaults = .standard) {
        //NSLog("%@", "[OxAudio] AppSession.init")
        self.modelContext = modelContext
        self.settingsDefaults = settingsDefaults
        let mainStore = MainStore()
        let inspectorStore = InspectorStore()
        // Hide the one-shot background invoke children from the inspector — they're internal
        // async plumbing (`Invoke(id: "parse")` in ToolchainMachine, `Invoke(id: "inspect")` in
        // ProjectMachine), not app-level state machines worth showing as actor rows. An invoked
        // child inherits its parent's inspect sink and registers with `systemId == invoke.id`.
        let inspect = AppSession.filteredInspect(
            inspectorStore.observe(),
            hidingSystemIds: ["parse", "inspect"]
        )
        store = mainStore
        inspector = inspectorStore
        navigation = mainStore.track(nonInspectedStore(
            AppNavigationMachine(),
            id: "swiftbuilder.navigation",
            systemId: "swiftbuilder.navigation",
        ))
        project = mainStore.track(inspectedStore(
            ProjectMachine(),
            id: "swiftbuilder.project",
            systemId: "swiftbuilder.project",
            inspect: inspect
        ))
        settings = mainStore.track(nonInspectedStore(
            BuildSettingsMachine(),
            id: "swiftbuilder.settings",
            systemId: "swiftbuilder.settings",
        ))
        let soundStyle = MusicSettings.current
        let soundtrackContext = SoundtrackContext.initial(
            style: soundStyle,
            tracks: TrackerModuleLibrary.discover(),
            defaults: settingsDefaults
        )
        let soundtrackStore = mainStore.track(inspectedStore(
            SoundtrackMachine(context: soundtrackContext),
            id: "swiftbuilder.soundtrack",
            systemId: "swiftbuilder.soundtrack",
            inspect: inspect
        ))
        soundtrack = soundtrackStore
        soundtrackDriver = SoundtrackEffectDriver(
            store: soundtrackStore,
            config: Self.audioConfig(for: soundStyle),
            defaults: settingsDefaults
        )
        build = mainStore.track(inspectedStore(
            BuildOperationsMachine(),
            id: "swiftbuilder.build",
            systemId: "swiftbuilder.build",
            inspect: inspect
        ))
        toolchain = mainStore.track(inspectedStore(
            ToolchainMachine(),
            id: "swiftbuilder.toolchain",
            systemId: "swiftbuilder.toolchain",
            inspect: inspect
        ))
        appearance = mainStore.track(inspectedStore(
            AppearanceMachine(),
            id: "swiftbuilder.appearance",
            systemId: "swiftbuilder.appearance",
            inspect: inspect
        ))
        // Sync the machine to the appearance `AppStyleStore` self-restored from UserDefaults, so the
        // statechart reflects the persisted choice from launch. From the machine's initial `.system`,
        // the matching event advances it (a no-op when the restored choice is already `.system`).
        appearance.send(Self.appearanceEvent(for: AppStyleStore.shared.preview))

        // Bridge build → soundtrack OFF the view tree. Doing this in ContentView's body (an
        // `onChange(of: SoundtrackBuildSnapshot(build.context))`) subscribed the whole view to the
        // full build context, so every progress tick re-ran ContentView.body and recreated the title
        // bar / tab bar / content. Here we consume the build snapshot stream off-main, collapse it to
        // the narrow SoundtrackBuildSnapshot, and only touch the soundtrack when that actually changes.
        let buildSnapshots = build.snapshots
        buildSoundtrackBridge = Task { [weak self] in
            var last: SoundtrackBuildSnapshot?
            for await (_, context) in buildSnapshots {
                let snapshot = SoundtrackBuildSnapshot(context)
                guard snapshot != last else { continue }
                last = snapshot
                await MainActor.run { self?.soundtrack.send(.buildSnapshotChanged(snapshot)) }
            }
        }

        if let lastUsedSettings = LastUsedBuildSettingsStore.load(from: settingsDefaults) {
            settings.send(.restore(lastUsedSettings.options, lastUsedSettings.selectedRepository))
        }
        // Re-open the security-scoped project folder before validating, so the persisted path is
        // reachable under the sandbox. If the folder moved since last launch the bookmark tracks it —
        // adopt the new path; otherwise validate whatever path is persisted (which prompts the user
        // to re-pick if access is missing / there's no usable bookmark).
        if let resolvedRoot = projectAccess.restore(), resolvedRoot.path != project.context.projectPath {
            project.send(.setPath(resolvedRoot.path))
        } else {
            project.send(.restore)
        }
    }

    /// Enumerate installed AudioUnit effects the first time the user actually opens the insert-slot
    /// picker. Deliberately *not* called at launch: macOS caches AU *validation* system-wide
    /// (`~/Library/Caches/AudioUnitCache`), so this is a cheap metadata read rather than a per-launch
    /// re-scan — but the first `AVAudioUnitComponentManager` access still spins up the whole
    /// component-registry machinery (and emits benign CoreAudio init logging like the
    /// `AddInstanceForFactory` / `SetPropertyData 'nope'` lines). Deferring it keeps that entirely out
    /// of the launch path, and off the table completely for the common case where nobody touches the
    /// effects rack. Idempotent: the guard means repeat opens are no-ops.
    func ensureAudioEffectsLoaded() {
        guard !didStartEffectsLoad else { return }
        didStartEffectsLoad = true
        Task { [weak self] in
            let effects = await Task.detached(priority: .utility) { AudioUnitCatalog.effects() }.value
            self?.availableAudioEffects = effects
        }
    }

    private static func audioConfig(for soundSettings: SoundPalette) -> AudioSessionConfig {
        AudioSessionConfig(
            sampleRate: soundSettings.sampleRate,
            bufferSize: soundSettings.bufferSize,
            scheduleAheadBuffers: soundSettings.scheduleAheadBuffers,
            insertSlotCount: SoundtrackContext.insertSlotCount,
            enableMasterLimiter: false,
            maxTrackDuration: soundSettings.maxRenderedTrackDuration,
            tailDuration: soundSettings.trackEndTailDuration,
            gain: 0.2,
            spatialization: .psychoacoustic3D(.spacious)
        )
    }

    #if canImport(AppKit)
    /// The native editor view controller for the AU currently in soundtrack insert `slot`.
    func makeSoundtrackInsertEditor(slot: Int) async -> NSViewController? {
        await soundtrackDriver?.makeInsertEditor(slot: slot)
    }
    #endif

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Change the app appearance. Drives the `AppearanceMachine` (the statechart source of truth) and
    /// mirrors the choice into `AppStyleStore`, which re-themes the UI live and persists the selection.
    func selectAppearance(_ preview: StylePreview) {
        guard preview != AppStyleStore.shared.preview else { return }
        appearance.send(Self.appearanceEvent(for: preview))
        AppStyleStore.shared.preview = preview
    }

    /// The event that moves the appearance machine to the state matching `preview`.
    static func appearanceEvent(for preview: StylePreview) -> AppearanceEvent {
        switch preview {
        case .system: .useSystem
        case .dark: .useDark
        case .light: .useLight
        }
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func persistLastUsedSettings() {
        persistSettings()
    }

    func openLogsFolder() {
        AppFolderActions.openLogsFolder()
    }

    func openExportsFolder() {
        AppFolderActions.openExportsFolder()
    }

    // MARK: - Navigation

    func selectSection(_ section: AppSectionID) {
        navigation.send(.select(section))
    }

    /// Marks a section as torn off into its own window and removes it from the main tab bar. If it
    /// was the selected tab, the main window falls back to the first remaining attached section.
    func markDetached(_ section: AppSectionID) {
        guard !detachedSections.contains(section) else { return }
        detachedSections.insert(section)
        if selectedSection == section, let fallback = attachedSections.first {
            selectSection(fallback)
        }
    }

    /// Re-attaches a section when its detached window closes, so its tab reappears in the main bar.
    func markAttached(_ section: AppSectionID) {
        detachedSections.remove(section)
    }

    // MARK: - Project

    func setProjectPath(_ path: String) {
        project.send(.setPath(path))
    }

    /// Adopt a folder the user picked in an `NSOpenPanel`: persist a security-scoped bookmark to it
    /// (so access survives relaunch and reaches any location on disk), begin accessing it, then load
    /// it. Use this — not `setProjectPath` — for picker results so the sandbox grant is captured.
    func selectProjectDirectory(_ url: URL) {
        projectAccess.store(pickedURL: url)
        setProjectPath(url.path)
    }

    func refreshProject() {
        project.send(.refresh)
    }

    @ObservationIgnored private var lastActivationRefresh: Date = .distantPast

    /// When the app regains focus, re-resolve the project ONLY if the swift repo's git branch
    /// actually changed since we last validated (the branch is otherwise read only at validation
    /// time). A cheap off-main `git rev-parse` probe gates the full `.refresh`, so a plain alt-tab
    /// back to the app with nothing changed does NOT churn the machine / rebuild the UI. Skipped
    /// mid-build and debounced. Also recovers a cold-launch read that lost its race (the probe reads
    /// the real branch, sees it differs from the cached one, and refreshes).
    func refreshProjectOnActivation() {
        guard !build.matches(.running), let info = project.context.projectInfo else { return }
        let now = Date()
        guard now.timeIntervalSince(lastActivationRefresh) > 2 else { return }
        lastActivationRefresh = now

        let swiftDirectory = info.swiftDirectory
        let displayedBranch = info.swiftBranch
        Task { [weak self] in
            let current = await CheckoutSchemeResolver.currentBranch(in: swiftDirectory)
            // Only a real, readable branch change triggers a reload; nil (probe failed) or unchanged
            // leaves the current state — and the UI — untouched.
            guard let current, current != displayedBranch else { return }
            await MainActor.run { self?.project.send(.refresh) }
        }
    }

    func setBuildSubdir(_ subdir: String) {
        project.send(.setBuildSubdir(subdir))
    }

    func setCheckoutSchemeOverride(_ scheme: String) {
        project.send(.setCheckoutSchemeOverride(scheme))
    }

    func applyImportedProject(
        path: String,
        buildSubdir: String,
        options: BuildOptions,
        targetRepository: String
    ) async throws {
        restoreSettings(options, targetRepository)
        setBuildSubdir(buildSubdir)
        setProjectPath(path)
        try await waitForProjectReady()
        guard project.context.isValid else {
            let message = project.context.validationMessage ?? "Imported project path is invalid."
            throw SessionWaitError.projectInvalid(message: message)
        }
    }

    // MARK: - Build orchestration

    func startBuild(kind: BuildOperationKind, notes: String = "") async throws {
        do {
            guard let request = try makeRequest(kind: kind) else { return }
            let job = BuildJobPlanner.job(for: request)
            let record = insertRecord(for: job, options: request.options, notes: notes)
            trackedRecords[request.operationID] = record
            build.send(.startRequest(request))
            try await waitForBuildIdle()
            finalizeRecord(request.operationID)
            if kind == .updateDependencies {
                project.send(.refresh)
                try await waitForProjectReady()
            }
        } catch {
            report(error)
            throw error
        }
    }

    func startFreshDependency(notes: String = "Fresh ninja clean rebuild") async throws {
        do {
            guard let request = try makeRequest(
                kind: .dependencyBuild,
                mode: .freshNinjaClean
            ) else { return }
            let job = BuildJobPlanner.job(for: request)
            let record = insertRecord(for: job, options: request.options, notes: notes)
            trackedRecords[request.operationID] = record
            build.send(.startRequest(request))
            try await waitForBuildIdle()
            finalizeRecord(request.operationID)
        } catch {
            report(error)
            throw error
        }
    }

    func runUpdateThenRebuild() async {
        do {
            guard project.context.projectInfo != nil else {
                throw SessionWaitError.projectInvalid(message: ProjectInspectFailure.projectNotLoaded.errorDescription ?? "Project is not loaded.")
            }
            project.send(.captureRevisions)
            try await waitForProjectReady()
            try await startBuild(kind: .updateDependencies, notes: "Match swift commit timestamps")
            guard let info = project.context.projectInfo else { return }
            let changed = await ProjectService.changedRepositories(
                in: info,
                since: project.context.revisionsBeforeUpdate
            )
            guard !changed.isEmpty else {
                build.send(.setStatusMessage("All dependencies already matched the swift commit."))
                return
            }
            guard let request = try makeRequest(
                kind: .updateAndRebuild,
                mode: .command(changedRepositories: changed)
            ) else { return }
            let job = BuildJobPlanner.job(for: request)
            let record = insertRecord(
                for: job,
                options: request.options,
                notes: "Rebuild changed: \(changed.map(\.name).joined(separator: ", "))"
            )
            trackedRecords[request.operationID] = record
            build.send(.startRequest(request))
            try await waitForBuildIdle()
            finalizeRecord(request.operationID)
        } catch {
            report(error)
        }
    }

    func cancelBuild() {
        build.send(.cancel)
    }

    /// Check (once, in the background) what Xcode the ci.swift.org nodes run and compare it to the
    /// locally selected Xcode. Safe to call repeatedly — it only runs the first time. Any failure
    /// leaves `ciXcodeStatus` nil and the banner hidden.
    func checkCIXcode() {
        guard ciXcodeTask == nil else { return }
        ciXcodeTask = Task { [weak self] in
            let status = await CIXcodeChecker.check()
            self?.ciXcodeStatus = status
        }
    }

    /// Re-run the ci.swift.org Xcode check (e.g. after switching Xcode with `xcode-select`).
    func recheckCIXcode() {
        ciXcodeTask?.cancel()
        ciXcodeTask = nil
        checkCIXcode()
    }

    /// Update every repository (`update-checkout`) and then delete the given build sub-directory,
    /// leaving a clean tree for the next build. Does NOT start a build. Both the Build tab and the
    /// Toolchain tab surface this, each passing the sub-directory its own flow uses (they can be on
    /// different bot modes — e.g. an incremental dev subdir vs. `buildbot_osx` for toolchain packaging).
    func updateAndCleanBuildTree(subdir: String) async {
        do {
            guard project.context.projectInfo != nil else {
                throw SessionWaitError.projectInvalid(
                    message: ProjectInspectFailure.projectNotLoaded.errorDescription ?? "Project is not loaded."
                )
            }
            // Reuses the existing update-checkout pipeline (which also refreshes the project afterward).
            try await startBuild(kind: .updateDependencies, notes: "Update all repositories, then clean the build tree")
            try await cleanBuildSubdirectory(named: subdir)
        } catch {
            report(error)
        }
    }

    /// Delete `<buildRoot>/<name>` off-main, after proving it is a direct child of the project's build
    /// root so a bad value can never escape it. Refreshes the project so the detected sub-dirs update.
    private func cleanBuildSubdirectory(named subdir: String) async throws {
        guard let info = project.context.projectInfo else { return }
        // Collapse to a single path component: this can never contain a separator or `..` after this,
        // so the delete is confined to the build root.
        let name = (subdir.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            build.send(.setStatusMessage("No build sub-directory to clean."))
            return
        }
        let target = info.buildRoot.appendingPathComponent(name, isDirectory: true)
        guard target.deletingLastPathComponent().standardizedFileURL.path
            == info.buildRoot.standardizedFileURL.path else {
            build.send(.setStatusMessage("Refusing to clean a path outside the build root."))
            return
        }
        let path = target.path
        guard FileManager.default.fileExists(atPath: path) else {
            build.send(.setStatusMessage("build/\(name) was already clean."))
            return
        }
        build.send(.setStatusMessage("Cleaning build/\(name)…"))
        // Off-main: a multi-GB build tree can take a while to remove; never block the UI or the audio.
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(atPath: path)
        }.value
        build.send(.setStatusMessage("Cleaned build/\(name)."))
        project.send(.refresh)
    }

    // MARK: - Toolchain

    /// (Re)parse the swift checkout's `build-presets.ini` into the toolchain catalog. Safe to call
    /// with no project selected — the machine reports the missing-file state.
    func loadToolchainCatalog() {
        let path = project.context.projectInfo?.swiftDirectory
            .appendingPathComponent("utils/build-presets.ini").path ?? ""
        // Idempotent: if this exact catalog is already parsed, don't re-parse. Lets the background
        // warm-up's result stand so switching to the tab doesn't redo the work (and re-flash the
        // loader). A changed project path still reloads, since `presetFilePath` won't match.
        if toolchain.matches(.ready), toolchain.context.presetFilePath == path, !toolchain.context.catalog.isEmpty {
            return
        }
        toolchain.send(.load(path))
    }

    /// Pre-warm the Toolchain tab's one-time costs off the critical path, so the first switch to it
    /// doesn't spike CPU/disk while the soundtrack is playing (the transient render starvation that
    /// glitches audio without any soundtrack state change). Runs once, at low priority: warm the
    /// SwiftData store for the tab's models so the first `@Query` isn't a cold fetch, then parse the
    /// 231-entry preset catalog as soon as the project is ready. All harmless if the tab is never opened.
    func warmUpToolchain() {
        guard toolchainWarmupTask == nil else { return }
        toolchainWarmupTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            if let modelContext {
                _ = try? modelContext.fetchCount(FetchDescriptor<ToolchainRecipe>())
                _ = try? modelContext.fetchCount(FetchDescriptor<CustomPreset>())
            }
            try? await waitForProjectReady()
            guard !Task.isCancelled else { return }
            loadToolchainCatalog()
        }
    }

    /// The user's custom preset/mixin blocks, for `.ini` generation.
    func toolchainCustomPresets() -> [CustomPresetValue] {
        guard let modelContext else { return [] }
        return ((try? modelContext.fetch(FetchDescriptor<CustomPreset>())) ?? []).map(\.value)
    }

    /// Generate the overlay `~/<tag>-presets.ini` and run `build-toolchain` through the build pipeline.
    func buildToolchain(_ draft: ToolchainRecipeDraft) async {
        do {
            guard let info = project.context.projectInfo else {
                throw SessionWaitError.projectInvalid(message: "Choose a valid swift project first.")
            }
            let overlayText = ToolchainPresetWriter.overlay(draft: draft, customPresets: toolchainCustomPresets())
            let overlayURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("\(draft.bundleTag)-presets.ini")
            try overlayText.write(to: overlayURL, atomically: true, encoding: .utf8)

            let buildToolchainPath = info.swiftDirectory.appendingPathComponent("utils/build-toolchain").path
            let basePresetPath = info.swiftDirectory.appendingPathComponent("utils/build-presets.ini").path

            var arguments = [
                draft.bundleTag,
                "--preset-file", basePresetPath,
                "--preset-file", overlayURL.path,
                "--preset-prefix", draft.presetPrefix,
            ]
            for flag in draft.flags.sorted(by: { $0.rawValue < $1.rawValue }) {
                arguments.append(flag.argument)
            }

            let operationID = UUID()
            let job = BuildJob(
                operationID: operationID,
                kind: .buildToolchain,
                executable: buildToolchainPath,
                arguments: arguments,
                workingDirectory: info.root.path,
                displayCommand: ToolchainPresetWriter.commandPreview(
                    draft: draft,
                    buildToolchainPath: buildToolchainPath,
                    basePresetPath: basePresetPath,
                    overlayPath: overlayURL.path
                ),
                logFilePath: try AppPaths.logFileURL(for: operationID).path,
                projectPath: info.root.path,
                buildSubdir: "",
                targetRepository: draft.bundleTag
            )
            let record = insertRecord(for: job, options: .default, notes: "Toolchain: \(draft.name)")
            trackedRecords[operationID] = record
            build.send(.start(job))
            try await waitForBuildIdle()
            finalizeRecord(operationID)
        } catch {
            report(error)
        }
    }

    func replay(_ record: BuildOperationRecord) async {
        do {
            restoreSettings(record.options, record.targetRepository)
            setBuildSubdir(record.buildSubdir)
            setProjectPath(record.projectPath)
            try await waitForProjectReady()
            guard let request = try makeRequest(
                kind: record.kind,
                options: record.options,
                targetRepository: record.targetRepository
            ) else { return }
            let job = BuildJobPlanner.job(for: request)
            let replay = insertRecord(
                for: job,
                options: request.options,
                notes: "Replay of \(record.id.uuidString)"
            )
            trackedRecords[request.operationID] = replay
            build.send(.startRequest(request))
            try await waitForBuildIdle()
            finalizeRecord(request.operationID)
        } catch {
            report(error)
        }
    }

    // MARK: - Internals

    /// The build sub-directory the regular build flow writes into (the user's selection, else the
    /// first detected one). Exposed so the "Update & Clean Tree" button on the Build tab can target it.
    var effectiveBuildSubdir: String {
        let selected = project.context.selectedBuildSubdir
        if !selected.isEmpty { return selected }
        return project.context.projectInfo?.detectedBuildSubdirs.first ?? ""
    }

    /// The build sub-directory the macOS toolchain-packaging flow always uses: `build-toolchain`
    /// composes the `<prefix>buildbot_osx_package` preset, whose `build-subdir` is `buildbot_osx`.
    static let toolchainBuildSubdir = "buildbot_osx"

    /// UserDefaults key for the opt-in update-checkout `--match-timestamp` toggle (off by default). The
    /// Build tab's checkbox writes it via `@AppStorage`; `makeRequest` reads it into the build request.
    static let matchTimestampDefaultsKey = "updateCheckoutMatchTimestamp"

    private func makeRequest(
        kind: BuildOperationKind,
        options: BuildOptions? = nil,
        targetRepository: String? = nil,
        mode: BuildPlanningMode = .command()
    ) throws -> BuildRunRequest? {
        guard let info = project.context.projectInfo else {
            build.send(.setStatusMessage(project.context.validationMessage ?? "Project path is invalid."))
            return nil
        }
        persistSettings()
        let operationID = UUID()
        return BuildRunRequest(
            operationID: operationID,
            kind: kind,
            project: info,
            buildSubdir: effectiveBuildSubdir,
            options: options ?? settings.context.options,
            targetRepository: targetRepository ?? settings.context.selectedRepository,
            mode: mode,
            logFilePath: try AppPaths.logFileURL(for: operationID).path,
            matchTimestamp: UserDefaults.standard.bool(forKey: Self.matchTimestampDefaultsKey)
        )
    }

    @discardableResult
    private func insertRecord(for job: BuildJob, options: BuildOptions, notes: String) -> BuildOperationRecord {
        let record = BuildOperationRecord(
            id: job.operationID,
            kind: job.kind,
            projectPath: job.projectPath,
            buildSubdir: job.buildSubdir,
            targetRepository: job.targetRepository,
            commandLine: job.displayCommand,
            logFileName: "\(job.operationID.uuidString).log",
            options: options,
            notes: notes
        )
        record.status = .running
        modelContext?.insert(record)
        return record
    }

    private func finalizeRecord(_ operationID: UUID) {
        guard let record = trackedRecords[operationID] else { return }
        record.finishedAt = .now
        record.exitCode = Int(build.context.lastExitCode ?? -1)
        record.progress = build.context.progress.fraction
        record.etaSeconds = build.context.progress.etaSeconds
        if record.exitCode == 0, build.context.statusMessage == nil {
            record.status = .succeeded
        } else if build.context.statusMessage == "Build cancelled." {
            record.status = .cancelled
        } else {
            record.status = .failed
        }
        trackedRecords[operationID] = nil
    }

    private func waitForBuildIdle(timeout: Duration = AppSession.buildTimeout) async throws {
        // Snapshot-driven, not polled: the machine actor replays its current snapshot on subscribe
        // and pushes every transition; the AsyncStream bridge enforces the deadline.
        //
        // We deliberately do NOT mirror per-snapshot progress onto the tracked SwiftData record.
        // That fires ~10×/sec, and every write invalidates every `@Query<BuildOperationRecord>`
        // (History + live log), rebuilding those views on each tick even though nothing displays a
        // record's live `progress`. Live progress comes from the machine context (top bar); the
        // record only needs its final value, which `finalizeRecord` writes once the build settles.
        let snapshots = build.snapshots(timeout: timeout) {
            SessionWaitError.buildTimedOut(seconds: Int(timeout.components.seconds))
        }
        for try await snapshot in snapshots {
            if !(snapshot.configuration?.matches(.running) ?? false) { return }
        }
    }

    func waitForProjectReady(timeout: Duration = AppSession.projectLoadTimeout) async throws {
        let snapshots = project.snapshots(timeout: timeout) {
            SessionWaitError.projectLoadTimedOut(seconds: Int(timeout.components.seconds))
        }
        for try await snapshot in snapshots {
            if !(snapshot.configuration?.matches(.loading) ?? false), !snapshot.context.reloadPending {
                break
            }
        }
        if let message = project.context.validationMessage, !project.context.isValid {
            throw SessionWaitError.projectInvalid(message: message)
        }
    }

    private func report(_ error: any Error) {
        lastErrorMessage = localizedErrorMessage(for: error)
        build.send(.setStatusMessage(lastErrorMessage ?? "An unknown error occurred."))
    }

    private func restoreSettings(_ options: BuildOptions, _ selectedRepository: String) {
        settings.send(.restore(options, selectedRepository))
        LastUsedBuildSettingsStore.save(
            options: options,
            selectedRepository: selectedRepository,
            to: settingsDefaults
        )
    }

    private func persistSettings() {
        LastUsedBuildSettingsStore.save(
            options: settings.context.options,
            selectedRepository: settings.context.selectedRepository,
            to: settingsDefaults
        )
    }
}

extension AppSession {
    /// Wrap an inspect sink so events originating from actors whose `systemId` is in `hidingSystemIds`
    /// are dropped before they reach the inspector. Used to keep transient background invoke children
    /// (the "parse"/"inspect" helpers) out of the actor list; events where a hidden actor is merely
    /// the `source` (e.g. its done-event delivered to the parent) still pass through under the parent.
    nonisolated static func filteredInspect(
        _ sink: @escaping @Sendable (InspectionEvent) -> Void,
        hidingSystemIds hidden: Set<String>
    ) -> @Sendable (InspectionEvent) -> Void {
        { event in
            if let systemId = event.actor.systemId, hidden.contains(systemId) { return }
            sink(event)
        }
    }
}

@MainActor
private func inspectedStore<M: StateMachine>(
    _ machine: M,
    id: String,
    systemId: String,
    inspect: @escaping @Sendable (InspectionEvent) -> Void
) -> MachineStore<M> {
    let actor = createActor(
        machine,
        id: id,
        options: ActorOptions(systemId: systemId),
        inspect: inspect
    )
    return MachineStore(actor: actor, initialContext: machine.context)
}

@MainActor
private func nonInspectedStore<M: StateMachine>(
    _ machine: M,
    id: String,
    systemId: String,
) -> MachineStore<M> {
    let actor = createActor(
        machine,
        id: id,
        options: ActorOptions(systemId: systemId)
    )
    return MachineStore(actor: actor, initialContext: machine.context)
}
