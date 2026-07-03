# QuakeKit

![Static Badge](https://img.shields.io/badge/-macOS-grey?style=flat&logo=apple)  ![Static Badge](https://img.shields.io/badge/version-6.3.2-orange?style=flat&logo=Swift)  ![Static Badge](https://img.shields.io/badge/status-ALPHA_Development_and_Test_ONLY-red?style=flat)


Swift-native platform work for the DK-Quake / ARIS-68 touch display and control center.

This repository is being built as a modular device/runtime platform first. The DK-Quake macOS host is the first implementation, not the only long-term target.

## Status

Early hardware/platform bring-up. This is not ready as an end-user replacement for DK-Suite yet.

Confirmed:

- HID control input works.
- HID touch input works.
- Knob-ring output works.
- The plugin manifest/API skeleton builds and validates sample manifests.
- Local shell/PHP/stdio-style plugin actions can be invoked through the runtime host.
- The AppKit panel UI renders on the DK physical display.
- The native shell supports Home, Widgets, Apps, Themes, and Runtime pages.
- Grid pages paginate overflow with knob boundary navigation and touch arrow pads.

## First Tangible Target

Build:

```bash
swift build
```

Enumerate supported DK-Quake HID interfaces:

```bash
swift run quake-probe
```

Dump all related HID collections, including the standard touch descriptor macOS exposes:

```bash
.build/debug/quake-probe --all-hid
```

Run protocol checks without hardware:

```bash
swift run quake-probe --self-test
swift run quake-test
```

Test confirmed HID output to the knob ring:

```bash
.build/debug/quake-probe --led-on
.build/debug/quake-probe --led-off
```

Validate a sample plugin manifest:

```bash
swift run quake-probe --validate-plugin Examples/Plugins/echo-plugin.json
```

Run a sample plugin action without hardware:

```bash
swift run quake-probe --run-plugin-action Examples/Plugins/system-monitor.quakekitplugin/manifest.json system.refresh
swift run quake-probe --run-plugin-action Examples/Plugins/weather.quakekitplugin/manifest.json weather.refresh
swift run quake-probe --run-plugin-action Examples/Plugins/markets.quakekitplugin/manifest.json markets.refresh
swift run quake-probe --run-plugin-action Examples/Plugins/sports.quakekitplugin/manifest.json sports.refresh
```

Validate all bundled example manifests:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```

Validate all bundled theme manifests:

```bash
for f in Examples/Themes/*.quakekittheme/theme.json; do
  swift run quake-probe --validate-theme "$f"
done
```

With hardware connected, run the safe live probe:

```bash
swift run quake-probe --listen --wake
```

Launch the first native panel host:

```bash
.build/debug/quake-panel
```

Launch modes:

```bash
# Normal hardware mode: display plus HID touch, knob, control, and heartbeat events.
.build/debug/quake-panel

# Display-only diagnostic mode: renders UI but intentionally disables all HID input.
.build/debug/quake-panel --no-hid

# High-contrast display diagnostic, also display-only.
.build/debug/quake-panel --display-test --no-hid
```

The live probe only sends safe wake, keep-alive, firmware, mic, and brightness query commands. It does not expose or send DFU.

## Current Milestone

- `QuakeHID`: IOKit HID transport plus DK-Quake protocol frames.
- `QuakeRuntime`: device events, page/tile/action models, runtime event envelope, plugin data snapshots, and knob-ring arbitration.
- `PluginExecutionHost`: local plugin action execution for packaged shell, PHP, and stdio-style adapters.
- `QuakePluginAPI`: Codable functional plugin and theme manifests, permissions, capabilities, package loading, and host/plugin message types.
- `quake-probe`: CLI smoke target for enumeration and hardware input decoding.
- `quake-test`: portable regression target for protocol, plugin, and runtime checks.
- `quake-panel`: first AppKit panel host with native shell pages, theme selection, and HID knob/touch events.

Bundled plugin adapters are intentionally keyless and tolerant of offline use.
Weather uses Open-Meteo with `QUAKEKIT_WEATHER_LAT`,
`QUAKEKIT_WEATHER_LON`, and `QUAKEKIT_WEATHER_LABEL` overrides. Markets uses
Yahoo Finance chart data with `QUAKEKIT_MARKET_SYMBOLS`. Sports uses ESPN's
public scoreboard endpoint with `QUAKEKIT_SPORTS_LEAGUE`.

## Current Hardware Notes

- macOS reports the DK touch interface as standard digitizer HID: usagePage `0x000D`, usage `0x0004`.
- The probe confirms control input, touch input, and knob-ring output.
- The physical DK display renders the native panel when the host uses a full-frame borderless window on the DK screen.
- The host can visually own the DK screen with a borderless full-frame window, even though macOS still exposes it as an external display.
- `quake-panel --display-test --no-hid` runs a high-contrast display diagnostic.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the platform plan.
See [docs/PLUGIN_ARCHITECTURE.md](docs/PLUGIN_ARCHITECTURE.md) for the plugin model.
See [docs/FUNCTIONAL_PLUGIN_SPEC.md](docs/FUNCTIONAL_PLUGIN_SPEC.md) for the functional plugin contract.
See [docs/THEME_PLUGIN_SPEC.md](docs/THEME_PLUGIN_SPEC.md) for the theme plugin contract.

## License

QuakeKit original project code is licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Important caveat: the DK-Quake / ARIS-68 HID protocol behavior is based on community reverse-engineering work that carries a non-commercial protocol caveat. Treat this project as open-source, non-commercial unless that protocol licensing boundary is clarified.
