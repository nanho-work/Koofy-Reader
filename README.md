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
- [미사용 기존 코드 정리](docs/unused-code-cleanup.md)
- [이전 자체 엔진 설계 기록](docs/reader-core-reference-plan.md) — historical reference

Validate both platforms from the first reader integration milestone. Passing
the existing unit tests does not establish that real-device reading works.

Use Flutter 3.35.7 / Dart 3.9.2 (see `.fvmrc`). The native reader requires
Android API 24+ or iOS 15+. Run `flutter pub get`, then `pod install` in `ios`
for iOS. Regenerate the three bridge bindings together with
`dart run pigeon --input pigeons/reader_api.dart` after changing the contract.

## AdMob policy in this repository

- Public repository: do not commit production AdMob IDs.
- Development uses Google test ad IDs by default.
- Production IDs are injected only at release build time.

## Ad-related files

- `lib/features/ads/config/admob_ids.dart`
- `lib/features/ads/presentation/banner_ad_widget.dart`
- `lib/features/ads/data/rewarded_ad_service.dart`
- `lib/features/ads/presentation/ad_footer_widget.dart`

## Local secret file

1. Copy `.env.admob.example` to `.env.admob`
2. Fill real production values in `.env.admob`
3. Keep `.env.admob` private (`.gitignore` already configured)

## Android build script (auto test/prod split)

`scripts/android_ads_build.sh` handles branching automatically:

- `debug` mode => test IDs
- `release` mode => production IDs from `.env.admob`

Examples:

```bash
./scripts/android_ads_build.sh debug apk
./scripts/android_ads_build.sh release aab
```

## GitHub Actions release build

Manual workflow:

- `.github/workflows/android-release.yml`

Required repository secrets:

- `ADMOB_APP_ID_ANDROID`
- `ADMOB_BANNER_ANDROID`
- `ADMOB_REWARDED_ANDROID`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Execution:

1. GitHub repository -> `Actions`
2. Run `Android Release (AdMob Prod)` workflow
3. Download artifact `app-release-aab`

## Why Play Console said "debug mode"

If release signing is missing, Play Console may reject upload as debug-signed.
This repository now requires `android/key.properties` for release builds.

Local file format (`android/key.properties`):

```properties
storeFile=upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

In GitHub Actions, this file is generated from secrets automatically.

## Android manifest App ID injection

- Manifest key uses `${ADMOB_APP_ID}`
- Value is injected by Gradle `manifestPlaceholders`
- Default is Google test App ID
- Release script overrides with `ORG_GRADLE_PROJECT_ADMOB_APP_ID`

## Quick release checklist

1. Ensure `.env.admob` is present locally/CI secrets.
2. Run `./scripts/android_ads_build.sh release aab`.
3. Verify ads in internal test track before store submission.
