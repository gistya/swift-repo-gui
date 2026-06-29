import Foundation
import Observation
import SwiftData
import SwiftXState
import SwiftXStateSwiftUI

/// The app's view model: a `MainStore` collating typed machines on the main actor.
/// Persistence (SwiftData) and panel/file dialogs live here; machines stay pure interpreters.
@MainActor
@Observable
final class AppSession {
    let store = MainStore()

    let navigation: MachineStore<AppNavigationMachine>
    let project: MachineStore<ProjectMachine>
    let settings: MachineStore<BuildSettingsMachine>
    let build: MachineStore<BuildOperationsMachine>

    @ObservationIgnored private weak var modelContext: ModelContext?
    @ObservationIgnored private var trackedRecords: [UUID: BuildOperationRecord] = [:]

    var selectedSection: AppSectionID { navigation.context.section }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        navigation = store.track(AppNavigationMachine())
        project = store.track(ProjectMachine())
        settings = store.track(BuildSettingsMachine())
        build = store.track(BuildOperationsMachine())

        project.send(.restore)
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    // MARK: - Build orchestration

    func startBuild(kind: BuildOperationKind, notes: String = "") async {
        guard let job = makeJob(kind: kind, notes: notes) else { return }
        let record = insertRecord(for: job, notes: notes)
        trackedRecords[job.operationID] = record
        build.send(.start(job))
        await waitForBuildIdle()
        finalizeRecord(job.operationID)
        if kind == .updateDependencies {
            project.send(.refresh)
            await waitForProjectReady()
        }
    }

    func startFreshDependency(notes: String = "Fresh ninja clean rebuild") async {
        guard let projectInfo = project.context.projectInfo else { return }
        let buildSubdir = effectiveBuildSubdir
        let repo = settings.context.selectedRepository
        let built = BuildCommandBuilder.freshNinjaClean(
            project: projectInfo,
            buildSubdir: buildSubdir,
            repoName: repo == "swift" ? "swift" : repo
        )
        let operationID = UUID()
        let job = BuildJob(
            operationID: operationID,
            kind: .dependencyBuild,
            executable: built.executable,
            arguments: built.arguments,
            workingDirectory: built.workingDirectory.path,
            displayCommand: built.display,
            logFilePath: AppPaths.logFileURL(for: operationID).path,
            projectPath: projectInfo.root.path,
            buildSubdir: buildSubdir,
            targetRepository: repo
        )
        let record = insertRecord(for: job, notes: notes)
        trackedRecords[operationID] = record
        build.send(.start(job))
        await waitForBuildIdle()
        finalizeRecord(operationID)
    }

    func runUpdateThenRebuild() async {
        project.send(.captureRevisions)
        await waitForProjectReady()
        await startBuild(kind: .updateDependencies, notes: "Match swift commit timestamps")
        guard let info = project.context.projectInfo else { return }
        let changed = ProjectService.changedRepositories(
            in: info,
            since: project.context.revisionsBeforeUpdate
        )
        guard !changed.isEmpty else {
            build.send(.setStatusMessage("All dependencies already matched the swift commit."))
            return
        }
        let rebuild = BuildCommandBuilder.command(
            kind: .updateAndRebuild,
            project: info,
            buildSubdir: effectiveBuildSubdir,
            options: settings.context.options,
            changedRepositories: changed
        )

        let operationID = UUID()
        let job = BuildJob(
            operationID: operationID,
            kind: .updateAndRebuild,
            executable: rebuild.executable,
            arguments: rebuild.arguments,
            workingDirectory: rebuild.workingDirectory.path,
            displayCommand: rebuild.display,
            logFilePath: AppPaths.logFileURL(for: operationID).path,
            projectPath: info.root.path,
            buildSubdir: effectiveBuildSubdir,
            targetRepository: changed.map(\.name).joined(separator: ", ")
        )
        let record = insertRecord(
            for: job,
            notes: "Rebuild changed: \(changed.map(\.name).joined(separator: ", "))"
        )
        trackedRecords[operationID] = record
        build.send(.start(job))
        await waitForBuildIdle()
        finalizeRecord(operationID)
    }

    func cancelBuild() {
        build.send(.cancel)
    }

    func replay(_ record: BuildOperationRecord) async {
        settings.send(.restore(record.options, record.targetRepository))
        project.send(.setPath(record.projectPath))
        project.send(.setBuildSubdir(record.buildSubdir))
        project.send(.refresh)
        await waitForProjectReady()
        guard let job = makeJob(
            kind: record.kind,
            notes: "Replay of \(record.id.uuidString)",
            options: record.options,
            targetRepository: record.targetRepository
        ) else { return }
        let replay = insertRecord(for: job, notes: "Replay of \(record.id.uuidString)")
        trackedRecords[job.operationID] = replay
        build.send(.start(job))
        await waitForBuildIdle()
        finalizeRecord(job.operationID)
    }

    // MARK: - Internals

    private var effectiveBuildSubdir: String {
        let selected = project.context.selectedBuildSubdir
        if !selected.isEmpty { return selected }
        return project.context.projectInfo?.detectedBuildSubdirs.first ?? ""
    }

    private func makeJob(
        kind: BuildOperationKind,
        notes: String,
        options: BuildOptions? = nil,
        targetRepository: String? = nil
    ) -> BuildJob? {
        guard let info = project.context.projectInfo else {
            build.send(.setStatusMessage(project.context.validationMessage ?? "Project path is invalid."))
            return nil
        }
        let buildSubdir = effectiveBuildSubdir
        let built = BuildCommandBuilder.command(
            kind: kind,
            project: info,
            buildSubdir: buildSubdir,
            options: options ?? settings.context.options,
            targetRepository: targetRepository ?? settings.context.selectedRepository
        )
        let operationID = UUID()
        return BuildJob(
            operationID: operationID,
            kind: kind,
            executable: built.executable,
            arguments: built.arguments,
            workingDirectory: built.workingDirectory.path,
            displayCommand: built.display,
            logFilePath: AppPaths.logFileURL(for: operationID).path,
            projectPath: info.root.path,
            buildSubdir: buildSubdir,
            targetRepository: targetRepository ?? settings.context.selectedRepository
        )
    }

    @discardableResult
    private func insertRecord(for job: BuildJob, notes: String) -> BuildOperationRecord {
        let record = BuildOperationRecord(
            id: job.operationID,
            kind: job.kind,
            projectPath: job.projectPath,
            buildSubdir: job.buildSubdir,
            targetRepository: job.targetRepository,
            commandLine: job.displayCommand,
            logFileName: "\(job.operationID.uuidString).log",
            options: settings.context.options,
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
        if record.exitCode == 0 {
            record.status = .succeeded
        } else if build.context.statusMessage == "Build cancelled." {
            record.status = .cancelled
        } else {
            record.status = .failed
        }
        trackedRecords[operationID] = nil
    }

    private func waitForBuildIdle() async {
        while build.matches(.running) {
            if let record = trackedRecords[build.context.lastOperationID ?? UUID()] {
                record.progress = build.context.progress.fraction
                record.etaSeconds = build.context.progress.etaSeconds
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func waitForProjectReady() async {
        while project.matches(.loading) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}