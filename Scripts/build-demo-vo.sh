#!/bin/zsh
# Build narrated demo: per-frame TTS + hold video to match audio.
# Prefers ElevenLabs when ELEVENLABS_API_KEY is set; else macOS `say`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="$ROOT/docs/demo/frames"
WORK="$ROOT/docs/demo/vo-work"
SCRIPT="$ROOT/docs/demo/vo-script.txt"
OUT="$ROOT/docs/demo/pcoptopus-demo-vo.mp4"
LOCAL_ENV="$ROOT/docs/demo/.elevenlabs.env"
SAY_VOICE="${PCOCTOPUS_DEMO_VOICE:-Samantha}"
SAY_RATE="${PCOCTOPUS_DEMO_RATE:-170}"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Load local secrets if present (never commit this file).
if [[ -f "$LOCAL_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_ENV"
  set +a
fi

ELEVEN_KEY="${ELEVENLABS_API_KEY:-}"
ELEVEN_VOICE="${ELEVENLABS_VOICE_ID:-JBFqnCBsd6RMkjVDRZzb}"
ELEVEN_MODEL="${ELEVENLABS_MODEL_ID:-eleven_multilingual_v2}"

if [[ -n "$ELEVEN_KEY" ]]; then
  echo "TTS backend: ElevenLabs (voice=${ELEVEN_VOICE:0:8}…)"
else
  echo "TTS backend: macOS say ($SAY_VOICE) — set ELEVENLABS_API_KEY for ElevenLabs"
fi

rm -rf "$WORK"
mkdir -p "$WORK"

list_file="$WORK/concat.txt"
: > "$list_file"

synth_audio() {
  local text="$1"
  local out_m4a="$2"
  local raw="$WORK/raw-$RANDOM"

  if [[ -n "$ELEVEN_KEY" ]]; then
    local mp3="${raw}.mp3"
    local payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1], "model_id": sys.argv[2]}))' "$text" "$ELEVEN_MODEL")"
    local http
    http="$(curl -sS -o "$mp3" -w '%{http_code}' \
      -X POST "https://api.elevenlabs.io/v1/text-to-speech/${ELEVEN_VOICE}?output_format=mp3_44100_128" \
      -H "xi-api-key: ${ELEVEN_KEY}" \
      -H "Content-Type: application/json" \
      -d "$payload")"
    if [[ "$http" != "200" ]]; then
      echo "ElevenLabs HTTP $http:" >&2
      head -c 400 "$mp3" >&2 || true
      echo >&2
      exit 1
    fi
    ffmpeg -y -hide_banner -loglevel error -i "$mp3" -c:a aac -b:a 192k "$out_m4a" </dev/null
    rm -f "$mp3"
  else
    local aiff="${raw}.aiff"
    say -v "$SAY_VOICE" -r "$SAY_RATE" -o "$aiff" "$text" </dev/null
    ffmpeg -y -hide_banner -loglevel error -i "$aiff" -c:a aac -b:a 192k "$out_m4a" </dev/null
    rm -f "$aiff"
  fi
}

# Use FD 3 so TTS/ffmpeg cannot steal script lines from stdin.
while IFS='|' read -r idx text <&3; do
  [[ "$idx" == \#* || -z "${idx// }" ]] && continue
  frame="$(find "$FRAMES" -maxdepth 1 -name "${idx}-*.png" | sort | head -1)"
  if [[ -z "$frame" || ! -f "$frame" ]]; then
    echo "Missing frame for $idx" >&2
    exit 1
  fi
  m4a="$WORK/$idx.m4a"
  seg="$WORK/$idx.mp4"

  synth_audio "$text" "$m4a"
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$m4a")"
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
cp "$OUT" "$ROOT/docs/demo/pcoptopus-demo.mp4"

ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
ls -lh "$OUT"
echo "DONE $OUT"
