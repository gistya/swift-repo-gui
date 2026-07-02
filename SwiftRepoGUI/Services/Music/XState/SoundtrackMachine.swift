import SwiftXState

struct SoundtrackMachine: StateMachine {
    typealias Context = SoundtrackContext
    typealias StateID = SoundtrackMachineState
    typealias EventID = SoundtrackEvent

    var context: SoundtrackContext { .init() }
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

    private static func notPlayingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .notPlaying)
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .notPlaying)
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setVolume, to: .notPlaying)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setPurpose, to: .notPlaying)
                .action { args, _ in Self.applyPurpose(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.trackReady, to: .playing)
                .when { ctx, event in Self.canPlayTrackReady(event, context: ctx) }
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context, phase: .playing) },
            XTransition(on: SoundtrackEvent.trackReady, to: .notPlaying)
                .action { args, _ in Self.applyTrackReady(args.event, to: args.context, phase: .stopped) },
            XTransition(on: SoundtrackEvent.resume, to: .playing)
                .when { $0.currentTrack != nil && !$0.isMuted }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .playing
                    return ctx
                },
            XTransition(on: SoundtrackEvent.resume, to: .notPlaying)
                .action { args, _ in Self.applyResume(args.context) },
            XTransition(on: SoundtrackEvent.stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.finish, to: .notPlaying)
                .action { args, _ in Self.applyFinish(args.context) },
        ]
    }

    private static func playingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .notPlaying)
                .when { _, event in Self.restoreMutes(event) }
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.restore, to: .playing)
                .action { args, _ in Self.applyRestore(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .notPlaying)
                .when { _, event in Self.muteEventTurnsOff(event) }
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setMuted, to: .playing)
                .action { args, _ in Self.applyMuted(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setVolume, to: .playing)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setPurpose, to: .playing)
                .action { args, _ in Self.applyPurpose(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.requestTrack, to: .notPlaying)
                .action { args, _ in Self.applyTrackRequest(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.pause, to: .notPlaying)
                .when { $0.currentTrack != nil && !$0.isMuted }
                .action { ctx in
                    var ctx = ctx
                    ctx.phase = .paused
                    return ctx
                },
            XTransition(on: SoundtrackEvent.stop, to: .notPlaying)
                .action { args, _ in Self.applyStop(args.context) },
            XTransition(on: SoundtrackEvent.fail, to: .notPlaying)
                .action { args, _ in Self.applyFailure(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.finish, to: .notPlaying)
                .action { args, _ in Self.applyFinish(args.context) },
        ]
    }

    private static func tubeRackTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackMachineState>] {
        [
            XTransition(on: SoundtrackEvent.restore, to: .tubeRackOn)
                .when { _, event in Self.restoreEffectsEnabled(event) },
            XTransition(on: SoundtrackEvent.restore, to: .tubeRackOff),
            XTransition(on: SoundtrackEvent.setEffects, to: .tubeRackOn)
                .when { _, event in Self.effectsEnabled(event) }
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setEffects, to: .tubeRackOff)
                .action { args, _ in Self.applyEffects(args.event, to: args.context) },
        ]
    }

    private static func applyRestore(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .restore(muted, volume, effects)? = event {
            ctx.isMuted = muted
            ctx.volume = min(1, max(0, volume))
            ctx.effectsSettings = effects.normalized()
            if muted {
                ctx.phase = .stopped
                ctx.currentTrack = nil
                ctx.nowPlaying = .empty
            }
        }
        return ctx
    }

    private static func applyMuted(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setMuted(muted)? = event {
            ctx.isMuted = muted
            ctx.lastError = nil
            if muted {
                ctx.phase = .stopped
                ctx.currentTrack = nil
                ctx.nowPlaying = .empty
            }
        }
        return ctx
    }

    private static func applyVolume(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setVolume(volume)? = event {
            ctx.volume = min(1, max(0, volume))
        }
        return ctx
    }

    private static func applyEffects(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setEffects(settings)? = event {
            ctx.effectsSettings = settings.normalized()
        }
        return ctx
    }

    private static func applyPurpose(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .setPurpose(purpose)? = event {
            ctx.activePurpose = purpose
        }
        return ctx
    }

    private static func applyTrackRequest(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .requestTrack(track, purpose, generation)? = event {
            ctx.phase = .loading
            ctx.currentTrack = track
            ctx.nowPlaying = track.nowPlaying(moduleTitle: nil)
            ctx.activePurpose = purpose
            ctx.generation = generation
            ctx.lastError = nil
        }
        return ctx
    }

    private static func applyTrackReady(
        _ event: SoundtrackEvent?,
        to context: SoundtrackContext,
        phase: SoundtrackPhase
    ) -> SoundtrackContext {
        var ctx = context
        if case let .trackReady(track, moduleTitle, generation)? = event,
           generation == ctx.generation {
            ctx.currentTrack = track
            ctx.nowPlaying = track.nowPlaying(moduleTitle: moduleTitle)
            ctx.phase = phase
            ctx.lastError = nil
        }
        return ctx
    }

    private static func applyResume(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard !ctx.isMuted else { return ctx }
        ctx.phase = ctx.currentTrack == nil ? .stopped : .playing
        return ctx
    }

    private static func applyStop(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.phase = .stopped
        ctx.currentTrack = nil
        ctx.nowPlaying = .empty
        return ctx
    }

    private static func applyFailure(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .fail(message)? = event {
            ctx.phase = .failed
            ctx.lastError = message
        }
        return ctx
    }

    private static func applyFinish(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.phase = .stopped
        return ctx
    }

    private static func canPlayTrackReady(_ event: SoundtrackEvent?, context: SoundtrackContext) -> Bool {
        guard !context.isMuted,
              case let .trackReady(_, _, generation)? = event else { return false }
        return generation == context.generation
    }

    private static func restoreMutes(_ event: SoundtrackEvent?) -> Bool {
        guard case let .restore(muted, _, _)? = event else { return false }
        return muted
    }

    private static func muteEventTurnsOff(_ event: SoundtrackEvent?) -> Bool {
        guard case let .setMuted(muted)? = event else { return false }
        return muted
    }

    private static func restoreEffectsEnabled(_ event: SoundtrackEvent?) -> Bool {
        guard case let .restore(_, _, effects)? = event else { return false }
        return effects.normalized().isEnabled
    }

    private static func effectsEnabled(_ event: SoundtrackEvent?) -> Bool {
        guard case let .setEffects(settings)? = event else { return false }
        return settings.normalized().isEnabled
    }
}
