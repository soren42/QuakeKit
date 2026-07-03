# Functional Plugin Examples

These examples are manifest-first fixtures for QuakeKit functional plugins. The
host validates each `manifest.json` against
`../../schemas/functional-plugin.schema.json` before loading the package.

| Package | Language | Transport | Purpose |
| --- | --- | --- | --- |
| `system-monitor.quakekitplugin` | POSIX shell | `shell` | Local system metrics action and data stream. |
| `weather.quakekitplugin` | POSIX shell plus HTML | `shell` | Weather data provider with an HTML canvas view. |
| `markets.quakekitplugin` | PHP | `php` | Market ticker provider with environment-backed settings. |
| `ai-agent.quakekitplugin` | HTML plus stdio adapter | `stdioJSONRPC` | Web document surface for an agent adapter. |
| `sports.quakekitplugin` | Executable stdio adapter | `stdioJSONRPC` | Scoreboard data provider. |
| `native-status.quakekitplugin` | Swift | `nativeSwift` | Manifest-only native Swift documentation sample. |
| `echo-plugin.json` | Executable stdio adapter | `stdioJSONRPC` | Loose manifest fixture for early validation. |

Process examples should read stdin to completion, use declared settings from
environment variables, and print one JSON object to stdout. HTML assets should
stay package-local and reference their manifest view through `entryPath`.

The native Swift example is intentionally manifest-only. It documents the
`nativeSwift` transport without adding runtime Swift source, package targets, or
dynamic loading behavior.

Validate all bundled plugin manifests from the repository root:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```
