import Ox0badf00dAVFoundation
import SwiftRepoCore
import SwiftXState

struct SoundtrackMachine: StateMachine {
    typealias Context = SoundtrackContext
    typealias StateID = SoundtrackState
    typealias EventID = SoundtrackEvent

    let initialContext: SoundtrackContext

    init(context: SoundtrackContext = .initial(
        style: MusicSettings.current,
        tracks: TrackerModuleLibrary.discover()
    )) {
        initialContext = context
    }

    var context: SoundtrackContext { initialContext }

    // A flat statechart: the active position is a single playback leaf. Effect enablement is plain
    // context data (`effectsSettings.isEnabled` / the insert-slot config), NOT a parallel machine
    // region — so `matches(.paused)` etc. resolve correctly and the chart maps cleanly onto the
    // AudioUnit-slot model.
    var machine: some XStateMachine {
        State(.stopped) {
            for transition in Self.stoppedTransitions() {
                transition
            }
        }
        .initial()

        State(.loading) {
            for transition in Self.loadingTransitions() {
                transition
            }
        }

        State(.playing) {
            for transition in Self.playingTransitions() {
                transition
            }
        }

        State(.paused) {
            for transition in Self.pausedTransitions() {
                transition
            }
        }

        State(.failed) {
            for transition in Self.failedTransitions() {
                transition
            }
        }
    }

    private static func stoppedTransitions() -> [Transition] {
        var transitions = commonTransitions(stayingIn: .stopped)
        transitions.append(Transition(on: .launch, to: .loading)
            .when(canLaunchPlayback)
            .action { args, _ in applyLaunch(args.context, shouldPlay: true) })
        transitions.append(Transition(on: .launch, to: .failed)
            .when(launchNeedsMissingTracksFailure)
            .action { args, _ in applyFailure("No tracker modules were found in the app bundle.", to: args.context) })
        transitions.append(Transition(on: .launch, to: .stopped)
            .when { context, event in
                !canLaunchPlayback(context, event) && !launchNeedsMissingTracksFailure(context, event)
            }
            .action { args, _ in applyLaunch(args.context, shouldPlay: false) })
        transitions.append(Transition(on: .togglePause, to: .loading)
            .when(canStartFromStopped)
            .action { args, _ in queueTrackForCurrentPurpose(args.context, startImmediately: true) })
        transitions.append(Transition(on: .previousTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .nextTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .playTestCue, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .loading)
            .when(buildChangeNeedsTrack)
            .action { args, _ in applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .stopped)
            .when { context, event in !buildChangeNeedsTrack(context, event) }
            .action { args, _ in applyBuildContext(args.event, to: args.context) })
        transitions.append(Transition(on: .playbackStopped, to: .stopped)
            .action { args, _ in applyStopped(args.event, to: args.context) })
        transitions.append(Transition(on: .audioFailed, to: .failed)
            .action { args, _ in applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func loadingTransitions() -> [Transition] {
        var transitions = commonTransitions(stayingIn: .loading)
        transitions.append(Transition(on: .playbackPrepared, to: .playing)
            .when(preparedStartedCurrentGeneration)
            .action { args, _ in applyPlaybackPrepared(args.event, to: args.context) })
        transitions.append(Transition(on: .playbackPrepared, to: .paused)
            .when(preparedPausedCurrentGeneration)
            .action { args, _ in applyPlaybackPrepared(args.event, to: args.context) })
        transitions.append(Transition(on: .audioFailed, to: .failed)
            .action { args, _ in applyFailure(args.event, to: args.context) })
        transitions.append(Transition(on: .togglePause, to: .paused)
            .action { args, _ in applyPauseIntent(args.context) })
        transitions.append(Transition(on: .previousTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .nextTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .loading)
            .action { args, _ in applyBuildContext(args.event, to: args.context) })
        transitions.append(Transition(on: .playbackStopped, to: .stopped)
            .action { args, _ in applyStopped(args.event, to: args.context) })
        return transitions
    }

    private static func playingTransitions() -> [Transition] {
        var transitions = commonTransitions(stayingIn: .playing)
        transitions.append(Transition(on: .togglePause, to: .playing)
            .action { args, _ in queuePause(args.context) })
        transitions.append(Transition(on: .playbackPaused, to: .paused)
            .action { args, _ in applyPlaybackPaused(args.event, to: args.context) })
        transitions.append(Transition(on: .previousTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .nextTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .playTestCue, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .loading)
            .when(buildChangeNeedsTrack)
            .action { args, _ in applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .playing)
            .when { context, event in !buildChangeNeedsTrack(context, event) }
            .action { args, _ in applyBuildContext(args.event, to: args.context) })
        transitions.append(Transition(on: .trackFinished, to: .loading)
            .when(shouldAutoAdvanceFinishedTrack)
            .action { args, _ in applyTrackFinishedAndQueueNext(args.event, to: args.context) })
        transitions.append(Transition(on: .trackFinished, to: .stopped)
            .when { context, event in !shouldAutoAdvanceFinishedTrack(context, event) }
            .action { args, _ in applyTrackFinished(args.event, to: args.context) })
        transitions.append(Transition(on: .audioFailed, to: .failed)
            .action { args, _ in applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func pausedTransitions() -> [Transition] {
        var transitions = commonTransitions(stayingIn: .paused)
        transitions.append(Transition(on: .togglePause, to: .paused)
            .when(canResumeCurrentTrack)
            .action { args, _ in queueResume(args.context) })
        transitions.append(Transition(on: .togglePause, to: .loading)
            .when(canStartFromPaused)
            .action { args, _ in queueTrackForCurrentPurpose(args.context, startImmediately: true) })
        transitions.append(Transition(on: .previousTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(-1, context: args.context, startImmediately: false) })
        transitions.append(Transition(on: .nextTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(1, context: args.context, startImmediately: false) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .paused)
            .action { args, _ in applyBuildContext(args.event, to: args.context) })
        transitions.append(Transition(on: .playbackPaused, to: .paused)
            .action { args, _ in applyPlaybackPaused(args.event, to: args.context) })
        transitions.append(Transition(on: .playbackResumed, to: .playing)
            .action { args, _ in applyPlaybackResumed(args.event, to: args.context) })
        transitions.append(Transition(on: .audioFailed, to: .failed)
            .action { args, _ in applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func failedTransitions() -> [Transition] {
        var transitions = commonTransitions(stayingIn: .failed)
        transitions.append(Transition(on: .launch, to: .loading)
            .when(canLaunchPlayback)
            .action { args, _ in applyLaunch(args.context, shouldPlay: true) })
        transitions.append(Transition(on: .previousTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .nextTrack, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .playTestCue, to: .loading)
            .when(canSelectTrack)
            .action { args, _ in queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .loading)
            .when(buildChangeNeedsTrack)
            .action { args, _ in applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(Transition(on: .buildSnapshotChanged, to: .failed)
            .when { context, event in !buildChangeNeedsTrack(context, event) }
            .action { args, _ in applyBuildContext(args.event, to: args.context) })
        return transitions
    }

    private static func commonTransitions(
        stayingIn state: SoundtrackState
    ) -> [Transition] {
        [
            Transition(on: .setVolume, to: state)
                .action { args, _ in applyVolume(args.event, to: args.context) },
            Transition(on: .setInsertSlot, to: state)
                .action { args, _ in applyInsertSlot(args.event, to: args.context) },
            Transition(on: .toggleInsertBypass, to: state)
                .action { args, _ in applyInsertBypass(args.event, to: args.context) },
            Transition(on: .audioRequestHandled, to: state)
                .action { args, _ in clearHandledRequest(args.event, from: args.context) },
            Transition(on: .toggleMute, to: .stopped)
                .when { context, _ in !context.isMuted }
                .action { args, _ in applyMute(to: args.context) },
            Transition(on: .toggleMute, to: .loading)
                .when(unmuteCanStartPlayback)
                .action { args, _ in applyUnmute(args.context, shouldPlay: true) },
            Transition(on: .toggleMute, to: .stopped)
                .when { context, event in context.isMuted && !unmuteCanStartPlayback(context, event) }
                .action { args, _ in applyUnmute(args.context, shouldPlay: false) },
            Transition(on: .playbackStopped, to: .stopped)
                .action { args, _ in applyStopped(args.event, to: args.context) },
        ]
    }
}

private extension SoundtrackMachine {
    static func canLaunchPlayback(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .launch? = event else { return false }
        return !context.isMuted && !context.startupPlayed && !context.tracks.isEmpty
    }

    static func launchNeedsMissingTracksFailure(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .launch? = event else { return false }
        return !context.isMuted && !context.startupPlayed && context.tracks.isEmpty
    }

    static func canStartFromStopped(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .togglePause? = event else { return false }
        return !context.isMuted && !context.tracks.isEmpty
    }

    static func canStartFromPaused(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .togglePause? = event else { return false }
        return !context.isMuted && context.currentTrack == nil && !context.tracks.isEmpty
    }

    static func canResumeCurrentTrack(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .togglePause? = event else { return false }
        return !context.isMuted && context.currentTrack != nil
    }

    static func canSelectTrack(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        context.canSelectTrack
    }

    static func unmuteCanStartPlayback(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case .toggleMute? = event else { return false }
        return context.isMuted && !context.tracks.isEmpty
    }

    static func buildChangeNeedsTrack(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        buildPurpose(for: event, previous: context) != nil
    }

    static func preparedStartedCurrentGeneration(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case let .playbackPrepared(_, generation, started)? = event else { return false }
        return started && generation == context.generation
    }

    static func preparedPausedCurrentGeneration(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case let .playbackPrepared(_, generation, started)? = event else { return false }
        return !started && generation == context.generation
    }

    static func shouldAutoAdvanceFinishedTrack(_ context: SoundtrackContext, _ event: SoundtrackEvent?) -> Bool {
        guard case let .trackFinished(generation)? = event else { return false }
        return generation == context.generation && !context.isMuted && context.playbackPhase != .paused && !context.tracks.isEmpty
    }

}

private extension SoundtrackMachine {
    static func applyLaunch(_ context: SoundtrackContext, shouldPlay: Bool) -> SoundtrackContext {
        var ctx = context
        guard !ctx.startupPlayed else { return ctx }
        ctx.startupPlayed = true
        guard shouldPlay else { return ctx }
        return queueRandomTrack(for: .startup, context: ctx, startImmediately: true)
    }

    static func applyMute(to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.isMuted = true
        ctx.playbackPhase = .stopped
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        ctx.lastError = nil
        ctx.generation += 1
        ctx.enqueue(.stop(generation: ctx.generation))
        return ctx
    }

    static func applyUnmute(_ context: SoundtrackContext, shouldPlay: Bool) -> SoundtrackContext {
        var ctx = context
        ctx.isMuted = false
        ctx.lastError = nil
        guard shouldPlay else { return ctx }
        let purpose: SoundtrackPurpose = ctx.wasBuildRunning && ctx.currentStage.isActive
            ? .stage(ctx.currentStage)
            : .startup
        ctx.startupPlayed = true
        return queueRandomTrack(for: purpose, context: ctx, startImmediately: true)
    }

    static func applyVolume(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .setVolume(volume)? = event else { return ctx }
        let clamped = SoundtrackContext.clampedVolume(volume)
        ctx.volume = clamped
        ctx.enqueue(.setVolume(clamped))
        return ctx
    }

    static func applyInsertSlot(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .setInsertSlot(index, component)? = event,
              ctx.insertSlots.indices.contains(index) else { return ctx }
        ctx.insertSlots[index].component = component
        ctx.insertSlots[index].isBypassed = false
        ctx.enqueue(.setInsert(index: index, component: component))
        return ctx
    }

    static func applyInsertBypass(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .toggleInsertBypass(index)? = event,
              ctx.insertSlots.indices.contains(index) else { return ctx }
        ctx.insertSlots[index].isBypassed.toggle()
        ctx.enqueue(.setInsertBypass(index: index, bypassed: ctx.insertSlots[index].isBypassed))
        return ctx
    }

    static func clearHandledRequest(_ event: SoundtrackEvent?, from context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .audioRequestHandled(id)? = event,
              ctx.pendingAudioRequest?.id == id else { return ctx }
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyBuildContext(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .buildSnapshotChanged(buildSnapshot)? = event else { return ctx }
        if ctx.playbackPhase == .paused, buildSnapshot.stage != .off {
            ctx.activePurpose = .stage(buildSnapshot.stage)
        }
        ctx.wasBuildRunning = buildSnapshot.isRunning
        ctx.currentStage = buildSnapshot.stage
        return ctx
    }

    static func applyBuildContextAndQueueTrack(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        guard let purpose = buildPurpose(for: event, previous: context) else {
            return applyBuildContext(event, to: context)
        }
        let ctx = applyBuildContext(event, to: context)
        return queueRandomTrack(for: purpose, context: ctx, startImmediately: true)
    }

    static func applyPlaybackPrepared(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .playbackPrepared(moduleTitle, generation, started)? = event,
              generation == ctx.generation else { return ctx }
        ctx.moduleTitle = moduleTitle
        ctx.playbackPhase = started ? .playing : .paused
        ctx.lastError = nil
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyPlaybackPaused(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .playbackPaused(generation)? = event,
              generation == ctx.generation else { return ctx }
        ctx.playbackPhase = .paused
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyPlaybackResumed(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .playbackResumed(generation)? = event,
              generation == ctx.generation else { return ctx }
        ctx.playbackPhase = .playing
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyStopped(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        if case let .playbackStopped(generation)? = event, generation != ctx.generation {
            return ctx
        }
        ctx.playbackPhase = .stopped
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyTrackFinished(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        guard case let .trackFinished(generation)? = event,
              generation == ctx.generation else { return ctx }
        ctx.playbackPhase = .stopped
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyTrackFinishedAndQueueNext(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        let stopped = applyTrackFinished(event, to: context)
        guard stopped.canSelectTrack else { return stopped }
        return queueRandomTrack(for: context.activePurpose, context: stopped, startImmediately: true)
    }

    static func applyFailure(_ event: SoundtrackEvent?, to context: SoundtrackContext) -> SoundtrackContext {
        guard case let .audioFailed(message, generation)? = event else { return context }
        if let generation, generation != context.generation { return context }
        return applyFailure(message, to: context)
    }

    static func applyFailure(_ message: String, to context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.playbackPhase = .failed
        ctx.lastError = message
        ctx.currentTrack = nil
        ctx.moduleTitle = nil
        ctx.pendingAudioRequest = nil
        return ctx
    }

    static func applyPauseIntent(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.playbackPhase = .paused
        return ctx
    }

    static func queuePause(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.enqueue(.pause(generation: ctx.generation))
        return ctx
    }

    static func queueResume(_ context: SoundtrackContext) -> SoundtrackContext {
        var ctx = context
        ctx.enqueue(.resume(generation: ctx.generation))
        return ctx
    }

    static func queueTrackForCurrentPurpose(
        _ context: SoundtrackContext,
        startImmediately: Bool
    ) -> SoundtrackContext {
        queueRandomTrack(for: context.activePurpose, context: context, startImmediately: startImmediately)
    }

    static func queueRandomTrack(
        for purpose: SoundtrackPurpose,
        context: SoundtrackContext,
        startImmediately: Bool
    ) -> SoundtrackContext {
        let ctx = context
        guard let track = randomTrack(in: ctx) else {
            return applyFailure("No tracker modules were found in the app bundle.", to: ctx)
        }
        return queueTrack(track, purpose: purpose, context: ctx, startImmediately: startImmediately)
    }

    static func queueOffsetTrack(
        _ offset: Int,
        context: SoundtrackContext,
        startImmediately: Bool
    ) -> SoundtrackContext {
        let ctx = context
        guard let track = track(offsetBy: offset, in: ctx) else {
            return applyFailure("No tracker modules were found in the app bundle.", to: ctx)
        }
        return queueTrack(track, purpose: ctx.activePurpose, context: ctx, startImmediately: startImmediately)
    }

    static func queueTrack(
        _ track: TrackerModuleTrack,
        purpose: SoundtrackPurpose,
        context: SoundtrackContext,
        startImmediately: Bool
    ) -> SoundtrackContext {
        var ctx = context
        ctx.generation += 1
        ctx.playbackPhase = .loading
        ctx.currentTrack = track
        ctx.activePurpose = purpose
        ctx.moduleTitle = nil
        ctx.lastError = nil
        ctx.enqueue(.play(url: track.url, generation: ctx.generation, startImmediately: startImmediately))
        return ctx
    }
}

private extension SoundtrackMachine {
    static func buildPurpose(
        for event: SoundtrackEvent?,
        previous context: SoundtrackContext
    ) -> SoundtrackPurpose? {
        // DORMANT HOOK — build events never re-cue the soundtrack yet. For now the track changes
        // ONLY when the current one ends (natural auto-advance). All the wiring stays live
        // (`.buildSnapshotChanged` still updates the displayed stage via `applyBuildContext`);
        // this is just the one decision point, deliberately turned off.
        //
        // Intended future behavior: change the track to SIGNAL A MAJOR BUILD TRANSITION —
        // BUILDING → TESTING → MEASURING → DEPLOYING → ERROR/IDLE — plus distinct success/failure
        // cues. It can't simply key off `buildSnapshot.stage != currentStage`: `BuildStage.runningStage`
        // classifies from keywords in each progress line, so the raw stage flickers many times per
        // second during a compiler build, and re-cueing on that flood the audio engine with rapid
        // engine.play() calls. Enabling this needs COARSE, DEBOUNCED transition detection (only act
        // once a new stage has held steady). The shape it will take:
        //
        //   guard case let .buildSnapshotChanged(build)? = event,
        //         !context.isMuted, context.playbackPhase != .paused, !context.tracks.isEmpty
        //   else { return nil }
        //   if build.isRunning, !context.wasBuildRunning { return .stage(build.stage) }       // started
        //   if build.stage == .failed, context.currentStage != .failed { return .failure }    // failed
        //   if !build.isRunning, context.wasBuildRunning, build.succeeded { return .success }  // finished
        //   if <debounced stage change> { return .stage(build.stage) }                         // phase change
        return nil
    }

    static func randomTrack(in context: SoundtrackContext) -> TrackerModuleTrack? {
        guard !context.tracks.isEmpty else { return nil }
        let candidates = context.tracks.count > 1
            ? context.tracks.filter { $0 != context.currentTrack }
            : context.tracks
        return candidates.randomElement() ?? context.tracks.randomElement()
    }

    static func track(offsetBy offset: Int, in context: SoundtrackContext) -> TrackerModuleTrack? {
        guard !context.tracks.isEmpty else { return nil }
        guard let currentTrack = context.currentTrack,
              let currentIndex = context.tracks.firstIndex(of: currentTrack) else {
            return offset >= 0 ? context.tracks.first : context.tracks.last
        }
        let nextIndex = (currentIndex + offset + context.tracks.count) % context.tracks.count
        return context.tracks[nextIndex]
    }
}

// MARK: Inference Maps - Workaroud for compiler issue.

// See Swift Evolution pitch:
// https://forums.swift.org/t/pitch-implicit-member-expressions-for-function-typed-parameters/87892/6

// These MUST stay UNLABELED tuples. The multi-value events below are named by the variadic
// `XTransition.init(on: Map<(repeat each Payload), EventID>)` overload, and a parameter pack only ever
// expands to an *unlabeled* tuple. A labeled tuple (e.g. `(String, generation: Int?)`) won't match that
// overload — it falls through to the scalar `Payload: Blankable` one and fails to compile with
// "type '(String, generation: Int?)' cannot conform to 'Blankable'". Keep the labels on the *enum
// cases* (they document the payload); just not on these Map-input tuples.
typealias Insert = (Int, AudioComponentRef?)
typealias AudioFailure = (String, Int?)
typealias PlaybackInfo = (String?, Int, Bool)

extension Map where In == Double, Out == SoundtrackEvent {
    static var setVolume: Map<In, Out> { .init(transform: Out.setVolume) }
}

extension Map where In == Insert, Out == SoundtrackEvent {
    static var setInsertSlot: Self { .init(transform: Out.setInsertSlot) }
}

extension Map where In == SoundtrackBuildSnapshot, Out == SoundtrackEvent {
    static var buildSnapshotChanged: Map<In, Out> { .init(transform: Out.buildSnapshotChanged) }
}

extension Map where In == AudioFailure, Out == SoundtrackEvent {
    static var audioFailed: Self { .init(transform: Out.audioFailed) }
}

extension Map where In == Int, Out == SoundtrackEvent {
    static var playbackPaused: Map<In, Out> { .init(transform: Out.playbackPaused) }
    static var playbackResumed: Map<In, Out> { .init(transform: Out.playbackResumed) }
    static var playbackStopped: Map<In, Out> { .init(transform: Out.playbackStopped) }
    static var trackFinished: Map<In, Out> { .init(transform: Out.trackFinished) }
    static var audioRequestHandled: Map<In, Out> { .init(transform: Out.audioRequestHandled) }
    static var toggleInsertBypass: Map<In, Out> { .init(transform: Out.toggleInsertBypass) }
}

extension Map where In == PlaybackInfo, Out == SoundtrackEvent {
    static var playbackPrepared: Map<In, Out> { .init(transform: Out.playbackPrepared) }
}
