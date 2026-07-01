# Contributing

Thanks for helping with OpenQuake Mac. This project is still early, so the most useful contributions right now are careful hardware reports, small focused fixes, and documentation of DK-Quake behavior across different Macs and macOS versions.

## Development Setup

Requirements:

- macOS 14 or newer
- Xcode Command Line Tools
- Swift Package Manager
- DK-Quake / ARIS-68 hardware for device testing

Build:

```bash
swift build
```

Run protocol checks without hardware:

```bash
.build/debug/quake-probe --self-test
```

Enumerate the device:

```bash
.build/debug/quake-probe --all-hid
```

Run the live input probe:

```bash
.build/debug/quake-probe --listen --wake
```

Run the native panel host:

```bash
.build/debug/quake-panel --debug-window
```

## Safety Rules

- Do not add, expose, or run DFU / firmware-flash commands.
- Do not test unknown output frames casually. Document the source and intended effect first.
- Prefer read/query commands and visibly reversible commands such as knob-ring lighting.
- Keep dangerous host actions such as shell execution, app launching, file writes, microphone capture, and network proxying behind explicit permission boundaries.
- If a test requires unplugging/replugging hardware, changing macOS Display Settings, or granting permissions, say so clearly in the issue or PR.

## License Expectations

By contributing, you agree that your contribution is made under this repository's license: GNU Affero General Public License v3.0 or later.

Do not contribute code copied from DK-Suite, vendor binaries, private SDKs, or proprietary sources. Protocol behavior should be documented from lawful observation, public community research, or your own tests.

## What Helps Most Right Now

- `quake-probe --all-hid` output from different systems.
- Confirmation of touch/knob/LED behavior.
- Reports about the physical DK screen staying black while screenshots show the rendered panel.
- Small fixes with a clear before/after test.
- Documentation of macOS permission prompts and display rotation behavior.

## Pull Request Guidelines

- Keep PRs focused. One hardware behavior or module boundary per PR is ideal.
- Include the commands you ran.
- Include hardware details when the change touches HID/display behavior.
- Avoid broad refactors while the platform shape is still settling.
- Do not commit `.build/`, screenshots, local app state, or generated Xcode user data.

## Current Architecture Direction

OpenQuake Mac is a platform first:

- `QuakeHID`: device transport and DK-Quake protocol handling.
- `QuakeRuntime`: runtime events, pages, tiles, actions, and state.
- `QuakePluginAPI`: language-neutral plugin manifests and host/plugin messages.
- `quake-probe`: hardware diagnostic CLI.
- `quake-panel`: first native AppKit panel host.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/ROADMAP.md](docs/ROADMAP.md).
