# Plugin Language Examples

QuakeKit functional plugins describe their runtime through the `entry`
manifest object. The schema supports native Swift, hosted HTML, PHP processes,
shell scripts, and generic stdio JSON-RPC adapters. This guide maps the common
language choices to the bundled example artifacts.

## Swift

Use `nativeSwift` only for trusted code that ships with, or is explicitly loaded
by, the host. Native Swift plugins should expose semantic actions, data streams,
and views through the manifest, while implementation and signing boundaries stay
host-controlled.

Manifest-only example:

```json
{
  "entry": {
    "transport": "nativeSwift",
    "command": "QuakeKitExamples.NativeStatusPlugin",
    "arguments": []
  }
}
```

See
`Examples/Plugins/native-status.quakekitplugin/manifest.json` for a complete
documentation sample. It intentionally does not include Swift source or modify
runtime targets.

## HTML

Use `webView` for a plugin whose primary surface is an HTML document, and use a
view `entryPath` for HTML-backed pages or widgets that are paired with another
process transport.

Bundled examples:

- `Examples/Plugins/weather.quakekitplugin/index.html` is a web canvas asset
  backed by the shell weather provider.
- `Examples/Plugins/ai-agent.quakekitplugin/index.html` is a web document
  surface for a stdio adapter.

Manifest shape:

```json
{
  "entry": {
    "transport": "webView",
    "url": "index.html"
  },
  "views": [
    {
      "id": "example.page",
      "title": "Example Page",
      "type": "webDocument",
      "presentation": "page",
      "entryPath": "index.html"
    }
  ]
}
```

## PHP

Use `php` for process-style data providers or actions that can read stdin,
inspect environment-backed settings, and emit one JSON payload on stdout.

Bundled example:

- `Examples/Plugins/markets.quakekitplugin/manifest.json`
- `Examples/Plugins/markets.quakekitplugin/markets.php`

Manifest shape:

```json
{
  "entry": {
    "transport": "php",
    "command": "markets.php",
    "arguments": []
  }
}
```

## Bash And POSIX Shell

Use `shell` for small local adapters and diagnostics. Prefer `/bin/sh`
compatible scripts for examples unless a plugin explicitly requires Bash.
Scripts should consume stdin, honor `QUAKEKIT_SETTING_*` environment values,
and print a JSON object to stdout.

Bundled examples:

- `Examples/Plugins/system-monitor.quakekitplugin/system-monitor.sh`
- `Examples/Plugins/weather.quakekitplugin/weather.sh`
- `Examples/Plugins/discord-companion.quakekitplugin/discord-companion.sh`
- `Examples/Plugins/obs-controls.quakekitplugin/obs-controls.sh`
- `Examples/Plugins/home-assistant.quakekitplugin/home-assistant.sh`
- `Examples/Plugins/octoprint.quakekitplugin/octoprint.sh`
- `Examples/Plugins/ubiquiti-network.quakekitplugin/ubiquiti-network.sh`
- `Examples/Plugins/hotkey-grid.quakekitplugin/hotkey-grid.sh`
- `Examples/Plugins/music-now-playing.quakekitplugin/music-now-playing.sh`

Manifest shape:

```json
{
  "entry": {
    "transport": "shell",
    "command": "system-monitor.sh",
    "arguments": []
  }
}
```

## Integration Stub Categories

Integration stubs stay manifest-first and choose the smallest transport that
matches the service boundary:

- Discord: `stdioJSONRPC` or `shell` adapter for presence, webhook, and bot
  action experiments.
- OBS: `stdioJSONRPC` adapter for scene, source, and recording controls.
- Home Assistant: networked data provider for entity state boards and control
  actions.
- OctoPrint: networked data provider for printer status, job progress, and
  pause/resume actions.
- Ubiquiti: networked data provider for device, client, and site health rows.
- Hotkey Grid: local action provider for macro buttons and command palettes.
- Music companion: local or networked provider for Spotify, Apple Music, or
  other now-playing sources.
- App Context: frontmost app/window detection for routing companion panels and
  hotkey grids. Keep detection best-effort and provide manual/env fallbacks
  because macOS automation permissions vary by launch surface.
- Creative and terminal companions: Affinity Photo 2, Warp AI, Terminus,
  Terminus Beta, and general terminal workflows should publish context,
  key/action plans, and dry-run status before synthesizing input.
- AI Workbench companions: Claude, Claude Code, ChatGPT, Codex, Gemini, and
  Antigravity panels should surface project path, active agent count, token
  estimates, and remaining work limits through deterministic local settings or
  status files before any provider-specific bridge is added.
- Voice AI and Meeting Notes: microphone/speaker-capable harnesses that hand off
  to Wispr Flow, local `whisper`, Apple Speech, or official model APIs as the
  user configures credentials and capture policy.
- LLM provider harnesses: ChatGPT, Claude, Grok, Gemini, DeepSeek, and Cursor
  companion stubs. These use official API/local companion boundaries and avoid
  consumer UI scraping or browser automation.

For service-shaped payloads, prefer `dataDriven` views backed by a data stream.
The host can render common row, device, scoreboard, and ticker payloads through
the generic native data board renderer without requiring every stub to ship a
custom web view.

## Validation

Validate language examples with the same manifest command used for packaged
plugins:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```
