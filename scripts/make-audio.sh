#!/bin/bash
# Regenerates audio/two-speakers.wav: four alternating speaker turns
# synthesized with the macOS `say` command (Samantha / Daniel), 16 kHz mono.
# The committed wav was produced by this script; rerunning may shift turn
# boundaries slightly because say's pacing varies between macOS versions.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p audio
tmp="$(mktemp -d)"

texts=(
    "Normally I would not make a video about a film scanner. In fact normally I would not even think about one. But lately I have been thinking a lot about the impermanence of the media we create, and how old storage methods can lead to almost anything being lost forever, from one photo of a beloved relative to an entire television series."
    "That is exactly why I brought six rolls of film with me today. I also brought a different way that we can scan the photos, so we can compare them side by side. Developing film is cheap enough, but getting high quality scans for archival purposes adds up much faster than most people expect it to."
    "So with film cameras getting trendier every year, I figured why not be proactive and take a look at this little touchscreen film and slide scanner. It claims to handle film, negatives, and even mounted slides at a somewhat reasonable price, and it takes only about twenty rolls of film for the device to pay for itself."
    "Or we can use a mirrorless camera with a macro lens, or a flatbed scanner, and you can get those used pretty cheap. All of these methods have their own trade offs in terms of quality, convenience, and price, so today we will run the same roll of film through every single one of them and look at the results together."
)
voices=(Samantha Daniel Samantha Daniel)

for i in 0 1 2 3; do
    say -v "${voices[$i]}" --data-format=LEI16@16000 -o "$tmp/seg$i.wav" "${texts[$i]}"
done

python3 - "$tmp" <<'EOF'
import sys, wave, os
tmp = sys.argv[1]
out = wave.open("audio/two-speakers.wav", "wb")
pos = 0.0
for i in range(4):
    seg = wave.open(os.path.join(tmp, f"seg{i}.wav"), "rb")
    if i == 0:
        out.setparams(seg.getparams())
    frames = seg.readframes(seg.getnframes())
    duration = seg.getnframes() / seg.getframerate()
    speaker = "Samantha" if i % 2 == 0 else "Daniel"
    print(f"turn {i}: {speaker:9s} {pos:6.2f} s -> {pos + duration:6.2f} s")
    pos += duration
    out.writeframes(frames)
    seg.close()
out.close()
print(f"total: {pos:.2f} s -> audio/two-speakers.wav")
EOF

rm -rf "$tmp"
