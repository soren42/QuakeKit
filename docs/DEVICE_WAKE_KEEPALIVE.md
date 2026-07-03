# Device Wake and Keep-Alive

How the DK-Quake / ARIS-68 panel is woken from cold and kept awake, and the
one-byte framing mistake that made both fail for weeks. Findings verified
against DK-Suite 0.4.49 (`Contents/Resources/app/background.js`) and live
hardware (firmware 1.0.19).

## Symptom

- Cold plug (DK-Suite never launched): panel backlight and knob LED ring stay
  dark, even while QuakeKit renders to the display and reads knob/touch input.
- Launch DK-Suite, quit it, launch a QuakeKit host: panel stays lit for
  ~30 seconds, then goes dark.

## Root cause: report-ID byte inside the payload

The control collection (VID `0x4158`, PID `0x514B`, usagePage `0xFF60`,
usage `0x61`) uses **unnumbered reports** — report ID 0. On this kind of
device the report ID is passed to `IOHIDDeviceSetReport` out-of-band and must
**not** appear in the payload.

DK-Suite writes through node-hid/hidapi, whose convention is a leading `0x00`
report-ID byte in the buffer that hidapi **strips** before calling
`IOHIDDeviceSetReport`. So the device receives frames that begin with the
`0xA3` header.

QuakeKit's original write path copied the node-hid buffer convention (leading
`0x00`) but then passed the whole buffer as the payload. The firmware received
`00 A3 ...` — every byte shifted by one — failed its header check, and
silently dropped the frame. Crucially, `IOHIDDeviceSetReport` still returned
`kIOReturnSuccess`, so every diagnostic said writes were succeeding while the
device ignored all of them: screen-on never landed, and neither did a single
keep-alive ping.

The fix (`QuakeDevice.sendControlFrame` and the default `sendControlReport`)
sends the frame bytes as the payload with report ID 0 out-of-band, exactly as
hidapi does.

## Firmware sleep model

Observed behavior plus DK-Suite's constants give a consistent model:

- The firmware treats "no valid host frame for ~30 s" as *host gone* and
  blanks the panel and knob ring (the USB display can stay enumerated while
  dark).
- Any valid vendor frame wakes it again — there is no special wake command.
- DK-Suite feeds it a ping every 15 s (`deviceKeepAliveGap: 15e3`); the ~30 s
  dark-out is two missed pings. Its `screenCheckTimeout` is likewise `3e4`.

That explains both symptoms: a cold device never saw a valid frame from
QuakeKit, and a DK-Suite-woken device died ~30 s after DK-Suite's last ping
because QuakeKit's pings were all malformed.

## Vendor protocol notes (from DK-Suite 0.4.49)

Short-command frame, matching `QuakeProtocol.shortCommand`:

```
0xA3, len(data)+1, opCode, ...data, sum(opCode + data) % 255
```

The checksum is genuinely `% 255` (not `& 0xFF`); the firmware validates it on
receive and QuakeKit's decoder applies the same rule.

| Frame | Meaning |
| --- | --- |
| `l(163,[239],2)` → `A3 02 02 EF F1` | Keep-alive ping, sent immediately on connect and every 15 s. Device answers `0x55 0xEF <counter>`. |
| `l(163,[4,1],1)` | Screen on — *attaches* the USB display. |
| `l(163,[4,0],1)` | Screen off — *detaches* the USB display. DK-Suite's "screen reboot" sends `[4,0]`, waits for the macOS display-removed event, then sends `[4,1]`. |
| `l(163,[46],2)` | Query firmware. Reply `0x55 0x2E name maj min patch`. |
| `l(163,[3],2)` / `l(163,[5],2)` | Query mic / luminance. |
| `l(163,[2,tone],1)` | Buzzer tone. |
| `l(163,[47,3],1)` | **Enter DFU/download mode. Never send this** — it is DK-Suite's `enterDownloadMode`, not a wake or status command. |

Unsolicited `0x55 0x00 0x90` frames are the firmware's "state sync / busy"
notification; DK-Suite uses them for settings bookkeeping. They are safe to
ignore for wake purposes.

Device matching (`SUPPORTED_VPID`): control `0x4158:0x514B` usage `0x61`
usagePage `0xFF60`; touch `0x0712:0x0010` usage `0x71` usagePage `0xFF73`.
DK-Suite opens HID devices non-exclusively on macOS (`nonExclusive: true`).

## What QuakeKit does now

On `QuakeDevice.activate()`:

1. Send screen-on (`A3 03 01 04 01 06`) once, with a single retry pulse 1 s
   later for devices still enumerating.
2. Query firmware (also serves as a wake frame and confirms two-way traffic).
3. Send a ping immediately, then every 15 s (`QuakeDevice.keepAliveInterval`,
   mirroring DK-Suite).

A healthy session shows a `state firmware ...` event at startup and a
`state pong` event after every ping. If pongs stop, the panel will go dark
within ~30 s — treat missing pongs as the alarm, not the write return codes.

## Verification

With DK-Suite closed and the device cold/dark:

```bash
swift run quake-probe --wake --listen
```

Expected: panel and knob ring light up, `state firmware name=3 version=…`
appears, and `state pong` events continue indefinitely (well past the 30 s
watchdog window). Protocol byte vectors are pinned by
`Tests/QuakeKitTests/QuakeProtocolFramingTests.swift` (`swift test`).
