# Security and distribution

This is a local release candidate with a local ad hoc signature. It has not been notarized or signed using an Apple distribution certificate. Build from source you have reviewed and use the build script’s signature verification as a bundle integrity check; an ad hoc signature does not identify a trusted publisher.

The native runtime depends on Apple AppKit, Foundation, Core Audio, AudioToolbox, and AudioUnit frameworks plus the in-tree DSP and ring buffer. It has no package-manager runtime dependencies, network update mechanism, or automatic startup. Tuning starts manually. The app does not change hardware volume or the default output device.

The engine bounds its stereo buffer and validates supported layouts. Tone boosts reserve headroom and output samples are clamped. Automated sanitizer and lifecycle fixtures cover a range of source-level errors. They do not prove realtime guarantees, all input behavior, live capture permission handling, or physical recovery. See [known limits](KNOWN_LIMITS.md).

## Reporting a problem

Use GitHub [private vulnerability reporting](https://github.com/fcw1987/UltraFineTune/security/advisories/new) for sensitive security reports. Do not publish audio, personal device identifiers, credentials, or exploit details in a public issue.

For a non-sensitive bug, provide the source revision, macOS/toolchain version, output model and connection, sample rate, exact reproduction steps, observed status, and expected result. Review diagnostic files for local paths and identifiers before sharing. No personal contact details are included in this project.

## Release checklist

The RC2 prerelease is available with an ad hoc signature and pending live acceptance disclosed. Before declaring a stable release, complete live Mac acceptance and decide on Developer ID signing and notarization. Update validation claims to match the exact released source. Public source availability does not establish live playback acceptance.
