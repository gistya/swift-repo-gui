import XCTest
@testable import Ox0badf00d

/// `TrackerModule.isRenderable` is the guard that keeps silent/undecodable modules out of a host's
/// playlist (a size-coded `1kb.it` with unsupported compressed samples decoded to empty PCM + empty
/// patterns, and would otherwise "play" as an inaudible track). It must be true only when the module
/// has both sample PCM and at least one note trigger.
final class RenderableModuleTests: XCTestCase {
    private func pattern(withNote: Bool) -> TrackerPattern {
        var events = Array(repeating: TrackerEvent.empty, count: 64)
        if withNote { events[0] = TrackerEvent(pitch: .midi(60), instrument: 1) }
        return TrackerPattern(rowCount: 64, channelCount: 1, events: events)
    }

    private func module(samples: [TrackerSample], hasNote: Bool) -> TrackerModule {
        TrackerModule(
            format: .it, title: "t", channelCount: 1, orders: [0],
            patterns: [pattern(withNote: hasNote)], samples: samples
        )
    }

    private var loudSample: TrackerSample { TrackerSample(name: "s", pcm: [0.5, -0.5, 0.5, -0.5]) }
    private var emptySample: TrackerSample { TrackerSample(name: "s", pcm: []) }

    func testRenderableWithSamplesAndNotes() {
        XCTAssertTrue(module(samples: [loudSample], hasNote: true).isRenderable)
    }

    func testNotRenderableWithoutSampleData() {
        // Notes but no decoded PCM (the 1kb.it failure mode — compressed samples came back empty).
        XCTAssertFalse(module(samples: [emptySample], hasNote: true).isRenderable)
        XCTAssertFalse(module(samples: [], hasNote: true).isRenderable)
    }

    func testNotRenderableWithoutNotes() {
        // Sample data but no note triggers anywhere in the patterns.
        XCTAssertFalse(module(samples: [loudSample], hasNote: false).isRenderable)
    }
}
