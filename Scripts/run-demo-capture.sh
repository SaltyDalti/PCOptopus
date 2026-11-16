#!/bin/zsh
# Automated portfolio demo: drive PCOptopus via Accessibility, capture only its window.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="$ROOT/docs/demo/frames"
OUT="$ROOT/docs/demo/pcoptopus-demo.mp4"
mkdir -p "$FRAMES"
find "$FRAMES" -name '*.png' -delete 2>/dev/null || true

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

win_id() {
  swift -e '
import Cocoa
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  if owner == "PCOptopus" {
    if let id = w[kCGWindowNumber as String] as? Int {
      print(id); exit(0)
    }
  }
}
exit(2)
'
}

capture() {
  local name="$1"
  local id
  id="$(win_id)"
  /usr/sbin/screencapture -l "$id" -x -t png "$FRAMES/$name.png"
  echo "captured $name (window $id)"
}

click_button() {
  local title="$1"
  osascript <<EOF
tell application "PCOptopus" to activate
delay 0.35
tell application "System Events"
  tell process "PCOptopus"
    set frontmost to true
    set target to missing value
    set elems to entire contents of window 1
    repeat with e in elems
      try
        if (name of e is "$title") then
          set target to e
          exit repeat
        end if
      end try
    end repeat
    if target is missing value then error "No UI element named $title"
    click target
  end tell
end tell
EOF
}

echo "== Demo capture starting =="
osascript -e 'tell application "PCOptopus" to activate'
sleep 1
capture "01-today"

echo "Fight for 100…"
click_button "Fight for 100"
sleep 4
capture "02-fighting"
sleep 6
capture "03-after-fight"

echo "Journal…"
click_button "Journal"
sleep 1.2
capture "04-journal"

echo "Contract…"
click_button "Contract"
sleep 1.2
capture "05-contract"

echo "Machine…"
click_button "Machine"
sleep 1.2
capture "06-machine"

echo "Settings…"
click_button "Settings"
sleep 1.2
capture "07-settings"

echo "Back to Today + cleanup demo seed only…"
click_button "Today"
sleep 0.8
# Delete ONLY our fake reclaimables (never Discord/Code/Adobe/etc.)
rm -rf "${HOME}/Library/Caches/PCOptopusDemo"
# Keep demo.flag so host name stays sanitized for remaining frames
mkdir -p "${HOME}/Library/Application Support/PCOptopus"
# Re-fight / re-scan so UI shows demo leftovers gone
click_button "Fight for 100"
sleep 8
capture "08-today-after-cleanup"

echo "Assembling video…"
# Hold each frame ~2.2s; privacy-safe (app window only)
# ~3s per frame for a readable silent walkthrough
ffmpeg -y -hide_banner -loglevel error \
  -framerate 1/3 \
  -pattern_type glob -i "$FRAMES/*.png" \
  -c:v libx264 -pix_fmt yuv420p -r 30 \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,fade=t=in:st=0:d=0.35" \
  "$OUT"

ls -lh "$OUT" "$FRAMES"
echo "DONE $OUT"
