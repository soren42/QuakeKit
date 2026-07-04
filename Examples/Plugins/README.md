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
| `app-context.quakekitplugin` | POSIX shell | `shell` | Frontmost app/window context detector and companion profile router. |
| `hotkey-grid.quakekitplugin` | POSIX shell | `shell` | Context-aware macro and status grid fixture. |
| `music-now-playing.quakekitplugin` | POSIX shell | `shell` | Spotify/Apple Music/local now-playing companion fixture with optional local file input. |
| `spotify-controls.quakekitplugin` | POSIX shell | `shell` | Spotify app/API metadata and playback-control companion fixture. |
| `youtube-media-companion.quakekitplugin` | POSIX shell | `shell` | YouTube media context, metadata, and playback-control plan fixture. |
| `youtube-companion.quakekitplugin` | POSIX shell | `shell` | Active browser YouTube tab companion and keyboard-control plan fixture. |
| `spotify-current-track.quakekitplugin` | POSIX shell | `shell` | Spotify current track metadata and playback-control plan fixture with optional local file input. |
| `affinity-photo-hotkeys.quakekitplugin` | POSIX shell | `shell` | Affinity Photo 2 persona-aware hotkey grid fixture. |
| `affinity-photo2.quakekitplugin` | POSIX shell | `shell` | Affinity Photo 2 frontmost document/persona companion fixture. |
| `terminal-companions.quakekitplugin` | POSIX shell | `shell` | Warp AI, Terminus, and Terminus Beta workspace/session companion fixture. |
| `terminal-companion.quakekitplugin` | POSIX shell | `shell` | Frontmost terminal app companion for Warp, Terminus, Terminal, and iTerm2. |
| `ai-agent-companions.quakekitplugin` | POSIX shell | `shell` | Claude, Claude Code, ChatGPT, Codex, Gemini, and Antigravity companion fixture. |
| `ai-workbench.quakekitplugin` | POSIX shell | `shell` | Project, agent count, token use, and work-limit status companion fixture. |
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

App-aware companion fixtures are offline-safe by default. YouTube, Spotify,
terminal, Affinity, and AI agent companions expose optional `QUAKEKIT_*_FILE`
or explicit `QUAKEKIT_*` inputs for deterministic local metadata while keeping
live provider calls, app automation, and input synthesis behind declared
permissions and dry-run settings.

Validate all bundled plugin manifests from the repository root:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```
