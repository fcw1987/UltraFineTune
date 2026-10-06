# Release signing preparation

The 1.0.1 release (build 4) is Developer ID signed and Apple notarized, with hardened runtime, a secure timestamp, and a validated stapled ticket. The exact release ZIP passes strict signature verification, Gatekeeper assessment as Notarized Developer ID, and the signed off-state self-test. See the [validation summary](../VALIDATION.md) for its checksum and boundaries. The original 1.0.0 release remains ad hoc signed and not notarized.

The following operator checklist reproduces the signing and distribution process; signing or archive creation alone does not establish notarization.

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

## Archive with Xcode

The shared `UltraFineTune` scheme builds the existing native sources as a macOS application. Release uses manual Developer ID signing, hardened runtime, a secure timestamp, arm64, and macOS 14.2. It does not add sandbox or microphone entitlements. Use an existing authorized team and identity; override the project team for your own account:

```sh
xcodebuild -project UltraFineTune.xcodeproj -scheme UltraFineTune \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/UltraFineTune-derived \
  -archivePath /tmp/UltraFineTune.xcarchive \
  -disableAutomaticPackageResolution archive \
  DEVELOPMENT_TEAM=EXISTING_TEAM_ID \
  CODE_SIGN_IDENTITY='Developer ID Application: FULL EXISTING NAME (TEAMID)'
```

Open the genuine archive in Xcode Organizer. With an existing signed-in Apple Developer account, **Distribute App → Direct Distribution** provides the notarization workflow. Proceed with an Apple upload only when explicitly authorized. No new notarytool profile is needed for this Organizer route. Archive creation and Developer ID signing alone do not establish notarization or release acceptance.

## Notarize and verify before publication

These commands are an operator checklist, not an automated release. They require a separately authorized submission and an existing notarytool Keychain profile. `EXISTING_NOTARY_PROFILE` is a placeholder, not a credential to create here.

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
