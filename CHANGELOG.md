# Release notes

## 1.0.1 — build 4 (candidate; not published)

- Explicit Developer ID signing with hardened runtime and a secure timestamp using an existing authorized identity.
- Shared Xcode Release archive scheme for the existing native app and Organizer distribution workflow.
- Version metadata updated consistently; bundle identifier, preference keys, DSP, and controls remain unchanged.
- Notarization, ticket stapling, Gatekeeper acceptance, and public release remain pending.

## 1.0.0 — build 3

- Stable release with the existing system audio EQ, eight presets, saved preset, comparison, and output trim.
- Stable app metadata and clear product, compatibility, installation, privacy, and support information.
- Apple silicon (arm64), macOS 14.2+. Ad hoc signed; not Developer ID signed or notarized.
- New versioned app ZIP and checksum; existing RC2 artifacts and tag are preserved.
- Bundle identifier, preference keys, DSP, and controls remain unchanged.

## Historical 1.0.0 RC2 — build 2 (superseded by 1.0.0)

- Native menu bar controls, eight listening presets, one saved preset, tone comparison, and Flat EQ.
- Local stereo processing through Core Audio process taps and a separate output Audio Unit.
- Manual start on launch; route changes and sleep stop tuning.
- Open-source publication standardizes UltraFineTune branding, adds the MIT license, support/privacy pages, native build validation, and a Pages website.
- Bundle identifier and preference keys remain stable through the naming change.

The downloadable RC2 prerelease includes an arm64 app, MIT license, installation guide, and ZIP checksum. It is ad hoc signed, not Developer ID signed or notarized. Live audio and recovery acceptance remain pending.
