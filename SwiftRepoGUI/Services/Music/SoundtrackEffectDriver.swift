import Foundation
import SwiftXStateSwiftUI

@MainActor
final class SoundtrackEffectDriver {
    private struct PreferenceSnapshot: Equatable {
        var isMuted: Bool
        var volume: Double
        var effectsSettings: SoundtrackEffectsSettings
    }

    private let store: MachineStore<SoundtrackMachine>
    private let audioActor: SoundtrackAudioActor
    private let defaults: UserDefaults

    private var snapshotTask: Task<Void, Never>?
    private var finishedTask: Task<Void, Never>?
    private var lastHandledRequestID = 0
    private var lastPersistedPreferences: PreferenceSnapshot?

    init(
        store: MachineStore<SoundtrackMachine>,
        style: SoundPalette,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
        audioActor = SoundtrackAudioActor(
            style: style,
            volume: Float(store.context.volume),
            effectsSettings: store.context.effectsSettings
        )

        let snapshots = store.snapshots
        snapshotTask = Task { @MainActor [weak self] in
            for await snapshot in snapshots {
                self?.handle(snapshot.context)
            }
        }

        let finishedGenerations = audioActor.finishedGenerations
        finishedTask = Task { @MainActor [weak self] in
            for await generation in finishedGenerations {
                self?.store.send(.trackFinished(generation: generation))
            }
        }
    }

    deinit {
        snapshotTask?.cancel()
        finishedTask?.cancel()
    }

    private func handle(_ context: SoundtrackContext) {
        persistPreferencesIfNeeded(context)

        guard let request = context.pendingAudioRequest,
              request.id > lastHandledRequestID else { return }
        lastHandledRequestID = request.id
        execute(request)
    }

    private func persistPreferencesIfNeeded(_ context: SoundtrackContext) {
        let snapshot = PreferenceSnapshot(
            isMuted: context.isMuted,
            volume: context.volume,
            effectsSettings: context.effectsSettings
        )
        guard snapshot != lastPersistedPreferences else { return }
        lastPersistedPreferences = snapshot
        defaults.set(snapshot.isMuted, forKey: SoundtrackDefaults.mutedKey)
        defaults.set(snapshot.volume, forKey: SoundtrackDefaults.volumeKey)
        SoundtrackEffectsSettingsStore.save(snapshot.effectsSettings, to: defaults)
    }

    private func execute(_ request: SoundtrackAudioRequest) {
        switch request.command {
        case let .play(streamRequest, generation, startImmediately):
            Task { [weak self] in
                guard let self else { return }
                let prepared = await audioActor.play(
                    request: streamRequest,
                    generation: generation,
                    startImmediately: startImmediately
                )
                if prepared.succeeded {
                    store.send(.playbackPrepared(
                        moduleTitle: prepared.moduleTitle,
                        generation: generation,
                        started: startImmediately
                    ))
                } else {
                    store.send(.audioFailed(
                        "Could not stream \(prepared.track.fileName): \(prepared.errorMessage ?? "Unknown error")",
                        generation: generation
                    ))
                }
            }
        case let .pause(generation):
            Task { [weak self] in
                guard let self else { return }
                if let message = await audioActor.pause() {
                    store.send(.audioFailed(message, generation: generation))
                } else {
                    store.send(.playbackPaused(generation: generation))
                }
            }
        case let .resume(generation):
            Task { [weak self] in
                guard let self else { return }
                if let message = await audioActor.resume() {
                    store.send(.audioFailed(message, generation: generation))
                } else {
                    store.send(.playbackResumed(generation: generation))
                }
            }
        case let .stop(generation):
            Task { [weak self] in
                guard let self else { return }
                await audioActor.stop()
                store.send(.playbackStopped(generation: generation))
            }
        case let .setVolume(volume):
            Task { [weak self] in
                guard let self else { return }
                await audioActor.setVolume(volume)
                store.send(.audioRequestHandled(request.id))
            }
        case let .setEffects(settings):
            Task { [weak self] in
                guard let self else { return }
                await audioActor.setEffectsSettings(settings)
                store.send(.audioRequestHandled(request.id))
            }
        }
    }
}
