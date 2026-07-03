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

## Validation

Validate language examples with the same manifest command used for packaged
plugins:

```bash
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f"
done
```
