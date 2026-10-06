# Known limits and validation

## Product scope

- Initial target: a stereo LG UltraFine selected as the Mac’s default output. Unsupported output layouts are rejected; this is not a multichannel equalizer.
- Requires macOS 14.2 or later and SDK support for Core Audio process taps.
- Capture and output must share a nominal sample rate.
- Presets are listening starting points. No model-specific acoustic measurement, calibration, or LG endorsement is claimed.
- Buffering adds latency. The displayed buffer target is not measured end-to-end device latency.
- Protected audio and apps with direct output routing may not be captured.
- Tone bypass retains trim and headroom. It does not restore the ordinary audio path; Stop tuning does.
- Sample clamping bounds digital output but cannot guarantee distortion-free processing for every input.
- Route/configuration changes and sleep require manual restart after the route is confirmed.
- One custom preset is stored. There is no preset library, network sync, automatic updater, or automatic tuning startup.

## Recorded RC evidence

The original 1.0.0 build 1 RC evidence records Darwin arm64, Apple clang 21, macOS 27.0.1, and SDK 27.0. Native compilation, ad hoc signature verification, all 12 automated RC phases, native off-state self-test, and read-only diagnostics passed. See `Tests/results/rc-final/`, [validation notes](../VALIDATION.txt), and [test fixture details](../Tests/README.md).

The suite exercised 16 EQ groups, seven ring groups, and nine actual-source callback groups in optimized and sanitizer variants. Cleanup fixtures checked 256 failure combinations and ten partial-start checkpoints. These checks validate DSP, callbacks under fixtures, and resource bookkeeping; they do not execute Apple’s live audio path.

The read-only hardware baseline identified an LG UltraFine USB stereo output at 48 kHz and 512 frames, default/system output, unmuted, with channel volumes near 0.19. Those checks did not change output or volume, request capture, or play audio.

A synthetic EQ/ring benchmark at 48 kHz with 64, 256, and 1024 frame blocks reported CPU time of 0.104–0.112% of equivalent audio duration, without clips, underruns, or overruns in those runs. It excludes Apple audio APIs and does not establish whole-app CPU usage, latency, or realtime guarantees.

The prior off-state UI smoke report checked a 500 × 775 content area and visible status/footer bounds. Its cached AppKit PNG lacks full native compositor content, so it did not establish complete visual acceptance. Source changes after that recorded run require fresh checks.

## Still pending

Live capture permission, audible stereo processing, listening quality, physical latency, sustained playback, installation/update behavior, device disconnect and format changes, sleep recovery, normal quit and force-quit recovery, require testing on a Mac with the intended output. Use [the Mac checklist](../MAC_TEST_CHECKLIST.md) and record actual outcomes before marking these accepted.

## RC2 checks on 2026-10-05

Version 1.0.0 build 2 compiles with warnings as errors and passes local ad hoc signature verification. The final portable suite passes 16 EQ groups, seven ring groups, and all eight preset bounds/headroom cases, including retained headroom during comparison. Native off-state self-test passes without creating audio resources. The isolated native UI smoke mode verifies persistent menu wiring, menu-driven reopen after window close, preset application, comparison, Flat EQ, and resize behavior without requesting capture or writing saved preferences. A screenshot scoped only to the updated app's own window was visually reviewed; the offline site was rendered and reviewed at 1280 px and 390 px widths. See `Validation/rc2/`.

Prior build 1 callback, sanitizer, cleanup, and benchmark evidence remains historical; the audio engine, EQ, and ring implementation were unchanged by RC2. Live listening and recovery acceptance remains pending. No playing app was replaced or interrupted during this pass.

The project license is undecided. This documentation does not supply a license grant. Public hosting, repository publication, and signed/notarized distribution are separate steps and are not performed by the local build.
