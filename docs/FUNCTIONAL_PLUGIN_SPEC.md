# Functional Plugin Specification

QuakeKit functional plugins provide behavior: actions, data streams, applet
pages, widgets, adapters, and background work. Presentation belongs to theme
plugins; functional plugins should expose intent and data, then let the host and
active theme decide how that work is rendered.

The normative machine schema is
[`schemas/functional-plugin.schema.json`](../schemas/functional-plugin.schema.json).
For language-specific manifest examples, see
[PLUGIN_LANGUAGE_EXAMPLES.md](PLUGIN_LANGUAGE_EXAMPLES.md).

## Package Layout

A functional plugin package is a directory ending in `.quakekitplugin`.

```text
Examples/Plugins/weather.quakekitplugin/
  manifest.json
  index.html
  assets/
```

Loose JSON manifests such as `Examples/Plugins/echo-plugin.json` are supported
for early development and validation. Packaged plugins should use
`manifest.json` at the package root.

Installable bundles may be provided either as an unpacked `.quakekitplugin`
directory or as a `.tar`, `.tar.gz`, or `.tgz` archive containing one plugin
directory. The installer validates the manifest before copying the package into
`~/Library/Application Support/QuakeKit/Plugins/`.

## Manifest Fields

### Root

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `$schema` | string | no | JSON Schema URL or relative path for editor validation. |
| `id` | string | yes | Stable lowercase id. Pattern: `^[a-z0-9][a-z0-9_-]*$`. |
| `name` | string | yes | Human-readable plugin name. |
| `version` | string | yes | Plugin version. SemVer is recommended. |
| `apiVersion` | string | yes | QuakeKit plugin API version. Current value: `0.1`. |
| `entry` | object | yes | Plugin entrypoint and transport. |
| `capabilities` | array | no | Host-facing feature flags exposed by the plugin. |
| `permissions` | array | no | Explicit capabilities requiring user or host trust. |
| `settings` | array | no | User-configurable plugin preferences exposed in the host settings UI. |
| `actions` | array | no | Commands the host or user can invoke. |
| `dataStreams` | array | no | Published values that views and other plugins may consume. |
| `views` | array | no | Applet pages, widgets, or shared page/widget surfaces. |

## Entry

`entry.transport` declares how the host starts or embeds the plugin.

| Transport | Use |
| --- | --- |
| `stdioJSONRPC` | Out-of-process adapter using JSON messages over standard input/output. |
| `websocket` | Local or remote service using a WebSocket bridge. |
| `nativeSwift` | Trusted Swift implementation compiled into, or loaded by, the host. |
| `webView` | HTML/CSS/JavaScript surface hosted by the native app. |
| `shell` | Shell script or executable process. |
| `php` | PHP script process. |

Supported entry fields:

| Field | Type | Description |
| --- | --- | --- |
| `transport` | string | Required transport value. |
| `command` | string or null | Executable, script, native symbol, or adapter command. |
| `arguments` | array | Optional command arguments. |
| `url` | string or null | Local package path or URL for web-style transports. |

## Capabilities

Capabilities are coarse host-discovery flags:

- `settings`
- `eventPublisher`
- `eventSubscriber`
- `dataProvider`
- `actionProvider`
- `viewProvider`
- `deviceProvider`
- `backgroundWorker`

The host should use capabilities for discovery and placement, not as a security
boundary. Security-sensitive access belongs in `permissions`.

## Permissions

Permissions use Swift enum-style single-key objects. Each array item must contain
exactly one permission.

| Permission | Shape | Description |
| --- | --- | --- |
| `network` | `{ "network": { "hosts": ["api.example.com"] } }` | Allows outbound access to listed hosts. |
| `secrets` | `{ "secrets": { "keys": ["API_KEY"] } }` | Allows named secret lookup. |
| `filesystem` | `{ "filesystem": { "paths": ["~/Data"], "write": false } }` | Allows scoped file access. |
| `inputSynthesis` | `{ "inputSynthesis": {} }` | Allows synthetic input events. |
| `audioCapture` | `{ "audioCapture": {} }` | Allows microphone/audio capture. |
| `audioPlayback` | `{ "audioPlayback": {} }` | Allows speaker or system audio playback. |
| `localProcess` | `{ "localProcess": {} }` | Allows local process inspection or execution. |

Permissions should be narrow and declarative. A plugin should request the minimum
set needed for its declared actions, streams, and views.

## Settings

Settings are user-editable plugin preferences. They are intended for runtime
configuration such as a weather location, ticker watchlist, preferred sports
league, polling interval, or service endpoint. Presentation choices still belong
to theme plugins.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable lowercase setting id. Pattern: `^[a-z0-9][a-z0-9_-]*$`. |
| `title` | string | yes | Human-readable label shown in the settings UI. |
| `type` | string | yes | `string`, `integer`, `number`, `boolean`, `choice`, or `secret`. |
| `defaultValue` | any | yes | Default value used when the user has not saved an override. |
| `choices` | array | only for `choice` | Ordered values the host cycles through in the panel UI. |
| `minimum` | number | no | Lower bound for numeric editors. |
| `maximum` | number | no | Upper bound for numeric editors. |
| `environment` | string | no | Environment variable populated before launching process-style transports. |
| `help` | string | no | Short implementation note for designers and developers. |

The first native settings UI cycles through declared choices and bounded
numeric values. Process-style transports also receive every setting as
`QUAKEKIT_SETTING_<SETTING_ID>`, uppercased with punctuation converted to
underscores. If `environment` is present, the same value is also exported under
that exact variable name.

Example:

```json
"settings": [
  {
    "id": "location",
    "title": "Location",
    "type": "choice",
    "defaultValue": "Charlotte, NC",
    "choices": ["Charlotte, NC", "Raleigh, NC"],
    "environment": "QUAKEKIT_WEATHER_LOCATION"
  }
]
```

## Actions

Actions are invokable commands.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable action id, usually namespaced such as `weather.refresh`. |
| `title` | string | yes | Human-readable command title. |
| `argumentSchema` | array | no | Ordered field definitions for arguments. |

## Data Streams

Data streams publish values from plugins to the host, views, or other plugins.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable stream id, usually namespaced such as `system.metrics`. |
| `title` | string | yes | Human-readable stream title. |
| `valueSchema` | array | no | Ordered field definitions for values produced by the stream. |

## Schema Fields

Action arguments and stream values share the same field shape.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable field id. |
| `title` | string | yes | Human-readable field title. |
| `type` | string | yes | `string`, `integer`, `number`, `boolean`, `url`, or `secret`. |
| `required` | boolean | no | Whether callers must supply the field. Defaults to `false`. |
| `defaultValue` | any | no | Default value used by the host or plugin. |

## Views

Views are the bridge between functional plugins and the panel shell. A plugin can
offer full applet pages, compact widgets, a view that supports both modes, or a
special main-menu widget used to render the Home page.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable view id. |
| `title` | string | yes | Human-readable view title. |
| `type` | string | no | `native`, `webCanvas`, `webDocument`, `text`, or `dataDriven`. |
| `presentation` | string | no | `page`, `widget`, `pageAndWidget`, or `mainMenu`. |
| `layout` | string | no | Page layout hint: `grid`, `fullScreen`, `halfLeading`, `halfTrailing`, `halfAndGrid`, `twoHalves`, `thirds`, or `quarters`. |
| `entryPath` | string | no | Local asset entrypoint such as `index.html`. |
| `dataStreamID` | string | no | Data stream backing the view. |
| `columnSpan` | integer | no | Widget grid width hint. |
| `rowSpan` | integer | no | Widget grid height hint. |
| `preferredWidth` | integer | no | Preferred rendered width in points. |
| `preferredHeight` | integer | no | Preferred rendered height in points. |
| `menuItems` | array | no | Declarative menu entries for `mainMenu` views. |

The host decides final layout. Plugins provide hints, not absolute control of
the display. Widget views still use `columnSpan` and `rowSpan`; page views may
use `layout` to request a non-grid shell such as split-screen, thirds, or quarters.

## Main Menu Widgets

The Home page is a special widget slot rather than a hard-coded screen. Users can
select a main-menu widget from Settings, and theme/plugin authors can provide
alternate launchers without touching the HID, windowing, or runtime layers.

A main-menu view uses `presentation: "mainMenu"`. It may provide `menuItems[]`;
if it does not, the host uses the built-in classic launcher as a fallback.

```json
{
  "id": "classic",
  "title": "Classic Launcher",
  "type": "dataDriven",
  "presentation": "mainMenu",
  "layout": "halfAndGrid",
  "menuItems": [
    { "id": "widgets", "title": "Widgets", "action": "page", "target": "widgets", "order": 10 },
    { "id": "weather", "title": "Weather", "action": "pluginView", "target": "weather:weather.canvas", "order": 20 },
    { "id": "carousel", "title": "Carousel", "action": "carousel", "target": "settings", "order": 30 }
  ]
}
```

Menu item fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable item id. |
| `title` | string | yes | Primary tile label. |
| `subtitle` | string | no | Secondary tile label. |
| `icon` | string | no | Future icon token. Current host stores but does not render it. |
| `action` | string | yes | `page`, `pluginView`, `pluginAction`, `status`, `carousel`, or `settings`. |
| `target` | string | no | Route target for the action. |
| `order` | integer | no | Sort order within the menu widget. |

Supported route targets:

| Action | Target Examples | Effect |
| --- | --- | --- |
| `page` | `home`, `widgets`, `apps`, `themes`, `settings`, `runtime`, `pluginAPIs` | Opens a host page. |
| `pluginView` | `system_monitor:system.overview` | Opens a plugin view as a transient applet. |
| `pluginAction` | `weather:weather.refresh` | Invokes a plugin action. |
| `carousel` | `settings`, `toggle`, `duration` | Opens carousel settings or changes carousel state. |
| `settings` | `global`, `plugin:weather` | Opens host settings page or plugin settings tile page. |
| `status` | any string | Shows a safe status message. |

## Theme And Hardware Boundaries

Functional plugins may publish data, actions, and semantic status. They should
not define colors, typography, component chrome, or raw HID output.

For the DK-QUAKE knob LED ring, plugins should request semantic runtime states
such as `focus`, `success`, `warning`, `danger`, or `progress`, ideally with a
priority and TTL. The runtime arbitrates competing requests and maps the winning
semantic state through the active theme's `hardware.knobRing` definition.

Trusted device-provider plugins may eventually receive lower-level hardware
access, but that should be an explicit capability boundary, not the default
plugin behavior.

## Validation

Validate a manifest with:

```bash
swift run quake-probe --validate-plugin Examples/Plugins/echo-plugin.json
```

Validate bundled examples with:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```

Install a packaged plugin:

```bash
swift run quake-probe --install-package ./MyWeather.quakekitplugin
swift run quake-probe --install-package ./MyWeather.quakekitplugin.tar.gz
```

Run a local executable action with:

```bash
swift run quake-probe --run-plugin-action Examples/Plugins/system-monitor.quakekitplugin/manifest.json system.refresh
```

The first runtime host supports packaged `shell`, `php`, and `stdioJSONRPC`
commands with a synchronous JSON request/response envelope. Web applet rendering,
long-lived stream subscriptions, and permission prompts are still active
implementation areas.
