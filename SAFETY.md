# Safety Notes

QuakeKit talks directly to DK-Quake / ARIS-68 HID interfaces. Treat device output commands with care.

## Do Not Send DFU

The upstream protocol research identifies a firmware-download / DFU command. This project must not expose or send it.

Known dangerous frame:

```text
A3 03 01 2F 03 33
```

Do not add this to probe commands, UI controls, tests, examples, or plugin APIs.

## Safe Commands Currently Used

The current probe and panel use only these known-safe categories:

- screen wake
- keep-alive ping
- firmware query
- microphone state query
- luminance query
- touch input decoding
- knob input decoding
- knob-ring lighting on/off

## Hardware Testing

When reporting hardware behavior, include:

- Mac model
- macOS version
- DK display resolution and rotation from System Information or Display Settings
- `quake-probe --all-hid` output
- whether touch, knob, keep-alive, LED on/off, and panel rendering work

## Plugin Safety

The plugin API is intentionally permissioned. Third-party plugins should not get ambient access to:

- shell commands
- local files
- microphone input
- input synthesis
- network hosts
- secrets
- device output commands

The host should mediate and log grants.
