# Android foldable verification — 2026-10-09

No Galaxy Fold8 device was connected. These results are for an Android 16/API36 arm64 emulator using the generic 7.6-inch fold-in profile, not Samsung firmware or a Fold8 hardware certification.

## Results

- Current-source debug APK built and installed successfully.
- All 33 library widget tests passed, including hinge-aware layout and fold/unfold state retention.
- Native Readium instrumentation test passed: app window uses the full active display width, reading anchor remains visible after narrow/wide transitions, background/resume preserves it, and a subsequent page turn advances.
- Captures inspected at 1768×2208 (open), 884×2208 (narrow), and 1768×2208 (returned): no unused right strip.
- No Android production code change was needed for this result. Added a focused instrumentation regression test only; no store upload.

## Emulator limitation and reproduction

The generic profile changed its posture/folded-area metadata but did not automatically resize the app viewport under the installed API36 image. The initial posture-only tests failed the width-transition expectation. To verify the app's resize path, the host driver paired `adb emu fold/unfold` with `adb shell wm size 884x2208` / `wm size reset`. This is a controlled posture-plus-viewport simulation, not verification of Samsung's actual cover-display handoff.

The test `ReaderRenderingTest#foldableViewportAndCheckpointSurviveFoldUnfoldAndBackground` is opt-in through foldClosedState/foldOpenedState instrumentation arguments. It emits KoofyFoldTest REQUEST_FOLD / REQUEST_UNFOLD markers for a host driver; those arguments gate execution rather than controlling hardware directly. Local driver and logs: `work/android-fold-check/run-test.py`, `native-test.log`, `library-test.log`. Run the driver only against the dedicated Koofy_Fold_Check emulator on emulator-5554. Captures: opened.png, closed.png, returned.png.

The full reader app/ads/One UI lifecycle on a physical Fold8 remains unverified. App width and content anchor behavior passed within the stated test scope.
