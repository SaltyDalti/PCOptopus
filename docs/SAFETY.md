# PCOptopus Safety Contract

Binding on every agent and every build. Autopilot starts **off**. An empty contract is a valid steady state: nothing granted, so nothing will change.

## Autopilot may change only granted items

- Autopilot may change only items the user granted, and only inside numeric bounds stored in the contract.
- v1 autopilot keys, via the privileged helper, are: `sleep`, `displaysleep`, `disksleep`, `powernap`, `womp`, `tcpkeepalive`, `ttyskeepawake`, scoped per power source (`-c` AC or `-b` battery).
- v1 autopilot may also `launchctl bootout` / `bootstrap` a **user** LaunchAgent whose label the user disabled in the contract. The original plist is copied into the journal before the change.
- System agents and `/Library/LaunchDaemons` stay out of autopilot.

## Confirm-tier (never automatic)

- Shell PATH edits (`~/.zprofile`)
- Low Power Mode
- Quitting an app that holds a sleep assertion
- Opening a vendor preference pane

## Manual-tier (explain and point; do not execute)

- Deleting caches or apps
- Moving Homebrew bottles
- `hibernatemode`, `standby`
- Spotlight reindex, iCloud, firewall, FileVault, firmware, NVRAM, SIP

## Hard bans

- Disabling SIP
- `kill -9`
- Packet capture
- Reading Documents / Mail / Photos / Messages
- Storing command-line arguments of processes
- Sending samples off the machine
- Letting the on-device model invent shell commands

## Write-ahead journal

1. Insert the intended before/after into the journal.
2. Apply the change.
3. Mark the entry applied or failed.
4. Undo replays the stored previous value.

## Kill switch and pauses

- Kill switch in the menu bar is checked by both the app tick and the helper before every privileged call.
- Pause autopilot while a prevent-sleep assertion is held.
- Pause autopilot while thermal state is serious or critical.

## Rate limits

- At most 6 autopilot applies per hour.
- 10-minute cooldown per action id.
- A finding must persist for two consecutive slow ticks before it fires.

## Helper allowlist

The helper allowlist is **code**, not a prompt. Unknown keys are refused.
