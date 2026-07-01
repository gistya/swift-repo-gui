import Foundation
import Observation
import SwiftData
import SwiftXState
import SwiftXStateSwiftUI

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
    static let projectLoadTimeout: Duration = .seconds(120)
    static let buildTimeout: Duration = .seconds(86_400)

    let store = MainStore()

    let navigation: MachineStore<AppNavigationMachine>
    let project: MachineStore<ProjectMachine>
    let settings: MachineStore<BuildSettingsMachine>
    let build: MachineStore<BuildOperationsMachine>

    @ObservationIgnored private weak var modelContext: ModelContext?
    @ObservationIgnored private let settingsDefaults: UserDefaults
    @ObservationIgnored private var trackedRecords: [UUID: BuildOperationRecord] = [:]
    @ObservationIgnored private(set) var lastErrorMessage: String?

    var selectedSection: AppSectionID { navigation.context.section }

    init(modelContext: ModelContext? = nil, settingsDefaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.settingsDefaults = settingsDefaults
        navigation = store.track(AppNavigationMachine())
        project = store.track(ProjectMachine())
        settings = store.track(BuildSettingsMachine())
        build = store.track(BuildOperationsMachine())

        if let lastUsedSettings = LastUsedBuildSettingsStore.load(from: settingsDefaults) {
            settings.send(.restore(lastUsedSettings.options, lastUsedSettings.selectedRepository))
        }
        project.send(.restore)
    }

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
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while build.matches(.running) {
            if clock.now >= deadline {
                throw SessionWaitError.buildTimedOut(seconds: Int(timeout.components.seconds))
            }
            if let record = trackedRecords[build.context.lastOperationID ?? UUID()] {
                record.progress = build.context.progress.fraction
                record.etaSeconds = build.context.progress.etaSeconds
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    func waitForProjectReady(timeout: Duration = AppSession.projectLoadTimeout) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while project.matches(.loading) || project.context.reloadPending {
            if clock.now >= deadline {
                throw SessionWaitError.projectLoadTimedOut(seconds: Int(timeout.components.seconds))
            }
            try await Task.sleep(for: .milliseconds(50))
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
