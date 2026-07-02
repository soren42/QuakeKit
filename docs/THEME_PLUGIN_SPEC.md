# Theme Plugin Specification

QuakeKit separates plugin responsibilities into two families:

- **Theme plugins** define presentation: colors, typography, metrics, component
  styles, assets, and user-configurable visual options.
- **Functional plugins** define behavior: actions, data streams, applet pages,
  widgets, process execution, and external integrations.

This document defines the QuakeKit theme plugin manifest. The normative machine
schema is [`schemas/theme-plugin.schema.json`](../schemas/theme-plugin.schema.json).

## Package Layout

A theme package is a directory ending in `.quakekittheme`.

```text
Examples/Themes/focus-dark.quakekittheme/
  theme.json
  assets/
```

Only `theme.json` is required. Asset files are optional and must be referenced
from the `assets` array.

## Manifest Fields

### Root

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `$schema` | string | no | JSON Schema URL or relative path for editor validation. |
| `id` | string | yes | Stable lowercase id. Pattern: `^[a-z0-9][a-z0-9_-]*$`. |
| `name` | string | yes | Human-readable theme name. |
| `version` | string | yes | Theme version. SemVer is recommended. |
| `apiVersion` | string | yes | QuakeKit theme API version. Current value: `0.1`. |
| `kind` | string | yes | Must be `theme`. |
| `author` | string | no | Author or organization. |
| `description` | string | no | Short explanation of intended visual use. |
| `palette` | object | yes | Color token and semantic color definitions. |
| `typography` | object | no | Font names and type scale. |
| `metrics` | object | no | Shared dimensions such as radius, spacing, density. |
| `components` | object | no | Standard component style tokens. |
| `assets` | array | no | Images, fonts, CSS, scripts, or sounds bundled with the theme. |
| `options` | array | no | User-configurable visual controls exposed by the host UI. |

## Palette

`palette.mode` must be one of:

- `dark`
- `light`
- `adaptive`

`palette.colors` is a dictionary of named color tokens. Every token has:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `value` | string | yes | Hex color in `#RRGGBB` or `#RRGGBBAA` format. |
| `role` | string | no | Human explanation of how the token should be used. |
| `configurable` | boolean | no | Whether the host may offer this token as a user color setting. |

`palette.semanticColors` maps required host roles to palette token names or
literal hex colors:

- `background`
- `surface`
- `surfaceRaised`
- `border`
- `textPrimary`
- `textSecondary`
- `accent`
- `success`
- `warning`
- `danger`

Theme authors should define semantic colors even when component styles are also
present. Semantic colors are the fallback contract used by native controls,
widgets, and web bridges.

## Typography

`typography` is optional.

| Field | Type | Description |
| --- | --- | --- |
| `displayFont` | string | Display/title font family. |
| `bodyFont` | string | General UI font family. |
| `monoFont` | string | Monospaced font family. |
| `scale` | object | Numeric point sizes keyed by role, such as `caption`, `body`, `title`, `value`. |

If a requested font is unavailable, the host should fall back to the nearest
system font.

## Metrics

`metrics` is optional.

| Field | Type | Description |
| --- | --- | --- |
| `cornerRadius` | number | Shared corner radius in points. |
| `borderWidth` | number | Shared border width in points. |
| `spacing` | number | Default spacing unit in points. |
| `density` | string | `compact`, `standard`, or `comfortable`. |

## Components

Component styles are optional and may reference semantic colors, palette tokens,
or literal hex colors.

Supported component keys:

- `tile`
- `tab`
- `statusRow`
- `gauge`
- `chart`

Each component may define:

- `background`
- `foreground`
- `border`
- `accent`
- `selectedBackground`
- `selectedBorder`

The host should apply component values first, then fall back to semantic colors.

## Assets

Assets allow themes to bundle design artifacts such as backgrounds or fonts.

| Field | Type | Required | Values |
| --- | --- | --- | --- |
| `id` | string | yes | Stable asset id. |
| `kind` | string | yes | `image`, `font`, `sound`, `css`, or `script`. |
| `path` | string | yes | Path relative to the theme package root. |
| `scale` | number | no | Asset scale multiplier, usually `1`, `2`, or `3`. |

Themes may include CSS or scripts for web applets, but native host components
must not execute theme scripts.

## Options

Options are the host-facing customization controls. Keep them small and visual.
For now, QuakeKit should prefer color edits, density selection, and simple
numeric tuning.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Stable option id. |
| `title` | string | yes | Label shown in settings UI. |
| `type` | string | yes | `color`, `number`, `boolean`, or `choice`. |
| `target` | string | yes | Dot path into the manifest, such as `palette.colors.accent.value`. |
| `defaultValue` | any | yes | Default option value. |
| `choices` | array | only for `choice` | Allowed values for choice controls. |
| `minimum` | number | no | Minimum numeric value. |
| `maximum` | number | no | Maximum numeric value. |

The first host UI should expose:

- color picker for `color`
- stepper or slider for `number`
- toggle for `boolean`
- segmented control or menu for `choice`

The current panel shell exposes a first-pass `Themes` page. It can select
installed themes and cycle an accent override. This is intentionally smaller
than the final settings editor; it exists to prove package discovery, theme
application, and on-device theme switching.

The current native shell persists the active theme and option overrides to the
user's Application Support directory. The implemented option targets are:

- `palette.colors.accent.value`
- `palette.colors.success.value`
- `palette.colors.warning.value`
- `palette.colors.danger.value`
- `metrics.cornerRadius`
- `metrics.spacing`
- `metrics.density`

Other valid targets may be stored by the host but will not necessarily affect
the current native shell until the renderer supports them.

## Functional Plugin Parity

Functional plugins will receive a congruent JSON Schema for their manifests.
The existing functional manifest already covers entrypoints, capabilities,
permissions, actions, data streams, and views. The next schema pass should make
that contract as explicit as this theme spec.
