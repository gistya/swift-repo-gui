import SwiftXState

struct SoundtrackAudioMachine: StateMachine {
    typealias Context = SoundtrackAudioContext
    typealias StateID = SoundtrackAudioMachineState
    typealias EventID = SoundtrackAudioEvent

    var context: SoundtrackAudioContext { .init() }
    var isParallel: Bool { true }

    var machine: some XStateMachine {
        XState(.playback) {
            XState(.notPlaying) {
                for transition in Self.notPlayingTransitions() {
                    transition
                }
            }
            .initial()

            XState(.playing) {
                for transition in Self.playingTransitions() {
                    transition
                }
            }
        }

        XState(.tubeRack) {
            XState(.tubeRackOff) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
            .initial()

            XState(.tubeRackOn) {
                for transition in Self.tubeRackTransitions() {
                    transition
                }
            }
        }
    }

    private static func notPlayingTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.trackReady, to: .notPlaying)
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setVolume, to: .notPlaying)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: .play, to: .playing)
                .when { $0.currentTrack != nil }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .playing
                    ctx.lastError = nil
                    return ctx
                },
            XTransition(on: .pause, to: .notPlaying)
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: .stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackAudioEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
        ]
    }

    private static func playingTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setVolume, to: .playing)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: .pause, to: .notPlaying)
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: .stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackAudioEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
        ]
    }

    private static func tubeRackTransitions() -> [XTransition<SoundtrackAudioContext, SoundtrackAudioEvent, SoundtrackAudioMachineState>] {
        [
            XTransition(on: SoundtrackAudioEvent.setEffects, to: .tubeRackOn)
                .when { _, event in Self.effectsEnabled(event) }
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
            XTransition(on: SoundtrackAudioEvent.setEffects, to: .tubeRackOff)
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
        ]
    }

    private static func applyTrackRequest(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        guard case let .requestTrack(track, purpose, generation)? = event else { return ctx }
        ctx.phase = .loading
        ctx.currentTrack = track
        ctx.activePurpose = purpose
        ctx.moduleTitle = nil
        ctx.generation = generation
        ctx.lastError = nil
        return ctx
    }

    private static func applyTrackReady(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        guard case let .trackReady(moduleTitle, generation)? = event,
              generation == ctx.generation else { return ctx }
        ctx.phase = .ready
        ctx.moduleTitle = moduleTitle
        ctx.lastError = nil
        return ctx
    }

    private static func applyVolume(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .setVolume(volume)? = event {
            ctx.volume = min(1, max(0, volume))
        }
        return ctx
    }

    private static func applyEffects(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .setEffects(settings)? = event {
            ctx.effectsSettings = settings.normalized()
        }
        return ctx
    }

    private static func applyStop(_ context: SoundtrackAudioContext) -> SoundtrackAudioContext {
        var ctx = context
        ctx.phase = .stopped
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        return ctx
    }

    private static func applyFailure(
        _ event: SoundtrackAudioEvent?,
        to context: SoundtrackAudioContext
    ) -> SoundtrackAudioContext {
        var ctx = context
        if case let .fail(message)? = event {
            ctx.phase = .failed
            ctx.lastError = message
        }
        return ctx
    }

    private static func effectsEnabled(_ event: SoundtrackAudioEvent?) -> Bool {
        guard case let .setEffects(settings)? = event else { return false }
        return settings.normalized().isEnabled
    }
}
