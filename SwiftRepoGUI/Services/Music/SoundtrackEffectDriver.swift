import Foundation
import Ox0badf00d
import SwiftXStateSwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// The membrane between the `SoundtrackMachine` and the `TrackerAudioEngine`.
///
/// - Machine → engine: observes the machine's snapshot stream, drains the single pending audio
///   command from context, and feeds commands through a **serial** consumer so they reach the engine
///   in production order (the actor serializes execution; this serializes issuance).
/// - Engine → machine: forwards `TrackerAudioEvent`s back as machine events, keeping the whole loop
///   unidirectional (intent in context → effect in the actor → result as an event).
///
/// It also mirrors user preferences (mute/volume/insert slots) to `UserDefaults`.
@MainActor
final class SoundtrackEffectDriver {
    private struct PreferenceSnapshot: Equatable {
        var isMuted: Bool
        var volume: Double
        var insertSlots: [SoundtrackInsertSlot]
    }

    private let store: MachineStore<SoundtrackMachine>
    private let engine: TrackerAudioEngine
    private let defaults: UserDefaults

    private var eventsTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let commandStream: AsyncStream<SoundtrackAudioRequest>
    private let commandContinuation: AsyncStream<SoundtrackAudioRequest>.Continuation

    private var lastHandledRequestID = 0
    private var lastPersistedPreferences: PreferenceSnapshot?

    init(
        store: MachineStore<SoundtrackMachine>,
        config: AudioSessionConfig,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
        self.engine = TrackerAudioEngine(config: config)

        let commands = AsyncStream<SoundtrackAudioRequest>.makeStream(bufferingPolicy: .unbounded)
        self.commandStream = commands.stream
        self.commandContinuation = commands.continuation

        let initialContext = store.context
        let engine = self.engine
        let store = self.store

        // Engine outcomes → machine events.
        let events = engine.events
        eventsTask = Task { @MainActor [weak self] in
            for await event in events {
                self?.forward(event)
            }
        }

        // Serial command execution: preserves issue order, and lets deinit cancel outstanding work.
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await request in commandStream {
                await perform(request.command)
                store.send(.audioRequestHandled(request.id))
            }
        }

        // Snapshot stream → drain the pending request + persist preferences.
        let snapshots = store.snapshots
        snapshotTask = Task { @MainActor [weak self] in
            for await snapshot in snapshots {
                self?.handle(snapshot.context)
            }
        }

        // Ordered startup: apply the persisted audio settings (master volume, THEN insert slots) to
        // the live engine, and only then kick the machine's default `.launch` behavior. Auto-play
        // therefore never begins until the saved state is fully loaded — so the startup track can't
        // play a fraction of a second at the wrong volume (or without its effect chain) before those
        // settings land. Owning `.launch` here rather than in the view's `.onAppear` is what
        // guarantees the ordering; `.launch` is idempotent (`startupPlayed`) so nothing can double it.
        startupTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            await engine.setVolume(initialContext.volume)
            for (index, slot) in initialContext.insertSlots.enumerated() where slot.component != nil {
                do {
                    try await engine.setInsert(slot: index, component: slot.component)
                    await engine.setInsertBypass(slot: index, bypassed: slot.isBypassed)
                } catch {
                    // Persisted plugin can't be hosted here (missing / incompatible format). Clear it
                    // so it isn't retried every launch and the UI reflects the real state.
                    store.send(.setInsertSlot(index: index, component: nil))
                }
            }
            store.send(.launch)
        }
    }

    deinit {
        eventsTask?.cancel()
        snapshotTask?.cancel()
        commandTask?.cancel()
        startupTask?.cancel()
        commandContinuation.finish()
    }

    private func handle(_ context: SoundtrackContext) {
        persistPreferencesIfNeeded(context)
        guard let request = context.pendingAudioRequest, request.id > lastHandledRequestID else { return }
        lastHandledRequestID = request.id
        commandContinuation.yield(request)
    }

    private func forward(_ event: TrackerAudioEvent) {
        switch event {
        case let .prepared(title, generation, started):
            store.send(.playbackPrepared(moduleTitle: title, generation: generation, started: started))
        case let .paused(generation):
            store.send(.playbackPaused(generation: generation))
        case let .resumed(generation):
            store.send(.playbackResumed(generation: generation))
        case let .stopped(generation):
            store.send(.playbackStopped(generation: generation))
        case let .finished(generation):
            store.send(.trackFinished(generation: generation))
        case let .failed(message, generation):
            store.send(.audioFailed(message, generation: generation))
        }
    }

    private func perform(_ command: SoundtrackAudioCommand) async {
        switch command {
        case let .play(url, generation, startImmediately):
            await engine.play(moduleURL: url, generation: generation, startImmediately: startImmediately)
        case let .pause(generation):
            await engine.pause(generation: generation)
        case let .resume(generation):
            await engine.resume(generation: generation)
        case let .stop(generation):
            await engine.stop(generation: generation)
        case let .setVolume(volume):
            await engine.setVolume(volume)
        case let .setInsert(index, component):
            do {
                try await engine.setInsert(slot: index, component: component)
            } catch {
                // The chosen plugin can't be hosted (e.g. mono-only AU on a stereo bus): clear it.
                if component != nil {
                    store.send(.setInsertSlot(index: index, component: nil))
                }
            }
        case let .setInsertBypass(index, bypassed):
            await engine.setInsertBypass(slot: index, bypassed: bypassed)
        }
    }

    private func persistPreferencesIfNeeded(_ context: SoundtrackContext) {
        let snapshot = PreferenceSnapshot(
            isMuted: context.isMuted,
            volume: context.volume,
            insertSlots: context.insertSlots
        )
        guard snapshot != lastPersistedPreferences else { return }
        lastPersistedPreferences = snapshot
        defaults.set(snapshot.isMuted, forKey: SoundtrackDefaults.mutedKey)
        defaults.set(snapshot.volume, forKey: SoundtrackDefaults.volumeKey)
        SoundtrackInsertSlotsStore.save(snapshot.insertSlots, to: defaults)
    }

    #if canImport(AppKit)
    /// The chosen AU's own editor view controller for `slot`, for the host to present in a sheet.
    func makeInsertEditor(slot: Int) async -> NSViewController? {
        await engine.makeInsertViewController(slot: slot)
    }
    #endif
}
