# Koofy-Reader

현재 UI와 공통 테마 구현: [UI 디자인 적용 문서](docs/ui-design-implementation.md).

Koofy Reader is a Flutter app targeting Android and iOS.

## Architecture and refactoring

The Flutter library opens the official native Readium reader on Android and iOS.
All reading entry points use Readium. The former Flutter renderer and its engine
selection/fallback paths have been removed. Prior reading positions and bookmarks
are archived; verified TXT positions migrate to content locators, while ambiguous
records require the user to review their previous context before opening.

- [Readium 단일 리더 전환과 검증](docs/readium-cutover.md) — current implementation
- [아키텍처와 기술 결정](docs/reader-architecture.md)
- [구현 단계와 검증 기준](docs/reader-validation-plan.md)
- [네이티브 리더 패치와 실행 방법](docs/reader-g1-implementation.md)
- [메인 서재 UI와 이어 읽기 연결](docs/library-home-implementation.md)
- [페이지 전환 효과 구현과 검증](docs/page-turn-implementation.md)
- [리더 글꼴 적용과 기기 테스트](docs/reader-fonts.md)
- [Firebase 기본 설정](docs/firebase-setup.md)
- [책·표지·글꼴 관리자와 다운로드 배포 절차](docs/reader-content-admin.md)
- [미사용 기존 코드 정리](docs/unused-code-cleanup.md)
- [이전 자체 엔진 설계 기록](docs/reader-core-reference-plan.md) — historical reference

Validate both platforms from the first reader integration milestone. Passing
the existing unit tests does not establish that real-device reading works.

Use Flutter 3.35.7 / Dart 3.9.2 (see `.fvmrc`). The native reader requires
Android API 24+ or iOS 15+. Run `flutter pub get`, then `pod install` in `ios`
for iOS. Regenerate the three bridge bindings together with
`dart run pigeon --input pigeons/reader_api.dart` after changing the contract.

## LevelPlay ads

Android and iOS use LevelPlay with Unity Ads and the built-in ironSource network.
App keys and separate library/viewer/rewarded ad unit IDs are configured in
`lib/features/ads/config/levelplay_ids.dart`. These are app identifiers, not secret API credentials.
AdMob SDK, adapter and direct ad requests are not included.

- Debug APK with integration test suite: `./scripts/android_ads_build.sh debug apk`
- Signed release AAB: `./scripts/android_ads_build.sh release aab`
- iOS device testing: `flutter run --dart-define=LEVELPLAY_TEST_SUITE=true`

The Settings page shows a test-suite button only in a non-release build with
`LEVELPLAY_TEST_SUITE=true`. This flag enables diagnostics, not forced test ads.
Register the physical test device in LevelPlay before requesting ads.
Existing Android signing configuration and GitHub signing secrets are still required for release.

See `docs/reader-ads.md` for configuration, reward delivery and device checks.

## Android release signing

Create `android/key.properties` for a locally signed release:

```properties
storeFile=upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

The `Android Release (LevelPlay)` GitHub Actions workflow requires
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
and `ANDROID_KEY_PASSWORD` secrets. It generates signing files and uploads
`app-release-aab`. No AdMob secrets are required.
