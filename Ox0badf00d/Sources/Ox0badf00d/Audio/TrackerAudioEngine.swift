import AVFoundation
import CoreAudioKit
import Foundation
import Ox0badf00dObjC
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public enum TrackerAudioError: Error, Sendable {
    case invalidSlot
    case instantiationFailed
    case incompatibleInsert
}

/// Owns and conceals the entire AVFoundation playback graph for tracker modules.
///
/// Everything AVAudio lives behind this actor: the engine, the player, the user insert slots, the
/// master limiter, and the module renderer. Rendering runs **on the actor** (off the main thread),
/// paced by `AVAudioPlayerNode.scheduleBuffer` completion callbacks delivered through a per-track
/// `AsyncStream` — there is no background `Thread`, no `NSCondition`, and no polling loop. Callers
/// issue imperative commands (`play`/`pause`/…/`setInsert`) and observe outcomes on ``events``.
///
/// The engine has **no dependency on SwiftXState**; it vends plain ``TrackerPlaybackState`` /
/// ``TrackerAudioEvent`` values a host can bridge to its own state model.
public actor TrackerAudioEngine {
    public nonisolated let events: AsyncStream<TrackerAudioEvent>
    private let eventContinuation: AsyncStream<TrackerAudioEvent>.Continuation

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let master: AVAudioUnitEffect?
    private var insertUnits: [AVAudioUnit?]

    private var config: AudioSessionConfig
    private var renderFormat: AVAudioFormat

    private var renderer: ModuleRenderer?
    private var moduleTitle: String?
    private var playGeneration = 0
    private var renderedFrames = 0
    private var inFlightBuffers = 0
    private var didRenderFinalChunk = false
    private var lastEngineError: String?

    private var pumpTask: Task<Void, Never>?
    private var ticksContinuation: AsyncStream<Void>.Continuation?

    public init(config: AudioSessionConfig = AudioSessionConfig()) {
        self.config = config
        self.renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRate,
            channels: config.channelCount
        )!
        self.insertUnits = Array(repeating: nil, count: config.insertSlotCount)

        if config.enableMasterLimiter {
            let description = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            self.master = AVAudioUnitEffect(audioComponentDescription: description)
        } else {
            self.master = nil
        }

        let stream = AsyncStream<TrackerAudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.events = stream.stream
        self.eventContinuation = stream.continuation

        // Engine wiring uses only stored properties, so it is legal directly in the actor initializer.
        engine.attach(player)
        if let master { engine.attach(master) }
        // The macOS analog of an IO buffer size: bound the output render quantum before starting.
        engine.outputNode.auAudioUnit.maximumFramesToRender = config.maximumFramesToRender
        var previous: AVAudioNode = player
        if let master {
            engine.connect(player, to: master, format: renderFormat)
            previous = master
        }
        engine.connect(previous, to: engine.mainMixerNode, format: renderFormat)
        engine.prepare()
    }

    // MARK: - Session

    public func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Float(min(1, max(0, volume)))
    }

    // MARK: - Transport

    public func play(moduleURL: URL, generation: Int, startImmediately: Bool) {
        teardownPlayback()
        playGeneration = generation
        renderedFrames = 0
        inFlightBuffers = 0
        didRenderFinalChunk = false

        do {
            let module = try ModuleLoader.load(url: moduleURL)
            moduleTitle = module.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let renderer = ModuleRenderer(
                module: module,
                sampleRate: Int(config.sampleRate.rounded()),
                options: RenderOptions(spatialization: config.spatialization, gain: config.gain)
            )
            renderer.prepareSongRendering(tailSeconds: config.tailDuration)
            self.renderer = renderer
        } catch {
            emit(.failed(message: Self.message(for: error), generation: generation))
            return
        }

        guard startEngineIfNeeded() else {
            emit(.failed(message: lastEngineError ?? "Audio engine unavailable.", generation: generation))
            return
        }

        // A fresh tick stream per track: completion callbacks from a superseded track yield into a
        // finished stream and are ignored, so tracks never cross-contaminate the refill counter.
        let ticks = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(8))
        ticksContinuation = ticks.continuation

        for _ in 0..<config.scheduleAheadBuffers {
            if didRenderFinalChunk { break }
            scheduleNextChunk(generation: generation)
        }
        if startImmediately { player.play() }
        emit(.prepared(moduleTitle: moduleTitle, generation: generation, started: startImmediately))

        pumpTask = Task { [weak self] in
            await self?.runPump(stream: ticks.stream, generation: generation)
        }
    }

    public func pause(generation: Int) {
        player.pause()
        if engine.isRunning { engine.pause() }
        emit(.paused(generation: generation))
    }

    public func resume(generation: Int) {
        guard renderer != nil else {
            emit(.failed(message: "No tracker stream is ready to resume.", generation: generation))
            return
        }
        guard startEngineIfNeeded() else {
            emit(.failed(message: lastEngineError ?? "Audio engine unavailable.", generation: generation))
            return
        }
        player.play()
        emit(.resumed(generation: generation))
    }

    public func stop(generation: Int) {
        teardownPlayback()
        if engine.isRunning { engine.pause() }
        emit(.stopped(generation: generation))
    }

    private func runPump(stream: AsyncStream<Void>, generation: Int) async {
        for await _ in stream {
            guard generation == playGeneration, !Task.isCancelled else { return }
            inFlightBuffers -= 1
            if !didRenderFinalChunk {
                scheduleNextChunk(generation: generation)
            }
            if didRenderFinalChunk, inFlightBuffers <= 0 {
                teardownPlayback()
                emit(.finished(generation: generation))
                return
            }
        }
    }

    private func scheduleNextChunk(generation: Int) {
        guard generation == playGeneration, let renderer, !didRenderFinalChunk else { return }
        let maxFrames = Int((config.maxTrackDuration * config.sampleRate).rounded())
        let remaining = maxFrames - renderedFrames
        guard remaining > 0 else {
            didRenderFinalChunk = true
            return
        }
        let requested = min(config.renderChunkFrames, remaining)
        let chunk = renderer.renderSongFrames(frameCount: requested)
        renderedFrames += chunk.buffer.frameCount
        guard chunk.buffer.frameCount > 0, let buffer = makeBuffer(from: chunk.buffer) else {
            didRenderFinalChunk = true
            return
        }
        inFlightBuffers += 1
        let ticks = ticksContinuation
        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { _ in
            ticks?.yield(())
        }
        if chunk.isFinished || renderedFrames >= maxFrames {
            didRenderFinalChunk = true
        }
    }

    private func makeBuffer(from pcm: PCMBuffer) -> AVAudioPCMBuffer? {
        let frameCount = pcm.frameCount
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let sourceChannels = pcm.channelCount
        let left = channels[0]
        let right = Int(renderFormat.channelCount) > 1 ? channels[1] : channels[0]
        pcm.interleavedSamples.withUnsafeBufferPointer { source in
            for frame in 0..<frameCount {
                let base = frame * sourceChannels
                left[frame] = source[base]
                right[frame] = source[base + min(1, sourceChannels - 1)]
            }
        }
        return buffer
    }

    private func teardownPlayback() {
        ticksContinuation?.finish()
        ticksContinuation = nil
        pumpTask?.cancel()
        pumpTask = nil
        player.stop()
        renderer = nil
        inFlightBuffers = 0
        didRenderFinalChunk = false
        renderedFrames = 0
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            lastEngineError = nil
            return true
        } catch {
            // Do NOT latch a permanent failure: a transient device error may recover on the next play.
            lastEngineError = Self.message(for: error)
            return false
        }
    }

    // MARK: - Insert slots

    public func setInsert(slot: Int, component: AudioComponentRef?, fullStateData: Data? = nil) async throws {
        guard slot >= 0, slot < insertUnits.count else { throw TrackerAudioError.invalidSlot }

        if let existing = insertUnits[slot] {
            engine.disconnectNodeOutput(existing)
            engine.detach(existing)
            insertUnits[slot] = nil
        }

        guard let component else {
            try rebuildInsertChain()
            return
        }

        let unit = try await instantiate(component)
        if let fullStateData,
           let plist = (try? PropertyListSerialization.propertyList(from: fullStateData, options: [], format: nil)) as? [String: Any] {
            unit.auAudioUnit.fullState = plist
        }
        engine.attach(unit)
        insertUnits[slot] = unit

        do {
            try rebuildInsertChain()
        } catch {
            // The AU rejected the graph format (e.g. a mono-only channel strip fed a stereo bus).
            // Back it out and restore a valid chain instead of crashing or leaving a broken graph.
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
            insertUnits[slot] = nil
            try? rebuildInsertChain()
            throw TrackerAudioError.incompatibleInsert
        }
    }

    public func setInsertBypass(slot: Int, bypassed: Bool) {
        guard slot >= 0, slot < insertUnits.count, let unit = insertUnits[slot] else { return }
        unit.auAudioUnit.shouldBypassEffect = bypassed
    }

    public func insertFullStateData(slot: Int) -> Data? {
        guard slot >= 0, slot < insertUnits.count,
              let unit = insertUnits[slot],
              let state = unit.auAudioUnit.fullState else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }

    public func parameters(slot: Int) -> [TrackerAUParameter] {
        guard slot >= 0, slot < insertUnits.count,
              let unit = insertUnits[slot],
              let tree = unit.auAudioUnit.parameterTree else { return [] }
        return tree.allParameters.map { parameter in
            TrackerAUParameter(
                address: parameter.address,
                identifier: parameter.identifier,
                displayName: parameter.displayName,
                minValue: parameter.minValue,
                maxValue: parameter.maxValue,
                value: parameter.value,
                unitName: parameter.unitName
            )
        }
    }

    public func setParameter(address: AUParameterAddress, value: Float, slot: Int) {
        guard slot >= 0, slot < insertUnits.count,
              let unit = insertUnits[slot],
              let parameter = unit.auAudioUnit.parameterTree?.parameter(withAddress: address) else { return }
        parameter.value = value
    }

    /// Sends a raw 3-byte MIDI message to the AU in `slot` (e.g. to drive a music-effect from a
    /// linked channel). A minimal hook the host can build channel-mapping UI on top of.
    public func sendMIDI(_ bytes: [UInt8], toSlot slot: Int) {
        guard slot >= 0, slot < insertUnits.count, bytes.count == 3,
              let unit = insertUnits[slot],
              let block = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        bytes.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            block(AUEventSampleTimeImmediate, 0, bytes.count, base)
        }
    }

    #if os(macOS)
    /// Requests the AU's own editor view controller. `sending` lets the freshly-created, non-Sendable
    /// controller cross back to the (main-actor) caller — the engine never retains it.
    public func makeInsertViewController(slot: Int) async -> sending NSViewController? {
        guard slot >= 0, slot < insertUnits.count, let unit = insertUnits[slot] else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSViewController?, Never>) in
            unit.auAudioUnit.requestViewController { controller in
                continuation.resume(returning: controller)
            }
        }
    }
    #elseif os(iOS)
    public func makeInsertViewController(slot: Int) async -> sending UIViewController? {
        guard slot >= 0, slot < insertUnits.count, let unit = insertUnits[slot] else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIViewController?, Never>) in
            unit.auAudioUnit.requestViewController { controller in
                continuation.resume(returning: controller)
            }
        }
    }
    #endif

    private func rebuildInsertChain() throws {
        // AVAudioEngine.connect raises NSExceptions (not Swift errors) for bad formats; contain them.
        try OxAudioExceptionCatcher.perform {
            self.connectInsertChain()
        }
    }

    private func connectInsertChain() {
        engine.disconnectNodeOutput(player)
        for unit in insertUnits.compactMap({ $0 }) { engine.disconnectNodeOutput(unit) }
        if let master { engine.disconnectNodeOutput(master) }

        var previous: AVAudioNode = player
        for unit in insertUnits.compactMap({ $0 }) {
            engine.connect(previous, to: unit, format: renderFormat)
            previous = unit
        }
        if let master {
            engine.connect(previous, to: master, format: renderFormat)
            previous = master
        }
        engine.connect(previous, to: engine.mainMixerNode, format: renderFormat)
    }

    private func instantiate(_ ref: AudioComponentRef) async throws -> AVAudioUnit {
        // Load user plugins OUT OF PROCESS: an arbitrary third-party AU (including copy-protected
        // ones whose PACE/iLok initializers can crash on load) then runs in a separate extension
        // process, so a failure surfaces as a thrown error instead of taking down the host app.
        try await AVAudioUnit.instantiate(with: ref.audioComponentDescription, options: .loadOutOfProcess)
    }

    // MARK: - Helpers

    private func emit(_ event: TrackerAudioEvent) {
        eventContinuation.yield(event)
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
