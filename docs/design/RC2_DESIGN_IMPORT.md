# RC2 Design Import

The canonical Claude Design RC2 package was ingested locally from:

`UI/QuakeKit Design System RC2.zip`

The source bundle is intentionally kept out of the distributable app bundle:
it contains local Apple font files which the upstream handoff explicitly says
must not be redistributed. Its implementation contract has been ported to the
native host instead of shipping its browser mockups.

## RC1 Mapping

| RC2 contract | RC1 native implementation |
| --- | --- |
| `templates/status-rail/` | `PanelMenuTemplate.statusRail` (default menu) |
| `templates/radial-orbit/` | `PanelMenuTemplate.radialOrbit` |
| `templates/ambient-marquee/` | `PanelMenuTemplate.ambientMarquee` |
| shared chrome ownership | `MenuChromeView` owns visible panel chrome; `PanelView` owns lifecycle, data, and navigation intent |
| shared generic applet state | `DataBoardView` data renderer with Music and AI Command Center rich variants |
| theme token/knob semantics | existing native `ThemeManifest` / `PanelTheme` and `KnobRingCoordinator` contract |

The browser template code remains an authoritative visual and interaction
reference for follow-up iteration. RC1 does not embed a web runtime in the HID
host: it preserves the four-layer ownership boundary using AppKit views.
