import Ox0badf00d
import SwiftXState

struct SoundtrackMachine: StateMachine {
    typealias Context = SoundtrackContext
    typealias StateID = SoundtrackState
    typealias EventID = SoundtrackEvent

    let initialContext: SoundtrackContext

    init(context: SoundtrackContext = .initial(
        style: SwiftBuilderStyle.current.sound,
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
        XState(.stopped) {
            for transition in Self.stoppedTransitions() {
                transition
            }
        }
        .initial()

        XState(.loading) {
            for transition in Self.loadingTransitions() {
                transition
            }
        }

        XState(.playing) {
            for transition in Self.playingTransitions() {
                transition
            }
        }

        XState(.paused) {
            for transition in Self.pausedTransitions() {
                transition
            }
        }

        XState(.failed) {
            for transition in Self.failedTransitions() {
                transition
            }
        }
    }

    private static func stoppedTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        var transitions = commonTransitions(stayingIn: .stopped)
        transitions.append(XTransition(on: .launch, to: .loading)
            .when(Self.canLaunchPlayback)
            .action { args, _ in Self.applyLaunch(args.context, shouldPlay: true) })
        transitions.append(XTransition(on: .launch, to: .failed)
            .when(Self.launchNeedsMissingTracksFailure)
            .action { args, _ in Self.applyFailure("No tracker modules were found in the app bundle.", to: args.context) })
        transitions.append(XTransition(on: .launch, to: .stopped)
            .when { context, event in
                // Deterministic catch-all: only when neither guarded `.launch` transition applies.
                // Multiple transitions on one event must be mutually exclusive so selection never
                // depends on declaration/iteration order.
                !Self.canLaunchPlayback(context, event) && !Self.launchNeedsMissingTracksFailure(context, event)
            }
            .action { args, _ in Self.applyLaunch(args.context, shouldPlay: false) })
        transitions.append(XTransition(on: .togglePause, to: .loading)
            .when(Self.canStartFromStopped)
            .action { args, _ in Self.queueTrackForCurrentPurpose(args.context, startImmediately: true) })
        transitions.append(XTransition(on: .previousTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .nextTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .playTestCue, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .loading)
            .when(Self.buildChangeNeedsTrack)
            .action { args, _ in Self.applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .stopped)
            .when { context, event in !Self.buildChangeNeedsTrack(context, event) }
            .action { args, _ in Self.applyBuildContext(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackStopped, to: .stopped)
            .action { args, _ in Self.applyStopped(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.audioFailed, to: .failed)
            .action { args, _ in Self.applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func loadingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        var transitions = commonTransitions(stayingIn: .loading)
        transitions.append(XTransition(on: SoundtrackEvent.playbackPrepared, to: .playing)
            .when(Self.preparedStartedCurrentGeneration)
            .action { args, _ in Self.applyPlaybackPrepared(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackPrepared, to: .paused)
            .when(Self.preparedPausedCurrentGeneration)
            .action { args, _ in Self.applyPlaybackPrepared(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.audioFailed, to: .failed)
            .action { args, _ in Self.applyFailure(args.event, to: args.context) })
        transitions.append(XTransition(on: .togglePause, to: .paused)
            .action { args, _ in Self.applyPauseIntent(args.context) })
        transitions.append(XTransition(on: .previousTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .nextTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .loading)
            .action { args, _ in Self.applyBuildContext(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackStopped, to: .stopped)
            .action { args, _ in Self.applyStopped(args.event, to: args.context) })
        return transitions
    }

    private static func playingTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        var transitions = commonTransitions(stayingIn: .playing)
        transitions.append(XTransition(on: .togglePause, to: .playing)
            .action { args, _ in Self.queuePause(args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackPaused, to: .paused)
            .action { args, _ in Self.applyPlaybackPaused(args.event, to: args.context) })
        transitions.append(XTransition(on: .previousTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .nextTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .playTestCue, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .loading)
            .when(Self.buildChangeNeedsTrack)
            .action { args, _ in Self.applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .playing)
            .when { context, event in !Self.buildChangeNeedsTrack(context, event) }
            .action { args, _ in Self.applyBuildContext(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.trackFinished, to: .loading)
            .when(Self.shouldAutoAdvanceFinishedTrack)
            .action { args, _ in Self.applyTrackFinishedAndQueueNext(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.trackFinished, to: .stopped)
            .when { context, event in !Self.shouldAutoAdvanceFinishedTrack(context, event) }
            .action { args, _ in Self.applyTrackFinished(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.audioFailed, to: .failed)
            .action { args, _ in Self.applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func pausedTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        var transitions = commonTransitions(stayingIn: .paused)
        transitions.append(XTransition(on: .togglePause, to: .paused)
            .when(Self.canResumeCurrentTrack)
            .action { args, _ in Self.queueResume(args.context) })
        transitions.append(XTransition(on: .togglePause, to: .loading)
            .when(Self.canStartFromPaused)
            .action { args, _ in Self.queueTrackForCurrentPurpose(args.context, startImmediately: true) })
        transitions.append(XTransition(on: .previousTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(-1, context: args.context, startImmediately: false) })
        transitions.append(XTransition(on: .nextTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(1, context: args.context, startImmediately: false) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .paused)
            .action { args, _ in Self.applyBuildContext(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackPaused, to: .paused)
            .action { args, _ in Self.applyPlaybackPaused(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.playbackResumed, to: .playing)
            .action { args, _ in Self.applyPlaybackResumed(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.audioFailed, to: .failed)
            .action { args, _ in Self.applyFailure(args.event, to: args.context) })
        return transitions
    }

    private static func failedTransitions() -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        var transitions = commonTransitions(stayingIn: .failed)
        transitions.append(XTransition(on: .launch, to: .loading)
            .when(Self.canLaunchPlayback)
            .action { args, _ in Self.applyLaunch(args.context, shouldPlay: true) })
        transitions.append(XTransition(on: .previousTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(-1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .nextTrack, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueOffsetTrack(1, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: .playTestCue, to: .loading)
            .when(Self.canSelectTrack)
            .action { args, _ in Self.queueRandomTrack(for: .test, context: args.context, startImmediately: true) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .loading)
            .when(Self.buildChangeNeedsTrack)
            .action { args, _ in Self.applyBuildContextAndQueueTrack(args.event, to: args.context) })
        transitions.append(XTransition(on: SoundtrackEvent.buildSnapshotChanged, to: .failed)
            .when { context, event in !Self.buildChangeNeedsTrack(context, event) }
            .action { args, _ in Self.applyBuildContext(args.event, to: args.context) })
        return transitions
    }

    private static func commonTransitions(
        stayingIn state: SoundtrackState
    ) -> [XTransition<SoundtrackContext, SoundtrackEvent, SoundtrackState>] {
        [
            XTransition(on: SoundtrackEvent.setVolume, to: state)
                .action { args, _ in Self.applyVolume(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.setInsertSlot, to: state)
                .action { args, _ in Self.applyInsertSlot(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.toggleInsertBypass, to: state)
                .action { args, _ in Self.applyInsertBypass(args.event, to: args.context) },
            XTransition(on: SoundtrackEvent.audioRequestHandled, to: state)
                .action { args, _ in Self.clearHandledRequest(args.event, from: args.context) },
            XTransition(on: .toggleMute, to: .stopped)
                .when { context, _ in !context.isMuted }
                .action { args, _ in Self.applyMute(to: args.context) },
            XTransition(on: .toggleMute, to: .loading)
                .when(Self.unmuteCanStartPlayback)
                .action { args, _ in Self.applyUnmute(args.context, shouldPlay: true) },
            XTransition(on: .toggleMute, to: .stopped)
                .when { context, event in context.isMuted && !Self.unmuteCanStartPlayback(context, event) }
                .action { args, _ in Self.applyUnmute(args.context, shouldPlay: false) },
            XTransition(on: SoundtrackEvent.playbackStopped, to: .stopped)
                .action { args, _ in Self.applyStopped(args.event, to: args.context) },
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
        guard case let .buildSnapshotChanged(buildSnapshot)? = event,
              !context.isMuted,
              context.playbackPhase != .paused,
              !context.tracks.isEmpty else { return nil }

        if buildSnapshot.isRunning, !context.wasBuildRunning {
            return .stage(buildSnapshot.stage)
        }
        if buildSnapshot.stage == .failed, context.currentStage != .failed {
            return .failure
        }
        if !buildSnapshot.isRunning, context.wasBuildRunning, buildSnapshot.succeeded {
            return .success
        }
        if buildSnapshot.stage.isActive, buildSnapshot.stage != context.currentStage {
            return .stage(buildSnapshot.stage)
        }
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
