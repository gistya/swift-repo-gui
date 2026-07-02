import XCTest
@testable import Ox0badf00d

final class Ox0badf00dTests: XCTestCase {
    func testSyntheticModuleRendersNonSilentPCM() {
        let sample = TrackerSample(
            name: "Loop",
            pcm: [0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5],
            volume: 0.8,
            loopStart: 0,
            loopLength: 8,
            loopMode: .forward
        )
        let pattern = TrackerPattern(
            rowCount: 1,
            channelCount: 1,
            events: [
                TrackerEvent(pitch: .midi(60), instrument: 1),
            ]
        )
        let module = TrackerModule(
            format: .xm,
            title: "Synthetic",
            channelCount: 1,
            orders: [0],
            patterns: [pattern],
            samples: [sample]
        )

        let buffer = ModuleRenderer(module: module, sampleRate: 44_100).render(seconds: 0.15)
        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertEqual(buffer.frameCount, 6_615)
        XCTAssertTrue(buffer.interleavedSamples.contains { abs($0) > 0.0001 })
        XCTAssertTrue(buffer.interleavedSamples.allSatisfy { $0.isFinite })
    }

    func testVolumeSlideRunsOnTicksInsideARow() {
        let sample = TrackerSample(
            name: "Constant",
            pcm: Array(repeating: 1, count: 64),
            volume: 1,
            loopStart: 0,
            loopLength: 64,
            loopMode: .forward
        )
        let pattern = TrackerPattern(
            rowCount: 1,
            channelCount: 1,
            events: [
                TrackerEvent(
                    pitch: .midi(60),
                    instrument: 1,
                    command: .volumeSlide(up: 0, down: 8)
                ),
            ]
        )
        let module = TrackerModule(
            format: .xm,
            title: "Volume Slide",
            channelCount: 1,
            orders: [0],
            patterns: [pattern],
            samples: [sample],
            initialSpeed: 6,
            initialTempo: 125
        )

        let pcm = ModuleRenderer(module: module, sampleRate: 1_000).render(seconds: 0.11)
        let early = averageAbsoluteMonoEnergy(pcm, frameRange: 2..<12)
        let late = averageAbsoluteMonoEnergy(pcm, frameRange: 95..<105)
        XCTAssertGreaterThan(early, late * 1.5)
    }

    func testPsychoacoustic3DAddsDelayedFarEarEnergy() {
        let sample = TrackerSample(
            name: "Left",
            pcm: Array(repeating: 1, count: 256),
            volume: 0.7,
            panning: 0,
            loopStart: 0,
            loopLength: 256,
            loopMode: .forward
        )
        let pattern = TrackerPattern(
            rowCount: 1,
            channelCount: 1,
            events: [
                TrackerEvent(pitch: .midi(60), instrument: 1),
            ]
        )
        let module = TrackerModule(
            format: .xm,
            title: "Spatial",
            channelCount: 1,
            orders: [0],
            patterns: [pattern],
            samples: [sample]
        )

        let stereo = ModuleRenderer(module: module, sampleRate: 44_100).render(seconds: 0.04)
        let spatial = ModuleRenderer(
            module: module,
            sampleRate: 44_100,
            options: RenderOptions(spatialization: .psychoacoustic3D(.spacious))
        ).render(seconds: 0.04)

        XCTAssertLessThan(channelEnergy(stereo, channel: 1), 0.0001)
        XCTAssertGreaterThan(channelEnergy(spatial, channel: 1), 0.01)
        XCTAssertNotEqual(stereo.interleavedSamples, spatial.interleavedSamples)
    }

    func testInstrumentSampleMapSelectsSampleForNote() {
        let positive = TrackerSample(
            name: "Positive",
            pcm: Array(repeating: 1, count: 128),
            volume: 1,
            loopStart: 0,
            loopLength: 128,
            loopMode: .forward
        )
        let negative = TrackerSample(
            name: "Negative",
            pcm: Array(repeating: -1, count: 128),
            volume: 1,
            loopStart: 0,
            loopLength: 128,
            loopMode: .forward
        )
        var sampleMap = Array<Int?>(repeating: 0, count: 96)
        sampleMap[60] = 1
        let instrument = TrackerInstrument(name: "Split", sampleMap: sampleMap)
        let pattern = TrackerPattern(
            rowCount: 1,
            channelCount: 1,
            events: [
                TrackerEvent(pitch: .midi(72), instrument: 1),
            ]
        )
        let module = TrackerModule(
            format: .xm,
            title: "Sample Map",
            channelCount: 1,
            orders: [0],
            patterns: [pattern],
            samples: [positive, negative],
            instruments: [instrument]
        )

        let pcm = ModuleRenderer(module: module, sampleRate: 44_100).render(seconds: 0.02)
        XCTAssertLessThan(Double(pcm.interleavedSamples[0]), -0.1)
    }

    func testInstrumentVolumeEnvelopeShapesPlayback() {
        let sample = TrackerSample(
            name: "Constant",
            pcm: Array(repeating: 1, count: 128),
            volume: 1,
            loopStart: 0,
            loopLength: 128,
            loopMode: .forward
        )
        let envelope = TrackerEnvelope(points: [
            TrackerEnvelopePoint(tick: 0, value: 1),
            TrackerEnvelopePoint(tick: 2, value: 0),
        ])
        let instrument = TrackerInstrument(
            name: "Fade",
            sampleMap: Array(repeating: 0, count: 96),
            volumeEnvelope: envelope
        )
        let pattern = TrackerPattern(
            rowCount: 1,
            channelCount: 1,
            events: [
                TrackerEvent(pitch: .midi(60), instrument: 1),
            ]
        )
        let module = TrackerModule(
            format: .xm,
            title: "Envelope",
            channelCount: 1,
            orders: [0],
            patterns: [pattern],
            samples: [sample],
            instruments: [instrument],
            initialSpeed: 6,
            initialTempo: 125
        )

        let pcm = ModuleRenderer(module: module, sampleRate: 1_000).render(seconds: 0.08)
        let early = averageAbsoluteMonoEnergy(pcm, frameRange: 2..<12)
        let late = averageAbsoluteMonoEnergy(pcm, frameRange: 55..<70)
        XCTAssertGreaterThan(early, late * 5)
    }

    func testRejectsUnknownData() {
        XCTAssertThrowsError(try ModuleLoader.load(data: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? ModuleError, .unsupportedFormat)
        }
    }

    func testLoadsAndRendersRealRepoTrackerFilesWhenPresent() throws {
        let fixtures = [
            ("1kb.it", TrackerFormat.it),
            ("4_rndd!.xm", TrackerFormat.xm),
            ("drozerix_-_stardust_jam.mod", TrackerFormat.mod),
        ]

        let available = fixtures.compactMap { fixture -> (URL, TrackerFormat)? in
            let url = repoTrackerModuleDirectory().appendingPathComponent(fixture.0)
            return FileManager.default.fileExists(atPath: url.path) ? (url, fixture.1) : nil
        }

        guard !available.isEmpty else {
            throw XCTSkip("No repository tracker fixtures are present.")
        }

        for (url, expectedFormat) in available {
            let module = try ModuleLoader.load(url: url)
            XCTAssertEqual(module.format, expectedFormat, url.lastPathComponent)
            XCTAssertGreaterThan(module.channelCount, 0, url.lastPathComponent)
            XCTAssertFalse(module.patterns.isEmpty, url.lastPathComponent)

            let pcm = ModuleRenderer(module: module, sampleRate: 22_050).render(seconds: 0.05)
            XCTAssertEqual(pcm.frameCount, 1_103, url.lastPathComponent)
            XCTAssertTrue(pcm.interleavedSamples.allSatisfy { $0.isFinite }, url.lastPathComponent)
        }
    }

    private func repoTrackerModuleDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SwiftRepoGUI/Resources/TrackerModules", isDirectory: true)
    }

    private func averageAbsoluteMonoEnergy(_ buffer: PCMBuffer, frameRange: Range<Int>) -> Double {
        let upperBound = min(frameRange.upperBound, buffer.frameCount)
        guard frameRange.lowerBound < upperBound else { return 0 }
        let values = frameRange.lowerBound..<upperBound
        let total = values.reduce(0.0) { partial, frame in
            let left = Double(buffer.interleavedSamples[frame * 2])
            let right = Double(buffer.interleavedSamples[frame * 2 + 1])
            return partial + abs((left + right) * 0.5)
        }
        return total / Double(values.count)
    }

    private func channelEnergy(_ buffer: PCMBuffer, channel: Int) -> Double {
        guard channel < buffer.channelCount else { return 0 }
        var total = 0.0
        for frame in 0..<buffer.frameCount {
            total += abs(Double(buffer.interleavedSamples[frame * buffer.channelCount + channel]))
        }
        return total / Double(max(1, buffer.frameCount))
    }
}
