#!/bin/zsh
# Removes demo reclaimables and the demo flag.
set -euo pipefail
DEMO_DIR="${HOME}/Library/Caches/PCOptopusDemo"
FLAG="${HOME}/Library/Application Support/PCOptopus/demo.flag"
rm -rf "$DEMO_DIR"
rm -f "$FLAG"
echo "Removed demo storage seed and demo.flag"
