# Architecture

OpenQuake Mac is structured as a platform, not a single-purpose dashboard app.

## Layers

1. **Device adapters**
   - Own transport-specific I/O.
   - Convert device bytes into normalized runtime events.
   - Accept safe device commands such as wake, keep-alive, lighting, and mic state.

2. **Runtime core**
   - Owns pages, layouts, actions, state, routing, and event dispatch.
   - Knows about concepts like tiles, widgets, dashboard pages, and action bindings.
   - Does not know whether a plugin is Swift, JSON-RPC, WebSocket, or another process.

3. **Plugin API**
   - Language-neutral manifest and message contract.
   - Supports data providers, action providers, view providers, device providers, and background workers.
   - Uses explicit permissions and host-granted capabilities.

4. **Host apps**
   - macOS host first, built with Swift/AppKit/SwiftUI.
   - Owns OS-specific windowing, secrets, audio, HID access, media keys, and app launching.
   - Future hosts can implement the same runtime/plugin contracts on Windows or Linux.

## Milestone 1

- Build and test the DK-Quake HID probe.
- Build a minimal native panel host that proves HID events can drive AppKit UI.
- Stabilize Codable models for pages, tiles, actions, plugin manifests, and events.
- Add one trivial external plugin contract example before building rich end-user apps.
- Keep first-party integrations as Swift modules but design third-party integrations as out-of-process plugins.

## Non-Goals For Milestone 1

- Full editor UI.
- Arbitrary third-party executable plugin installation.
- Rich bundled apps such as music, Home Assistant, or system monitor.
- HID display-frame pushing. The DK-Quake screen is treated as a normal external display.
