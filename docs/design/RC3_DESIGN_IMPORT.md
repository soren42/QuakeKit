# RC3 Design Import

The canonical Claude Design RC3 package was ingested locally from:

`UI/QuakeKit Design System RC3.zip`

As with RC2, the raw package is intentionally excluded from the product and
source distribution. It includes locally licensed Apple font files and browser
mockups that are reference material, not a runtime dependency.

## Native Mapping

| RC3 contract | Native implementation |
| --- | --- |
| macOS source-list Settings window | `QuakeSettingsWindowView` sidebar and single scrolling detail surface |
| System navigation | General, Themes, Widgets & Apps, Carousel |
| Package navigation | Plugins, Audio & Privacy, About |
| settings.json / theme-config.json bindings | Existing `QuakeSettingsConfiguration` and `ThemeUserConfiguration` stores |
| Package installation | Existing `NSOpenPanel` and `QuakePackageInstaller` entry points |
| Audio and privacy controls | `QuakeAudioService` permission, recording, speaker, and recording-folder actions |
| Standard tray dropdown | Compact template status item, dynamic panel/audio/menu/theme status, and native `NSMenu` actions |

## RC3 Decisions

- The AppKit implementation remains native. It does not embed the HTML mockup
  or distribute the supplied local fonts.
- The selected Settings section is restored through `UserDefaults`; functional
  preferences continue to persist only through the documented JSON stores.
- The tray menu reports live status at menu-open time. Active menu and active
  theme rows open the native Settings surface instead of creating a second
  configuration flow.
- The `Audio & Privacy` section is deliberately shell-owned. It shows the real
  macOS microphone state, starts/stops the existing local meeting clip, performs
  the existing speaker test, and opens the macOS privacy pane for denied access.

## Verification

`./scripts/validate-release.sh` passed after the RC3 import. The remaining
verification boundary is visual and physical: open the bundled app, inspect the
primary-display Settings window in light and dark macOS appearances, and verify
the menu-bar dropdown on the target system.
