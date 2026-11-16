# Design write-up — PCOptopus

Interview / portfolio case: native macOS optimizer with a measurable goal (**Pulse = 100**) and production-grade safety rails.

## Problem

“Clean my Mac” tools usually do one of two things: scare the user with junk scores, or mutate the system without a clear undo path. On Apple Silicon laptops, the real pain is quieter — runaway agents, power mode, PATH drift, reclaimable caches — and Full Disk Access prompts that fire on every rebuild make even honest tools feel broken.

## Constraints

- Ship with **Command Line Tools only** (no mandatory Xcode IDE)
- **Empty-by-default contract** — no writes until the user grants a category
- **No automatic deletion** — storage is recommend-only
- Sticky FDA across rebuilds via a **stable local signing identity**
- One headline metric the UI can fight for: **Pulse**

## Approach

**Pulse** collapses sensors into a 0–100 score. When Pulse drops, Today’s **Fight for 100** (and optional auto-fight) applies only autopilot-capable, already-granted fixes — never delete, never confirm-tier without the user.

**Policy** owns cooldowns, required ticks before fire, and the kill switch. **Journal** is write-ahead: every apply records before/after so Undo is real. **Contract** is the grant list; Settings and Contract edit it in place so AppKit controls stay live under a high-frequency UI tick.

**Storage** scans Library-scoped reclaim candidates only, so ordinary Documents/Downloads use doesn’t thrash TCC. Packaging signs into a dedicated keychain so `codesign` doesn’t hang on the login keychain UI.

## Trade-offs

| Chose | Instead of | Why |
|-------|------------|-----|
| AppKit CLT binary | SwiftUI-only Xcode app | Builds on a fresh Mac with CLT |
| Recommend-only cleanup | Auto-delete caches | Trust + interview demo safety |
| Local signing identity | Ad-hoc / CDHash churn | FDA survives rebuilds |
| Fight-for-100 autopilot | Manual-only apply | Goal is visible; still grant-gated |
| In-place control updates | Full view rebuild each tick | Dead checkboxes / lost clicks |

## Result

A demable loop: Pulse dips → Fight for 100 → Journal Undo → Contract empty = zero writes. Verification harness is the CI gate. Packaging lands a signed `/Applications/PCOptopus.app` suitable for a 90-second walkthrough.

## What I’d do next

Notarization + Developer ID for distribution outside this machine; richer storage “show me” without extra TCC prompts; optional Helper notarization path; broaden sensors without widening the delete surface.
