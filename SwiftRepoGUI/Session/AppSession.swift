import Foundation
import Observation
import Ox0badf00d
import SwiftData
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

    @ObservationIgnored private weak var modelContext: ModelContext?
    @ObservationIgnored private let settingsDefaults: UserDefaults
    @ObservationIgnored private var soundtrackDriver: SoundtrackEffectDriver?
    @ObservationIgnored private var trackedRecords: [UUID: BuildOperationRecord] = [:]
    @ObservationIgnored private var didStartEffectsLoad = false
    @ObservationIgnored private(set) var lastErrorMessage: String?

    /// Installed AudioUnit effects the user can drop into a soundtrack insert slot. Populated lazily
    /// by `ensureAudioEffectsLoaded()` the first time the effects rack is opened — never at launch.
    /// Observed, so the deck's slot picker fills in when the (off-main) enumeration completes.
    private(set) var availableAudioEffects: [AudioComponentRef] = []

    var selectedSection: AppSectionID { navigation.context.section }

    init(modelContext: ModelContext? = nil, settingsDefaults: UserDefaults = .standard) {
        //NSLog("%@", "[OxAudio] AppSession.init")
        self.modelContext = modelContext
        self.settingsDefaults = settingsDefaults
        let mainStore = MainStore()
        let inspectorStore = InspectorStore()
        let inspect = inspectorStore.observe()
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
        let soundStyle = SwiftBuilderStyle.current.sound
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

        if let lastUsedSettings = LastUsedBuildSettingsStore.load(from: settingsDefaults) {
            settings.send(.restore(lastUsedSettings.options, lastUsedSettings.selectedRepository))
        }
        project.send(.restore)
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

    private static func audioConfig(for style: SoundPalette) -> AudioSessionConfig {
        AudioSessionConfig(
            sampleRate: style.sampleRate,
            maximumFramesToRender: 4_096,
            renderChunkFrames: style.streamRenderChunkFrames,
            scheduleAheadBuffers: 3,
            insertSlotCount: SoundtrackContext.insertSlotCount,
            enableMasterLimiter: false,
            maxTrackDuration: style.maxRenderedTrackDuration,
            tailDuration: style.trackEndTailDuration,
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

    // MARK: - Project

    func setProjectPath(_ path: String) {
        project.send(.setPath(path))
    }

    func refreshProject() {
        project.send(.refresh)
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

    private var effectiveBuildSubdir: String {
        let selected = project.context.selectedBuildSubdir
        if !selected.isEmpty { return selected }
        return project.context.projectInfo?.detectedBuildSubdirs.first ?? ""
    }

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
            logFilePath: try AppPaths.logFileURL(for: operationID).path
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
        // and pushes every transition; the AsyncStream bridge enforces the deadline. Progress
        // mirroring onto the tracked record now happens per snapshot (formerly per poll tick).
        let snapshots = build.snapshots(timeout: timeout) {
            SessionWaitError.buildTimedOut(seconds: Int(timeout.components.seconds))
        }
        for try await snapshot in snapshots {
            if let operationID = snapshot.context.lastOperationID,
               let record = trackedRecords[operationID] {
                record.progress = snapshot.context.progress.fraction
                record.etaSeconds = snapshot.context.progress.etaSeconds
            }
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
