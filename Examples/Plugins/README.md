# Functional Plugin Examples

These examples are manifest-first fixtures for QuakeKit functional plugins. The
host validates each `manifest.json` against
`../../schemas/functional-plugin.schema.json` before loading the package.

| Package | Language | Transport | Purpose |
| --- | --- | --- | --- |
| `system-monitor.quakekitplugin` | POSIX shell | `shell` | Local system metrics action and data stream. |
| `weather.quakekitplugin` | POSIX shell plus HTML | `shell` | Weather data provider with an HTML canvas view. |
| `markets.quakekitplugin` | PHP | `php` | Market ticker provider with environment-backed settings. |
| `obs-stream-controls.quakekitplugin` | POSIX shell | `shell` | OBS stream scene and control stubs. |
| `octoprint-printer.quakekitplugin` | POSIX shell | `shell` | OctoPrint printer status and control stubs. |
| `ai-agent.quakekitplugin` | HTML plus stdio adapter | `stdioJSONRPC` | Voice-capable agent surface with transcription and summary settings. |
| `meeting-notes.quakekitplugin` | POSIX shell | `shell` | Meeting recorder, transcription, summary, and export harness. |
| `chatgpt-harness.quakekitplugin` | POSIX shell | `shell` | ChatGPT/OpenAI API companion stub. |
| `claude-harness.quakekitplugin` | POSIX shell | `shell` | Claude/Anthropic API companion stub. |
| `grok-harness.quakekitplugin` | POSIX shell | `shell` | Grok/xAI API companion stub. |
| `cursor-harness.quakekitplugin` | POSIX shell | `shell` | Cursor local companion and workspace status stub. |
| `gemini-harness.quakekitplugin` | POSIX shell | `shell` | Gemini API companion stub. |
| `deepseek-harness.quakekitplugin` | POSIX shell | `shell` | DeepSeek API companion stub. |
| `sports.quakekitplugin` | Executable stdio adapter | `stdioJSONRPC` | Scoreboard data provider. |
| `discord-companion.quakekitplugin` | POSIX shell | `shell` | Discord presence, voice, webhook planning, and activity companion fixture. |
| `obs-controls.quakekitplugin` | POSIX shell | `shell` | OBS scene, stream, recording, and request-plan controls fixture. |
| `home-assistant.quakekitplugin` | POSIX shell | `shell` | Home Assistant entity dashboard stub. |
| `octoprint.quakekitplugin` | POSIX shell | `shell` | 3D printer status, temperature profile, and job controls fixture. |
| `ubiquiti-network.quakekitplugin` | POSIX shell | `shell` | UniFi network health dashboard stub. |
| `hotkey-grid.quakekitplugin` | POSIX shell | `shell` | Focus-aware macro and status grid stub. |
| `music-now-playing.quakekitplugin` | POSIX shell | `shell` | Spotify/Apple Music/local now-playing companion fixture with optional local file input. |
| `native-status.quakekitplugin` | Swift | `nativeSwift` | Manifest-only native Swift documentation sample. |
| `echo-plugin.json` | Executable stdio adapter | `stdioJSONRPC` | Loose manifest fixture for early validation. |

Process examples should read stdin to completion, use declared settings from
environment variables, and print one JSON object to stdout. HTML assets should
stay package-local and reference their manifest view through `entryPath`.

## Integration Stub Categories

The integration fixtures are intentionally deterministic until their credential
and service-specific bridges are implemented. They still declare realistic
settings, permissions, actions, data streams, and `dataDriven` views so the host
can load them, render them through the generic native data board, and expose
their settings from the tray configuration window. Several adapters honor
optional `QUAKEKIT_*` environment variables, and the music fixture can read a
local `title|artist|album|state|position|duration` file when
`QUAKEKIT_MUSIC_NOW_PLAYING_FILE` is set.

LLM and voice harnesses use official API, local CLI, local companion, or
user-configured endpoint boundaries. They should not scrape or automate vendor
consumer interfaces. The first pass supports Wispr Flow handoff, local
`whisper` CLI transcription of configured audio files, and declared host
permissions for future microphone/speaker capture.

The native Swift example is intentionally manifest-only. It documents the
`nativeSwift` transport without adding runtime Swift source, package targets, or
dynamic loading behavior.

Validate all bundled plugin manifests from the repository root:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```
