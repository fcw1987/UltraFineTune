# Security and distribution

Version 1.0.0 is a stable release with a local ad hoc signature. It has not been notarized or signed using an Apple distribution certificate. Build from source you have reviewed and use the build script’s signature verification as a bundle integrity check; an ad hoc signature does not identify a trusted publisher.

The native runtime depends on Apple AppKit, Foundation, Core Audio, AudioToolbox, and AudioUnit frameworks plus the in-tree DSP and ring buffer. It has no package-manager runtime dependencies, network update mechanism, or automatic startup. Tuning starts manually. The app does not change hardware volume or the default output device.

The engine bounds its stereo buffer and validates supported layouts. Tone boosts reserve headroom and output samples are clamped. Automated sanitizer and lifecycle fixtures cover a range of source-level errors. They do not prove realtime guarantees, all input behavior, live capture permission handling, or physical recovery. See [known limits](KNOWN_LIMITS.md).

## Reporting a problem

Use GitHub [private vulnerability reporting](https://github.com/fcw1987/UltraFineTune/security/advisories/new) for sensitive security reports. Do not publish audio, personal device identifiers, credentials, or exploit details in a public issue.

For a non-sensitive bug, provide the source revision, macOS/toolchain version, output model and connection, sample rate, exact reproduction steps, observed status, and expected result. Review diagnostic files for local paths and identifiers before sharing. No personal contact details are included in this project.

## Distribution status

Stable 1.0.0 (build 3) is available for Apple silicon and macOS 14.2+. Developer ID signing and notarization are separate future distribution work; the current release has neither. Automated validation and off-state controls are checked against the released source. Live permission, listening, latency, sustained playback and hardware recovery have the boundaries documented in [known limits](KNOWN_LIMITS.md); stable designation does not imply those measurements have been performed.
