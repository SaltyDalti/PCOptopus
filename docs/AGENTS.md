# Agent interface notes

Package order: **0 scaffold** gates everything. After 0 merges, packages **1–4** may proceed in parallel. Package **5** waits on 1–4. Packages **6–8** follow.

## Ownership

| Package | Paths |
|---------|-------|
| 0 Scaffold | `Package.swift`, `Model/`, `Store/`, `docs/`, `Fixtures/` |
| 1 Fast sensors | `Sensors/FastSensors.swift`, `PmsetParser.swift` |
| 2 Slow sensors | `Sensors/SlowSensors.swift` |
| 3 Policy | `Policy/` |
| 4 Interface | `App/Sources/` (AppKit runtime), `App/SwiftUI/` (Xcode SwiftUI) |
| 5 Apply | `Apply/`, `Helper/` |
| 6 Autopilot | `App/Sources/AppState.swift` loops |
| 7 Coach | `Coach/` |
| 8 Integration | `Scripts/`, `PCOptopusVerification` |

## Rules

- Safety contract in `docs/SAFETY.md` is binding.
- Metric keys in `Model/MetricKeys.swift` stay stable.
- Helper allowlist is code in `Apply/PmsetAllowlist.swift`.
- Do not persist serial numbers or process arguments.
- Prefer fake applier tests over live `pmset` writes.

## Verify

```bash
swift build
swift run PCOptopusVerification
swift run PCOptopus
./Scripts/package-app.sh   # signed app → dist/ + /Applications
```

CI: `.github/workflows/verify.yml` runs `PCOptopusVerification` on macOS 14.
