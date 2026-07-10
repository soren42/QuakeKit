# QuakeKit RC1 Independent Review Packet

## Scope

Review the RC1 candidate as a macOS AppKit host for the DK-QUAKE / ARIS-68
display. The review must distinguish confirmed behavior from offline-safe
fixtures and must not recommend browser automation of consumer LLM products.

## Candidate Contents

- Three selectable native menu shells: Status Rail (default), Radial Orbit, and Ambient Marquee.
- Shared full-page data renderer, with first-class System Monitor, Weather, Music, and AI Command Center surfaces.
- Music consolidates the old Spotify examples under a source selection setting.
- AI Command Center consolidates individual LLM harness examples under an agent/harness selection setting.
- `.app` bundle is an unsigned menu-bar accessory for local testing.
- Hardware transport and keepalive behavior are unchanged from the verified vendor-frame implementation.

## Required Local Gate

```bash
cd /Users/jason/Code/QuakeKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/validate-release.sh
open .build/QuakeKit.app
```

Use `--debug-window --no-hid` only for host-side visual inspection. Use the
normal app bundle on physical hardware for touch/knob/display checks.

## Claude Fable-5 Review

Ask Fable-5 for a rigorous code review. It should inspect architecture,
concurrency/lifecycle, unsafe filesystem/process behavior, manifest validation,
and AppKit rendering edge cases. Require findings in this exact order:

1. Severity-ranked findings with file and line references.
2. Missing or fragile tests.
3. RC1 release blockers versus follow-ups.
4. A short verification log for each command it actually ran.

Focus files:

- `Sources/QuakePanelHost/main.swift`
- `Sources/QuakePanelHost/MenuChromeView.swift`
- `Sources/QuakePanelHost/DataBoardView.swift`
- `Sources/QuakePanelHost/SettingsWindow.swift`
- `Sources/QuakeHID/QuakeDevice.swift`
- `Sources/QuakePluginAPI/PluginRegistry.swift`

## Grok-4.5 Product Feedback Run

Ask Grok-4.5 to test as an informed DK-QUAKE owner, not merely as a code
reviewer. It should navigate all three menu styles, open every standard page,
exercise Music and AI Command Center settings, and report usability feedback
separately from defects.

Required checks:

- Status Rail: rail touch targets, knob focus, overflow behavior, legibility.
- Radial Orbit: tab touch targets, focused hub projection, app/page transition clarity.
- Ambient Marquee: dock readability, touch targets, content not occluded by chrome.
- Themes: all installed themes preserve text contrast and focus visibility.
- Settings: Main Menu Widget selector and its contextual settings persist after relaunch.
- Consolidation: only one Music and one AI launcher entry; legacy IDs are not exposed.
- Hardware: cold wake, 15-second keepalive past 90 seconds, touch, knob directions, knob ring, panel fullscreen behavior.

## Feedback Format

Return one issue per item using:

```text
Severity: blocker | high | medium | low | feedback
Area:
Reproduction:
Expected:
Actual:
Evidence: screenshot/log/file:line
Suggested disposition: fix RC1 | track post-RC1 | not reproducible
```

No automated changes should be made directly from either review. Reconcile
findings against the manifest/plugin safety model before implementation.
