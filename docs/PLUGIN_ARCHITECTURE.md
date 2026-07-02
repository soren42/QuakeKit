# Plugin Architecture

QuakeKit separates extension points into two families:

- **Theme plugins** own presentation: colors, typography, metrics, standard
  component styles, design assets, and limited user-facing visual settings.
- **Functional plugins** own behavior: actions, data streams, views, process
  execution, and external integrations.

Functional plugins should support two presentation shapes:

- **Applet pages**: full-panel or multi-page experiences, such as weather, an AI agent console, or a system dashboard.
- **Widgets**: compact grid tiles that can be arranged alongside other widgets.

The functional plugin manifest describes both shapes. A functional plugin can
expose any mix of actions, data streams, and views. Theme plugins use a separate
manifest and package suffix so presentation and behavior can evolve
independently.

## Theme Plugins

Theme plugin packages use the `.quakekittheme` suffix and contain a required
`theme.json` manifest. They are validated by
[`schemas/theme-plugin.schema.json`](../schemas/theme-plugin.schema.json).

Theme plugins define:

- palette tokens and semantic colors
- typography scale and preferred font families
- spacing, density, border, and corner metrics
- standard component styles for tiles, tabs, rows, gauges, and charts
- optional assets such as images, fonts, CSS, or sounds
- user-configurable visual options, primarily color and density controls

See [THEME_PLUGIN_SPEC.md](THEME_PLUGIN_SPEC.md) for the complete theme contract.

## Plugin Lanes

### Process Plugins

Process plugins are the default power-user lane. They run out of process and can
be written in shell, PHP, Python, Swift, Go, JavaScript, or any executable
runtime. The preferred protocol is JSON over stdio.

Use this lane for:

- shell and PHP plugins
- weather, market, and sports data adapters
- AI-agent adapters
- scripts that publish data streams or handle actions

### Web Views

Web plugins expose HTML, CSS, JavaScript, or canvas-based surfaces hosted by the
native app. They are a strong fit for highly styled pages and animated widgets.

Use this lane for:

- elegant dashboards
- weather scenes
- charts and scoreboards
- chat and transcript surfaces

### Native Swift

Native Swift plugins are the trusted, high-performance lane. Early versions can
be compiled into the app as Swift packages. Dynamic native bundles should wait
until signing, ABI, and capability boundaries are mature.

Use this lane for:

- privileged macOS integrations
- performance-sensitive views
- host-owned services like microphone capture

## Manifest Surface Model

Each `PluginView` declares:

- `type`: native, web canvas, web document, text, or data-driven
- `presentation`: page, widget, or both
- `entryPath`: local web/native asset entrypoint when needed
- `dataStreamID`: stream backing the view
- `columnSpan` and `rowSpan`: widget grid hints
- `preferredWidth` and `preferredHeight`: page/widget layout hints

The current host loads manifests from `Examples/Plugins`. The panel shell builds
separate `Widgets` and `Apps` pages from those manifests.

## Example Targets

- `system_monitor`: shell-backed system utilization dashboard.
- `weather`: web canvas weather page and widget.
- `markets`: PHP-backed market ticker widget.
- `sports_scores`: process-backed scoreboard page and widget.
- `ai_agent`: microphone-capable conversational agent page.

These examples are manifest-first. Rendering and process execution are the next
implementation layers.
