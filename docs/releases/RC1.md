# QuakeKit 1.0.0 RC1

## Release Candidate Scope

- Native RC2-inspired menu-template surface with Status Rail as the default,
  plus Radial Orbit and Ambient Marquee.
- Menu-specific persistent settings in the macOS Settings window.
- Rich Music and AI Command Center applet surfaces.
- Consolidated Music and AI example-package inventory; superseded package IDs
  are kept as references but are not loaded by the host.
- Local unsigned `.app` bundle version `1.0.0`, channel `RC1`.

## Before Community Distribution

1. Run `./scripts/validate-release.sh` with Xcode selected.
2. Complete the independent code review and product-feedback runs in
   `docs/reviews/RC1_EXTERNAL_REVIEW.md`.
3. Perform physical DK panel verification for wake, keepalive, touch, knob,
   pointer guard, display ownership, and knob ring.
4. Sign and notarize a distribution build before presenting RC1 as an installer.

## Known Boundaries

- External integrations remain offline-safe unless explicitly configured.
- LLM pages use official API or local-tool boundaries; consumer web UI
  automation is not supported.
- The app bundle is suitable for local launch testing, not signed distribution.
