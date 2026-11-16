#!/bin/zsh
# Manual round-trip helper for AC sleep undo testing.
# Does NOT change settings unless you pass --execute (requires admin for pmset -c).
set -euo pipefail
EXECUTE=0
if [[ "${1:-}" == "--execute" ]]; then EXECUTE=1; fi

CURRENT=$(pmset -g custom | awk '/AC Power/{p=1} p&&$1=="sleep"{print $2; exit}')
echo "Current AC sleep: $CURRENT minutes"
echo "Proposed scratch value: 2"
echo "Restore value: $CURRENT"

if [[ "$EXECUTE" -ne 1 ]]; then
  echo "Dry run only. Re-run with --execute to apply 2 then restore (will prompt for admin if needed)."
  exit 0
fi

echo "Setting AC sleep to 2…"
sudo pmset -c sleep 2
VERIFY=$(pmset -g custom | awk '/AC Power/{p=1} p&&$1=="sleep"{print $2; exit}')
echo "Verified: $VERIFY"
echo "Restoring AC sleep to $CURRENT…"
sudo pmset -c sleep "$CURRENT"
FINAL=$(pmset -g custom | awk '/AC Power/{p=1} p&&$1=="sleep"{print $2; exit}')
echo "Final: $FINAL"
[[ "$FINAL" == "$CURRENT" ]] && echo "OK round-trip" || echo "FAIL restore"
