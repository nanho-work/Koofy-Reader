# iPhone Duo UIScene migration — 2026-10-09

The previous SDK-linked app rendered in a compatibility viewport on the Duo simulator, leaving unused space on the right. The app now adopts Flutter 3.35's scene lifecycle and builds with Xcode 27.1 RC (27A9275).

- `Info.plist` declares `FlutterSceneDelegate` and the Main storyboard in a single-window scene configuration.
- `AppDelegate` implements the pinned Flutter SDK's `FlutterPluginRegistrant`. Plugins and the privacy channel register against the scene-created engine.
- The native reader observes its own scene's activation/deactivation for checkpoint, speech, translation and banner handling.
- During Home transitions, Duo temporarily reports a closed viewport (466×678) before restoring the open viewport (951×669). Rebuilding Readium while inactive caused position restoration to time out. Inactive resize completions now defer the rebuild until scene activation.

## Validation

- iPhone Duo, iOS 27.1 (24A94232): full-width library and two-page reader, settings, dark theme, catalog and fonts displayed.
- Home → app return: same text and 2.9% reading position restored after the inactive-resize fix.
- Actual production source with ML Kit included: `flutter build ios --release --no-codesign --no-pub` passed with Xcode 27.1 RC. This is an unsigned device build, not a submission or physical-device test.
- Plist lint and diff whitespace checks passed.

## Screenshot artifacts

`work/store-duo/Koofy-Reader-iPhone-Duo-2007x2853.zip` contains six RGB PNGs, each 2007×2853. Raw open-display captures are 2853×2007. `preview.png` is the contact sheet; `render.mjs` and the SVGs retain the editable compositions.

Capture uses an isolated source copy in `work/duo-capture`. The pinned ML Kit binary has no arm64 simulator slice, so translation is stubbed only in that copy; production dependencies and translation source remain intact. Translation was not exercised or depicted. Simulator checks do not replace device validation of ads, consent, TTS or translation.

No app version bump or App Store upload was performed. Full-width Duo behavior needs a new app release. The global Xcode selection remains unchanged; commands used the toolchain under `work/duo-toolchain/Xcode.app` explicitly.
