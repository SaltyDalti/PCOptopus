#!/bin/zsh
# Build narrated demo: per-frame macOS TTS + hold video to match audio.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="$ROOT/docs/demo/frames"
WORK="$ROOT/docs/demo/vo-work"
SCRIPT="$ROOT/docs/demo/vo-script.txt"
OUT="$ROOT/docs/demo/pcoptopus-demo-vo.mp4"
VOICE="${PCOCTOPUS_DEMO_VOICE:-Samantha}"
RATE="${PCOCTOPUS_DEMO_RATE:-170}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
rm -rf "$WORK"
mkdir -p "$WORK"

list_file="$WORK/concat.txt"
: > "$list_file"

# Use FD 3 so say/ffmpeg cannot steal script lines from stdin.
while IFS='|' read -r idx text <&3; do
  [[ "$idx" == \#* || -z "${idx// }" ]] && continue
  frame="$(find "$FRAMES" -maxdepth 1 -name "${idx}-*.png" | sort | head -1)"
  if [[ -z "$frame" || ! -f "$frame" ]]; then
    echo "Missing frame for $idx" >&2
    exit 1
  fi
  aiff="$WORK/$idx.aiff"
  m4a="$WORK/$idx.m4a"
  seg="$WORK/$idx.mp4"

  say -v "$VOICE" -r "$RATE" -o "$aiff" "$text" </dev/null
  ffmpeg -y -hide_banner -loglevel error -i "$aiff" -c:a aac -b:a 192k "$m4a" </dev/null
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$m4a")"
  # Pad a little so the frame is readable after speech ends
  hold="$(python3 -c "print(max(2.4, float('$dur') + 0.55))")"
  fade_at="$(python3 -c "print(max(0.1, float('$hold')-0.35))")"

  ffmpeg -y -hide_banner -loglevel error \
    -loop 1 -i "$frame" -i "$m4a" \
    -c:v libx264 -tune stillimage -pix_fmt yuv420p -r 30 \
    -c:a aac -b:a 192k -shortest \
    -t "$hold" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,fade=t=in:st=0:d=0.25,fade=t=out:st=${fade_at}:d=0.3" \
    "$seg" </dev/null

  echo "file '$seg'" >> "$list_file"
  echo "segment $idx  hold=${hold}s  voice=${dur}s"
done 3< "$SCRIPT"

ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$list_file" -c copy "$OUT" </dev/null
# Also refresh the silent/named canonical demo pointer used in docs
cp "$OUT" "$ROOT/docs/demo/pcoptopus-demo.mp4"

ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
ls -lh "$OUT"
echo "DONE $OUT"
