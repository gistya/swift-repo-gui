# Ox0badf00d

Ox0badf00d is a native Swift tracker module package for loading and rendering classic module music.

The initial engine supports:

- ProTracker-style `MOD` files with 4/6/8+ channel signatures.
- FastTracker II `XM` files with packed pattern data, note-to-sample instrument maps, volume/panning envelopes, and delta-decoded 8/16-bit samples.
- Impulse Tracker `IT` files with packed pattern data and uncompressed PCM samples.
- Tick-based playback for core tracker effects: arpeggio, portamento, tone portamento, vibrato, tremolo, volume slides, panning, sample offsets, retrigger, note cut/delay, pattern break/jump, pattern delay, tempo/speed, and global volume changes.
- Streaming-style stereo `Float` PCM rendering with no libopenmpt, no ffmpeg, and no external decoder.
- Optional psychoacoustic 3D spatialization using interaural time differences, level differences, head-shadow filtering, crossfeed, and early reflection cues.

This is intentionally a Swift package rather than app-only code so SwiftBuilder can use it as the real playback core later.

```swift
import Foundation
import Ox0badf00d

let data = try Data(contentsOf: moduleURL)
let module = try ModuleLoader.load(data: data)
let renderer = ModuleRenderer(module: module, sampleRate: 44_100)
let pcm = renderer.render(seconds: 8)
```

`PCMBuffer.interleavedSamples` contains stereo samples in left/right order.

For spatial playback:

```swift
let renderer = ModuleRenderer(
    module: module,
    sampleRate: 44_100,
    options: RenderOptions(spatialization: .psychoacoustic3D(.spacious))
)
```

## Current Scope

This is a real parser, tick scheduler, effect engine, and PCM renderer. The goal is capability parity with mature tracker players, then to go beyond them with modern spatial rendering.

Still to do for that bar:

- IT instrument envelope playback and New Note Actions.
- More exact XM envelope edge cases and fadeout behavior.
- More exact per-format effect memory and edge-case compatibility.
- IT compressed sample decoding.
- Filter/resonance commands where formats provide them.
- Golden-file render tests against known-good tracker engines.
