# Validation boundaries

Historical RC2 local validation on macOS arm64: native build with warnings as errors, strict ad hoc signature verification, 16 EQ groups, seven ring groups, and eight preset cases. Off-state self-test creates no audio resources. Isolated UI smoke verifies menu wiring, reopen after closing the window, preset application, comparison, Flat EQ, resizing, and visible footer/status, without capture or saved preference writes.

The earlier RC2 publication pass repeated the focused portable fixtures, actual-source callback/cleanup fixtures, native build, and off-state checks after branding. A screenshot of only the app window documents its controls. GitHub Actions repeats build and focused tests for pushed revisions. CI output is available under the repository’s Actions tab.

Earlier local RC fixtures also exercised sanitizers, nine callback groups, 256 cleanup failure combinations, and ten partial-start checkpoints. Developer machine logs and identifiers are intentionally excluded from public source history. Historical results are not claims about every future revision.

Live permission, listening quality, sustained playback, physical latency, installation/update, sleep/disconnect, quit, and force-quit recovery remain pending in the [Mac checklist](MAC_TEST_CHECKLIST.md). No benchmark claim about whole-app CPU or device latency is made.

Stable 1.0.0 build 3 repeats the native build, strict signature verification, off-state self-test, isolated UI smoke, and publication checks. The metadata and product copy change does not alter DSP or engine code. GitHub Actions runs the repository’s native build and focused fixtures before merge.
