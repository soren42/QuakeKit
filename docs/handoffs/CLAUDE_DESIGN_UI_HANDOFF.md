# QuakeKit UI Redesign Handoff For Claude Design

## Assignment

You are designing the frontend/interface package only. Do not change hardware protocol behavior, plugin execution behavior, app permissions, or Swift runtime architecture. The Home/main menu is now a selectable special plugin view class, so your primary deliverable should include a redesigned main-menu widget package that can be handed back to Codex for integration into the Swift/AppKit QuakeKit host.

## Project Summary

QuakeKit is a Swift-native macOS control center for the DK-QUAKE / ARIS-68 touch display. The device appears to macOS as a wide external display plus HID touch/knob/control interfaces. QuakeKit renders a native panel window on the DK display, reads touch and knob input, wakes and keeps the device alive, controls the knob LED ring through semantic theme states, and exposes a modular plugin/theme platform.

The long-term goal is a polished native replacement for the stock DK app, with an extensible platform for widgets, full-page applets, automation panels, voice/AI workflows, and third-party themes.

## Current UI Surfaces

- DK panel pages: Home, Widgets, Apps, Themes, Settings, Runtime, Plugin APIs.
- Home is no longer hard-coded chrome. It is rendered from a selected `mainMenu` widget view, with `builtin:classic` as fallback and `Examples/Plugins/main-menu-classic.quakekitplugin` as the bundled package template.
- Primary-monitor settings window: Global, Themes, Widgets & Apps, Carousel, Plugins, About.
- macOS menu-bar accessory: Open Settings, Show Panel, microphone controls, meeting clip, speaker test, Quit.
- Full-screen/freeform applets: System Monitor and Weather are the strongest current design testbeds.
- Generic data-driven plugin surfaces: most integration fixtures return `rows`, `actions`, status fields, and structured payloads for renderer experimentation.
- Theme examples: Focus Dark, Cyberpunk Neon, Weather Glass.

## Current Functionality Status

- Hardware wake/keep-alive, panel rendering, touch input, knob input, and knob LED output are working.
- The app can be launched from the Swift build or assembled into a local `.app` bundle for testing.
- Plugin/theme package install and remove exist in the primary settings window, with restart required for package rediscovery.
- Global settings include a Main Menu Widget selector. Installed plugin packages can provide alternate menu widgets through `presentation: "mainMenu"`.
- Carousel can rotate eligible widget views with configurable duration and inclusion list.
- Plugin fixtures are offline-safe and deterministic. They provide displayable payloads even without credentials.
- LLM harnesses are UI-ready stubs only; they describe official API/local companion boundaries and should not imply consumer-UI scraping.
- Permission and secret handling are partially declarative. Do not design final security UX as if every grant flow already exists.

## Design Goals

1. Redesign the DK-panel main menu/navigation as a `mainMenu` widget package, not as hard-coded host chrome.
2. Preserve dense, glanceable utility. The display is wide and short; avoid tall marketing-style compositions.
3. Support both widgets and full-page/multi-page applets.
4. Account for non-grid layouts: full screen, two halves, thirds, quarters, and half-screen plus grid.
5. Make plugin data/action payloads visually coherent without requiring every plugin to supply custom UI.
6. Treat themes as a real design system: tokens, components, layout hints, assets, knob-ring semantics.
7. Keep primary settings window macOS-standard and mouse/keyboard friendly.
8. Design for touch and knob operation on the DK panel.

## Important Constraints

- Target display: 1920 x 480 landscape, with possible 480 x 1920 portrait support later.
- App shell is currently AppKit/Swift, not web-first.
- User interaction on the device is touch plus knob. Pointer is intentionally discouraged on the DK screen.
- Text must remain readable at a glance and not overlap at narrow panel height.
- Do not depend on network credentials for default UI states.
- Do not invent plugin fields that cannot be mapped to current or near-term manifest/data payloads. If you need new fields, list them explicitly as integration requirements.

## Source Documents To Read

- Documentation styleguide: `docs/manuals/styleguide.html`
- User manual: `docs/manuals/user-manual.html`
- Developer guide: `docs/manuals/developer-guide.html`
- Plugin developer guide: `docs/manuals/plugin-developer-guide.html`
- Theme designer handbook: `docs/manuals/theme-designers-handbook.html`
- Documentation gap ledger: `docs/manuals/documentation-gap-ledger.html`
- Functional plugin schema: `schemas/functional-plugin.schema.json`
- Theme schema: `schemas/theme-plugin.schema.json`
- Current plugin examples: `Examples/Plugins/`
- Main-menu package template: `Examples/Plugins/main-menu-classic.quakekitplugin/manifest.json`
- Current theme examples: `Examples/Themes/`

## Implementation Files To Understand

- Panel host and status menu: `Sources/QuakePanelHost/main.swift`
- Primary settings window: `Sources/QuakePanelHost/SettingsWindow.swift`
- Weather panel renderer: `Sources/QuakePanelHost/WeatherPanel.swift`
- System/data dashboard renderer: `Sources/QuakePanelHost/DataBoardView.swift`
- Theme model: `Sources/QuakePluginAPI/ThemeManifest.swift`
- Plugin model: `Sources/QuakePluginAPI/PluginManifest.swift`

## Current Themes

| Theme | Use Case | Notes |
| --- | --- | --- |
| Focus Dark | restrained operational dashboard | best neutral default candidate |
| Cyberpunk Neon | high-contrast system monitor / btop-style dashboard | strongest stylized theme |
| Weather Glass | ambient weather and passive information panels | now includes a backdrop SVG and layout hints |

## Plugin Payload Expectations

Generic data-driven plugins now tend to emit:

- `ok`
- `status`
- `mode`
- `rows[]` with `title`, `value`, `detail`
- `actions[]` with `id`, `title`, `enabled`, optional `dryRun`
- plugin-specific arrays such as `games[]`, `symbols[]`, `actionItems[]`, `devices[]`, `cameras[]`, `tasks[]`, `transcriptSegments[]`

Design a generic data card/page system that can gracefully render these fields without custom UI for every plugin.

## Main Menu Widget Contract

The main menu is a functional plugin view with `presentation: "mainMenu"`.
It can declare `menuItems[]` with:

- `id`
- `title`
- `subtitle`
- `icon` as a future token
- `action`: `page`, `pluginView`, `pluginAction`, `status`, `carousel`, or `settings`
- `target`: examples include `widgets`, `runtime`, `weather:weather.canvas`, `system_monitor:system.overview`, `toggle`, `settings`, or `plugin:weather`
- `order`

Design work should therefore deliver a menu package specification: layout, tile hierarchy, focus states, touch zones, optional icon tokens, and a manifest-level `menuItems[]` proposal. If new visual-only fields are needed, list them as schema requests rather than assuming Swift behavior already exists.

## Requested Deliverable Back To Codex

Provide an interface package containing:

- DK-panel main navigation redesign as a selectable `mainMenu` widget package.
- Widget grid and overflow/page controls.
- Full-page applet templates for System Monitor and Weather.
- Generic data-driven plugin card and detail templates.
- Primary settings window visual treatment.
- Theme token recommendations for Focus Dark, Cyberpunk Neon, and Weather Glass.
- Component specifications for tabs, tiles, status rows, gauges, charts, action buttons, forms, alerts, and empty/loading/error states.
- Touch/knob interaction notes.
- Any requested schema or runtime additions, clearly separated from pure UI assets.

Preferred output format: design mockups plus an implementation-oriented spec that Codex can translate into Swift/AppKit code.

## Do Not Do

- Do not modify HID protocol assumptions.
- Do not design unsafe device-command probing.
- Do not automate or scrape consumer LLM, Spotify, YouTube, or other vendor UIs in ways that violate terms.
- Do not make the DK panel look like a generic website landing page.
- Do not require every plugin to ship custom views before it can look good.

## Open UI Questions

- Which bundled `mainMenu` package should become the v1.0 default: classic launcher, status-first dashboard, carousel landing page, or a hybrid?
- Should applet pages have persistent top navigation, edge swipe/touch pads, or transient navigation chrome?
- How should knob focus be visualized across themes?
- How much information should the DK panel show versus the primary settings window?
- What is the best default theme for v1.0: Focus Dark or Cyberpunk Neon?
