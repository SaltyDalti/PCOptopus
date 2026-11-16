#!/bin/zsh
set -euo pipefail
# Prove empty contract does not mutate pmset; run package verification suite.
BEFORE=$(pmset -g custom | awk '/AC Power/{p=1} p&&$1=="sleep"{print $2; exit}')
echo "AC sleep before: $BEFORE"
cd "$(dirname "$0")/.."
swift run PCOptopusVerification
AFTER=$(pmset -g custom | awk '/AC Power/{p=1} p&&$1=="sleep"{print $2; exit}')
echo "AC sleep after: $AFTER"
if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "FAIL: pmset changed without a grant"
  exit 1
fi
echo "OK: zero writes with empty contract"
