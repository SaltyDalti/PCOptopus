#!/bin/zsh
# Creates regenerable fake reclaimables under Library/Caches/PCOptopusDemo.
# Safe to delete. Used for portfolio Show me / Fight for 100 demos.
set -euo pipefail

DEMO_DIR="${HOME}/Library/Caches/PCOptopusDemo"
SUPPORT="${HOME}/Library/Application Support/PCOptopus"
FLAG="${SUPPORT}/demo.flag"

mkdir -p "$DEMO_DIR/OldInstallerLeftovers" "$DEMO_DIR/StaleBuildCache" "$SUPPORT"
touch "$FLAG"

# ~28 MB each so StorageScanner's 20 MB floor picks them up as cache.
dd if=/dev/zero of="$DEMO_DIR/OldInstallerLeftovers/fake-sdk-cache.bin" bs=1024k count=28 status=none
dd if=/dev/zero of="$DEMO_DIR/StaleBuildCache/DerivedData-sim.bin" bs=1024k count=32 status=none
dd if=/dev/zero of="$DEMO_DIR/orphan-xcode-log.blob" bs=1024k count=24 status=none

# Backdate so "idle" heuristics treat them as leftover clutter.
TOUCH_STAMP="202401150101"
touch -t "$TOUCH_STAMP" \
  "$DEMO_DIR/OldInstallerLeftovers/fake-sdk-cache.bin" \
  "$DEMO_DIR/StaleBuildCache/DerivedData-sim.bin" \
  "$DEMO_DIR/orphan-xcode-log.blob" \
  "$DEMO_DIR/OldInstallerLeftovers" \
  "$DEMO_DIR/StaleBuildCache" \
  "$DEMO_DIR"

echo "Seeded demo reclaimables in ~/Library/Caches/PCOptopusDemo"
echo "Demo flag: $FLAG"
du -sh "$DEMO_DIR"/*
