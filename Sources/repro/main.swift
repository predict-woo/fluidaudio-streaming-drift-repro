import AVFoundation
import FluidAudio
import Foundation

// Streams audio/two-speakers.wav into SortformerDiarizer twice: once as a
// single addAudio call, once in 100 ms batches (a typical real-time mic
// callback). The audio and the code are identical; only the feeding
// granularity differs. Every 80 ms output frame accounts for 1280 samples of
// timeline, so both runs must emit the same frames at the same positions.

let audioURL = URL(fileURLWithPath: "audio/two-speakers.wav")
guard FileManager.default.fileExists(atPath: audioURL.path) else {
    fatalError("run from the repo root: swift run -c release repro")
}

let file = try AVAudioFile(forReading: audioURL)
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buffer)
let audio = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
let audioSeconds = Double(audio.count) / 16000

// Dominant speaker per finalized frame: argmax over slots with p >= 0.5.
func dominantSlot(_ probs: ArraySlice<Float>) -> Int? {
    var best: (slot: Int, p: Float)?
    for (i, p) in probs.enumerated() where p >= 0.5 && p > (best?.p ?? -1) {
        best = (i, p)
    }
    return best?.slot
}

struct Run {
    let start: Double
    let slot: Int?
}

// Feeds the audio in `batchSize`-sample calls and returns the finalized
// frame count plus the start time of every speaker run lasting >= 2 s.
func run(batchSize: Int, models: SortformerModels) throws -> (frames: Int, turns: [Run]) {
    let diarizer = SortformerDiarizer(config: .fastV2_1)
    diarizer.initialize(models: models)
    diarizer.reset()

    var predictions: [Float] = []
    var fed = 0
    while fed < audio.count {
        let end = min(fed + batchSize, audio.count)
        diarizer.addAudio(Array(audio[fed..<end]))
        while let update = try diarizer.process() {
            predictions.append(contentsOf: update.chunkResult.finalizedPredictions)
        }
        fed = end
    }
    if let update = try diarizer.finalizeSession() {
        predictions.append(contentsOf: update.chunkResult.finalizedPredictions)
    }

    let frames = predictions.count / 4
    var turns: [Run] = []
    var runStart = 0
    var runSlot: Int?? = nil
    for f in 0...frames {
        let slot = f < frames ? dominantSlot(predictions[(f * 4)..<(f * 4 + 4)]) : nil
        if runSlot == nil || slot != runSlot! {
            if let previous = runSlot, f - runStart >= 25 {
                turns.append(Run(start: Double(runStart) * 0.08, slot: previous))
            }
            runStart = f
            runSlot = slot
        }
    }
    return (frames, turns)
}

print("FluidAudio Sortformer streaming repro: one-shot vs real-time feeding")
print(String(format: "audio: %.2f s, two say voices alternating at 18.4 / 36.8 / 54.7 s", audioSeconds))
print("")
FileHandle.standardError.write("loading models (first run downloads them)...\n".data(using: .utf8)!)
let models = try await SortformerModels.loadFromHuggingFace(config: .fastV2_1)

let oneShot = try run(batchSize: audio.count, models: models)
let streamed = try run(batchSize: 1600, models: models)

func describe(_ result: (frames: Int, turns: [Run])) -> [String] {
    var lines = [String(format: "%4d frames = %6.2f s timeline", result.frames, Double(result.frames) * 0.08)]
    lines += result.turns.map { turn in
        String(format: "%6.2f s  %@", turn.start, turn.slot.map { "speaker \($0)" } ?? "silence")
    }
    return lines
}

let left = describe(oneShot)
let right = describe(streamed)
print("  whole file in one addAudio       100 ms batches")
for i in 0..<max(left.count, right.count) {
    let l = i < left.count ? left[i] : ""
    let r = i < right.count ? right[i] : ""
    print("  \(l.padding(toLength: 33, withPad: " ", startingAt: 0))\(r)")
}

print("")
if oneShot.frames == streamed.frames {
    print("PASS: frame count and timeline are independent of feeding granularity")
} else {
    let extra = streamed.frames - oneShot.frames
    print(String(format: "FAIL: 100 ms feeding emitted %+d frames (%+.2f s of timeline) for identical audio;", extra, Double(extra) * 0.08))
    print("      speaker turn timestamps drift later as the session runs")
}
