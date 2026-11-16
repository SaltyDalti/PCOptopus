# Automated demo capture

Privacy-safe walkthrough of PCOptopus. Captures **only** the app window (no desktop, no username).

## What it does

1. Seeds fake reclaimables under `~/Library/Caches/PCOptopusDemo`
2. Enables demo mode (`demo.flag` / `--demo`) → Mac name becomes **Demo MacBook Pro**, storage scan only sees the seed folder
3. Drives: Today → Fight for 100 → Journal → Contract → Machine → Settings → delete seed → re-scan
4. Writes `pcoptopus-demo.mp4` (~24s silent)

PCOptopus **never deletes**. The script removes only the fake seed files to show a before/after scan.

## Run

```bash
./Scripts/seed-demo-storage.sh
# optional: enlarge leftovers for a dramatic 1 GB+ plan
open -n /Applications/PCOptopus.app --args --demo
./Scripts/run-demo-capture.sh
./Scripts/cleanup-demo-storage.sh
```

Output: `docs/demo/pcoptopus-demo.mp4` and `docs/demo/frames/`.

## Voiceover (automated)

```bash
./Scripts/build-demo-vo.sh
```

Uses macOS `say` (default voice: Samantha) + ffmpeg to produce `pcoptopus-demo-vo.mp4`.
Script lines live in `vo-script.txt`. Override voice with `PCOCTOPUS_DEMO_VOICE=Reed ./Scripts/build-demo-vo.sh`.

For a clone of your own voice later, swap the audio in Descript/ElevenLabs and remux.
