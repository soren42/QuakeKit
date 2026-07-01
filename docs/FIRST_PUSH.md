# First Push Checklist

Use this before publishing the initial GitHub repo.

## Local Checks

```bash
swift build
.build/debug/quake-probe --self-test
.build/debug/quake-probe --validate-plugin Examples/Plugins/echo-plugin.json
.build/debug/quake-probe --all-hid
```

Optional hardware checks:

```bash
.build/debug/quake-probe --listen --wake
.build/debug/quake-probe --led-on
.build/debug/quake-probe --led-off
.build/debug/quake-panel --debug-window
```

## Recommended GitHub Settings

- Enable Issues.
- Enable Discussions if you want community hardware reports and integration ideas outside the issue tracker.
- Add repository topics:
  - `dk-quake`
  - `aris-68`
  - `macos`
  - `swift`
  - `hid`
  - `control-center`
  - `plugin-api`
- Protect `main` after the initial push if outside contributors become active.
- In GitHub's license detection, verify that the repository is detected as AGPL-3.0.

## Initial Commit Message

```text
Initial Swift-native OpenQuake platform skeleton
```

## Suggested Repo Description

```text
Swift-native macOS platform for the DK-Quake / ARIS-68 touch display and control center.
```

## Known Status To Publish

- HID control input works.
- HID touch input works.
- Knob-ring output works.
- Plugin manifest model and validator exist.
- AppKit panel renders in screenshots and on the main display.
- Physical DK glass may remain black even when macOS screenshots show the panel UI. Help wanted.

## License Status

- Original project code: AGPL-3.0-or-later.
- DK-Quake protocol implementation: public non-commercial protocol caveat remains; do not imply commercial availability.
