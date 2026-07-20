# FluidAudio streaming Sortformer timestamp drift repro

Minimal reproduction for [FluidInference/FluidAudio#807](https://github.com/FluidInference/FluidAudio/pull/807): the streaming Sortformer preprocessor emits more mel frames than the audio contains when fed in real-time-sized batches, so every frame-derived timestamp (speaker turns, segment boundaries) drifts progressively late.

## Run

```bash
swift run -c release repro
```

Models download from HuggingFace on first run. The included `audio/two-speakers.wav` is 72.6 s of two alternating macOS `say` voices (Samantha / Daniel) with known turn boundaries at **18.4 / 36.8 / 54.7 s**; regenerate it with `scripts/make-audio.sh`.

The program streams the same file into `SortformerDiarizer` twice, once as a single `addAudio` call and once in 100 ms batches (a typical mic callback size), and prints the finalized frame count and detected speaker turns for both.

## Output against FluidAudio `main`

```
FluidAudio Sortformer streaming repro: one-shot vs real-time feeding
audio: 72.56 s, two say voices alternating at 18.4 / 36.8 / 54.7 s

  whole file in one addAudio       100 ms batches
   907 frames =  72.56 s timeline   937 frames =  74.96 s timeline
    0.00 s  speaker 0                0.00 s  speaker 0
   18.48 s  speaker 1               19.12 s  speaker 1
   36.88 s  speaker 0               38.16 s  speaker 0
   54.72 s  speaker 1               56.72 s  speaker 1

FAIL: 100 ms feeding emitted +30 frames (+2.40 s of timeline) for identical audio;
      speaker turn timestamps drift later as the session runs
```

One-shot feeding matches the ground-truth boundaries within a frame. With 100 ms feeding the same model output is stamped 0.6 s late at the first turn, 1.3 s at the second, 2.0 s at the third: the drift grows without bound as the session runs (~3.3% of elapsed time).

## Why

Each streaming preprocess call center-pads the buffered audio (`nFFT/2` zeros on both sides) before computing mel frames, but the `samplesConsumed` inversion only accounts for one pad, so every call emits frames covering 272 samples (17 ms) more timeline than the audio it consumes. One call per 6-frame chunk adds up to the ~3.3% clock skew above. Feeding everything in one `addAudio` call pads once, which is why batch-fed tests never see it.

---

This repro was created with [Claude Code](https://claude.com/claude-code).
