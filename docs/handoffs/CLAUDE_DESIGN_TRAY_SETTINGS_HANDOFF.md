# QuakeKit Tray and Global Settings Redesign Handoff

## Assignment

Design the macOS-primary settings experience opened from the QuakeKit menu-bar
icon. This is a keyboard-and-mouse configuration surface on the primary display,
not a DK panel page. Deliver canonical HTML/CSS/JS mockups and a concise
implementation handback for the Swift/AppKit host.

The panel itself is a 1920 x 480 touch/knob instrument. The Settings window is
the operational control plane for that instrument: dense, calm, and efficient.
It should feel like a native macOS utility, not a marketing page or a floating
dashboard of nested cards.

## Current Runtime and Navigation

- App is a menu-bar accessory (`LSUIElement`); it should not present as a Dock
  app in normal launch mode.
- Current tray menu: `Open Settings...`, `Show Panel`, microphone permission,
  30-second meeting recording, speaker test, and Quit.
- Selecting `Open Settings...` opens one resizable native window on the primary
  display. Reuse that model; no panel-screen configuration flow is required.
- Existing top-level settings sections: `Global`, `Themes`, `Widgets & Apps`,
  `Carousel`, `Plugins`, `About`.
- Do not redesign the status-bar icon itself. The shipped source of truth is the
  `trayTemplate-18{,@2x}.png` template image and `seismic-q-tray-template.svg`.

## Data and Persistence Contract

The host persists JSON at `~/Library/Application Support/QuakeKit/settings.json`
and `theme-config.json`. The proposed design must expose these real controls,
not static sample values.

### Global

- Default panel page.
- Main menu widget: `Status Rail` (default), `Radial Orbit`, `Ambient Marquee`,
  `Classic Built-in Menu`, plus future installed `mainMenu` plugin packages.
- Contextual menu options:
  - Status Rail: `railMode` (`labels`, `collapsed`).
  - Radial Orbit: `headlineProjection` (boolean).
  - Ambient Marquee: `dockPolicy` (`always`, `autohide`) and `chipOverflow`
    (`paginate`, `scroll`, `shrink`).
- Package folder access and release/build information.

### Themes

- Nine shipped choices: Cyberpunk Neon, Focus Dark, Weather Glass, Vantage
  Dark/Light, Aqua Glass Dark/Light, BeOS Light/Dark.
- Immediate active-theme selection.
- Theme-defined configurable options: color, number, boolean, and choice.
- Restore packaged defaults.
- List installed themes with source/path and removal action for user-installed
  packages only.

### Widgets and Apps

- Inventory of plugin views, with name, source plugin, presentation
  (`widget`, `page`, `pageAndWidget`, `mainMenu`), native SF Symbol icon, and
  whether it is eligible for Home/carousel display.
- Opening plugin settings routes to the plugin’s specific settings form.
- Widget tiles show a compact subset of the full page payload. The Settings UI
  may manage Home inclusion/order later, but should reserve a clear place for it.

### Carousel

- Enable/disable.
- Duration choices: 5, 10, 15, 30, 60 seconds.
- Explicit include list of eligible widget views, with All/None controls.

### Plugins and Packages

- Plugin inventory: transport, permission summary, capabilities, settings count,
  source location, and reset settings.
- Install Plugin and Install Theme use native file selection and accept package
  directories or supported tar bundles.
- User-installed packages can be removed. Bundled examples cannot.
- Never display secret values. Permission declarations must remain visible and
  comprehensible before a user enables/configures an integration.

### Audio and Privacy

- Microphone authorization status.
- Meeting recording action/status.
- Speaker-output test state.
- Make permission state unmistakable; do not imply active recording when none is
  occurring.

## Brand and Visual Requirements

- Follow `docs/brand/index.html` and `docs/brand/QuakeKit-Brand-Standards.pdf`.
- Tone: terse, technical, neutral. Labels are nouns; actions are verbs.
- Use the supplied Seismic mark/wordmark only. Do not redraw or recolor the mark.
- Use SF Symbols or Lucide-style 2px outline equivalents; no emoji or decorative
  icon clusters.
- The window can adapt to the active theme for preview surfaces, but primary
  settings controls must remain legible and native-feeling in macOS light/dark
  appearance.
- Avoid nested cards. Use a clear sidebar/toolbar plus a single detail surface
  with grouped rows, tables, and inspector-style controls.

## Design Deliverables

1. One canonical settings window design at desktop width, covering all sections.
2. A narrow-window/responsive state that preserves labels and controls.
3. States for empty inventory, loading/refreshing data, plugin permission issue,
   failed package install, and destructive removal confirmation.
4. Native file-picker entry points for package installation, shown as actions
   rather than a custom faux filesystem browser.
5. A component/state inventory and AppKit handback:
   - screen hierarchy;
   - each control’s binding key/type;
   - selected, disabled, empty, error, and hover/focus state;
   - which visuals are shell-owned versus plugin-provided;
   - exact icon asset/SF Symbol names where supplied.

## Out of Scope

- HID wake/keepalive, input capture, display ownership, and knob ring protocol.
- A web settings implementation; the host is Swift/AppKit.
- Storing API keys in plaintext or showing secrets in the UI.
- Changing the on-panel menu templates, shared plugin backpages, or theme format.

## Relevant Code

- `Sources/QuakePanelHost/SettingsWindow.swift`
- `Sources/QuakePanelHost/main.swift` (`QuakeSettingsConfiguration`, tray menu,
  package loaders, app lifecycle)
- `Sources/QuakePluginAPI/PluginManifest.swift`
- `Sources/QuakePluginAPI/ThemeManifest.swift`
- `Sources/QuakePluginAPI/QuakePackageInstaller.swift`
- `docs/brand/index.html`
- `docs/brand/QuakeKit-Brand-Standards.pdf`
