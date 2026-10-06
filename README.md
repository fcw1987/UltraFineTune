# UltraFine Tune

A native macOS menu bar app that applies bass, midrange, treble, and output trim to captured system playback, then sends the processed stereo audio to your selected output. Its initial target is an LG UltraFine used as the Mac’s default output.

**Local release candidate:** version 1.0.0, build 2 (Release candidate 2). RC2 passes a native arm64 build, signature verification, off-state menu/window checks, 16 EQ and seven ring groups, and all eight preset bounds/headroom cases. Live audio permission, listening quality, physical latency, installation, and recovery acceptance remain pending. The app uses a local ad hoc signature; it is not notarized or signed with an Apple distribution certificate. See [known limits](docs/KNOWN_LIMITS.md) before use.

## Quick start

You need macOS 14.2 or later and Xcode or Apple Command Line Tools with a macOS SDK supporting Core Audio process taps. No package manager or third-party runtime libraries are required.

```sh
# From the repository folder: build only, without opening or installing.
bash build.sh

# Optional: build and open the local app.
bash build.sh --run-local
```

1. Select your LG UltraFine in **System Settings → Sound → Output**. The app’s selected output must already be the Mac’s default output.
2. Open `dist/UltraFine Tune.app`, choose the output, and click **Start tuning**.
3. Approve macOS system audio capture permission if requested. Play familiar audio at a comfortable volume and begin with **Neutral**.
4. Make small tone changes. **Compare original tone** keeps trim and reserved headroom for comparison; **Stop tuning** returns to ordinary playback.

Tuning starts manually on every launch. Audio is processed locally in memory: no recordings, network transmission, microphone capture, or screen capture. Route changes and sleep stop tuning; confirm the current output and restart manually. These are implemented behaviors; live hardware acceptance is still required.

## Documentation

- [Build, install, update, and remove](docs/BUILD.md)
- [Controls, everyday use, and troubleshooting](docs/USAGE.md)
- [Privacy and stored settings](docs/PRIVACY.md)
- [Security, distribution, and reporting](docs/SECURITY.md)
- [Possible next steps](docs/ROADMAP.md)
- [Known limits and validation boundaries](docs/KNOWN_LIMITS.md)
- [Mac acceptance checklist](MAC_TEST_CHECKLIST.md)
- [Test reproduction and fixture limits](Tests/README.md)
- [Recorded RC evidence](VALIDATION.txt) and [release notes](RC_NOTES.md)

The [informational website](docs/index.html) uses only local static assets and works offline. Open `docs/index.html` in a browser. To publish with GitHub Pages after repository publication, choose **Deploy from a branch**, the desired branch, and **/docs** in the repository’s Pages settings. Publication is a separate action; this checkout does not publish anything.

## Implementation

| File | Responsibility |
| --- | --- |
| `Sources/main.m` | AppKit controls, preferences, menu bar lifecycle |
| `Sources/UFAudioEngine.m` | Core Audio process tap, private capture aggregate, output Audio Unit |
| `Sources/UFPresets.h` | Shared subjective preset definitions |
| `Sources/UFEQ.c` | Stereo filters, control smoothing, headroom, sample clamp and metering |
| `Sources/UFRing.c` | Bounded stereo buffering and small clock drift compensation |

The capture tap excludes the app’s own output. Capture and playback require matching nominal sample rates. Stop destroys the output unit, aggregate, and tap. The app does not change the default output or hardware volume. Automated fixtures exercise bookkeeping and DSP; they do not prove Apple’s live audio lifecycle or process-death recovery.

API and coefficient references: [Apple Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [audio capture usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription), [Apple AUHAL technical note](https://developer.apple.com/library/archive/technotes/tn2091/_index.html), and [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/).

## Project status

This project is independent of LG. The tone presets are listening starting points, not measured speaker calibration or an LG endorsement. A project license has not yet been selected; no license grant is claimed by this documentation. Decide on licensing before public distribution.
