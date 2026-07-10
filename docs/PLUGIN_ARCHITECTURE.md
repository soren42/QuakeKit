# Plugin Architecture

QuakeKit separates extension points into two families:

- **Theme plugins** own presentation: colors, typography, metrics, standard
  component styles, design assets, and limited user-facing visual settings.
- **Functional plugins** own behavior: actions, data streams, views, process
  execution, and external integrations.

Functional plugins should support two presentation shapes:

- **Applet pages**: full-panel or multi-page experiences, such as weather, an AI agent console, or a system dashboard.
- **Widgets**: compact grid tiles that can be arranged alongside other widgets.
- **Main-menu widgets**: special launcher views that render the Home page and
  route to host pages, plugin views, plugin actions, carousel controls, or safe
  status messages.

The functional plugin manifest describes both shapes. A functional plugin can
expose any mix of actions, data streams, and views. Theme plugins use a separate
manifest and package suffix so presentation and behavior can evolve
independently.

Functional plugins are validated by
[`schemas/functional-plugin.schema.json`](../schemas/functional-plugin.schema.json).
See [FUNCTIONAL_PLUGIN_SPEC.md](FUNCTIONAL_PLUGIN_SPEC.md) for the complete
functional plugin contract.

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
- `presentation`: page, widget, both, or mainMenu
- `icon`: SF Symbol name for native launcher and compact widget surfaces
- `entryPath`: local web/native asset entrypoint when needed
- `dataStreamID`: stream backing the view
- `columnSpan` and `rowSpan`: widget grid hints
- `preferredWidth` and `preferredHeight`: page/widget layout hints
- `menuItems`: declarative launcher entries when `presentation` is `mainMenu`

The current host loads manifests from `Examples/Plugins`. The panel shell builds
separate `Widgets` and `Apps` pages from those manifests, declared plugin
actions appear on the `Apps` page for early runtime testing, and the Home page
uses the selected `mainMenu` view with a built-in fallback.

## Example Targets

- `system_monitor`: shell-backed system utilization dashboard.
- `weather`: web canvas weather page and widget.
- `markets`: PHP-backed market ticker widget.
- `sports_scores`: process-backed scoreboard page and widget.
- `ai_agent`: microphone-capable conversational agent page.
- `main_menu_classic`: declarative Home-page launcher widget.

These examples now include minimal runnable or renderable package assets. Local
shell, PHP, and stdio-style actions can be invoked by `PluginExecutionHost` and
from `quake-probe --run-plugin-action`. Full applet/widget rendering and live
data-stream subscription are still implementation layers in progress. Data-driven
plugin detail surfaces can already capture a first action result into
`PluginDataStore` and display that payload as a runtime snapshot.

The bundled weather, markets, and sports adapters attempt live public data with
short timeouts and then return deterministic fallback payloads. This makes the
examples useful on-device without API keys while preserving reliable tests.
