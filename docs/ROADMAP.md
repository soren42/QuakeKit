# Roadmap

## Phase 0: Native Platform Skeleton

- SwiftPM package with separable runtime, HID, and plugin API modules.
- DK-Quake HID protocol encoder/decoder.
- CLI probe for hardware enumeration and live event logging.
- Manifest validator for the first language-neutral plugin contract.
- Minimal AppKit panel host that draws a native grid and consumes HID knob/touch events.

## Phase 1: macOS Host Runtime

- AppKit panel window placed on the DK-Quake display.
- Runtime event bus connected to HID touch and knob events.
- Page model rendering with a simple grid.
- Basic action dispatcher for page switching and host status messages.
- Keychain-backed secret store abstraction.

## Phase 2: Plugin Runtime

- Plugin registry persisted in app support.
- In-process Swift plugin adapter for first-party integrations.
- Out-of-process JSON-RPC adapter over stdio.
- Permission grant UI and persisted grants.
- Data snapshot/stream subscriptions.

## Phase 3: Extensible Control Center

- Dashboard pages with `WKWebView`.
- Native settings/editor UI.
- Home Assistant as a plugin, not a hard-coded feature.
- System metrics, music, calendar, and other integrations built on the same plugin surfaces.
- OS-agnostic protocol documentation for future Windows/Linux hosts.
