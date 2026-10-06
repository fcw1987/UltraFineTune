# Release signing preparation

The public 1.0.0 release is ad hoc signed and not notarized. These build options prepare a future release; they do not change that status. This preparation retains the current version metadata. Before producing a new release candidate, update both `Info.plist` and the CLI report in `Sources/main.m` consistently (proposed candidate: 1.0.1, build 4), and update release notes. A candidate must not be described as released or notarized until its checks pass.

## Local compatibility check

```sh
bash build.sh --hardened-runtime --output-dir /tmp/UltraFineTune-runtime-review
/tmp/UltraFineTune-runtime-review/UltraFineTune.app/Contents/MacOS/UltraFineTune --self-test
codesign --verify --strict /tmp/UltraFineTune-runtime-review/UltraFineTune.app
codesign --display --verbose=4 /tmp/UltraFineTune-runtime-review/UltraFineTune.app
```

The signature display should contain `runtime`. This remains an ad hoc build with no secure timestamp or trusted publisher. The self-test is an off-state check; it does not start capture, test listening, or establish permission acceptance. A successful build does not establish hardened-runtime compatibility with live Core Audio process taps.

## Sign using existing credentials

Proceed only when the operator has an authorized, existing Developer ID Application certificate and its private key available to `codesign`. This guide does not create credentials, export keys, or store secrets. Substitute the full existing certificate name:

```sh
bash build.sh --release-sign-identity 'Developer ID Application: FULL EXISTING NAME (TEAMID)' --output-dir /tmp/UltraFineTune-release-candidate
codesign --verify --strict /tmp/UltraFineTune-release-candidate/UltraFineTune.app
codesign --display --verbose=4 /tmp/UltraFineTune-release-candidate/UltraFineTune.app
```

Record the expected Developer ID Application authority, TeamIdentifier, secure `Timestamp`, and `runtime` flag. An unavailable identity, locked or inaccessible key, or timestamp-server failure must fail the build; the script does not fall back to ad hoc signing. Default source builds remain ad hoc signed. No entitlements are added by these options.

Before distribution, test the exact signed candidate under the [Mac acceptance checklist](../MAC_TEST_CHECKLIST.md), including capture permission and supported hardware playback. Capture testing requires separate operator approval. The existing `NSAudioCaptureUsageDescription`, bundle identifier `local.ultrafinetune.app`, and preference keys remain unchanged. Whether live process taps need an additional hardened-runtime audio entitlement in this app is unresolved; do not add microphone/audio-input entitlements or claim capture compatibility based on the off-state check.

## Notarize and verify before publication

These commands are a future operator checklist, not an automated release. They require a separately authorized submission and an existing notarytool Keychain profile. `EXISTING_NOTARY_PROFILE` is a placeholder, not a credential to create here.

```sh
ditto -c -k --keepParent /tmp/UltraFineTune-release-candidate/UltraFineTune.app /tmp/UltraFineTune-notary-submission.zip
xcrun notarytool submit /tmp/UltraFineTune-notary-submission.zip --keychain-profile EXISTING_NOTARY_PROFILE --wait
```

Save the submission ID and result. Require Apple's **Accepted** status. If rejected or incomplete, inspect the submission log with `xcrun notarytool log SUBMISSION_ID --keychain-profile EXISTING_NOTARY_PROFILE`; fix the issue and submit again. Never publish an unsuccessful submission as notarized.

After acceptance, attach and validate the ticket on the app (ZIP files cannot be stapled):

```sh
xcrun stapler staple /tmp/UltraFineTune-release-candidate/UltraFineTune.app
xcrun stapler validate /tmp/UltraFineTune-release-candidate/UltraFineTune.app
codesign --verify --strict /tmp/UltraFineTune-release-candidate/UltraFineTune.app
spctl --assess --type execute --verbose=4 /tmp/UltraFineTune-release-candidate/UltraFineTune.app
```

Require successful stapler validation and Gatekeeper acceptance with the expected notarized Developer ID origin. Repackage the stapled app with the installation guide and license, then calculate the final ZIP's SHA-256. Extract that exact ZIP to a clean location and repeat signature, stapler, and Gatekeeper checks before publishing. Validate a downloaded, quarantined copy through the normal launch path as part of release acceptance. Any app changes after signing require rebuilding, signing, and notarizing again.

Apple references: [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [resolving notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues), [hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime), and [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). The local `man codesign` and `xcrun notarytool --help` describe installed tool behavior.
