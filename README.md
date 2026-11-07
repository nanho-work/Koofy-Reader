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

## 관리자 통계 (2026-11-06)

웹 메뉴는 Quiz_Site의 `/admin/projects/koofy-reader/statistics`이며, 기존
`readerAdmin?action=statistics`의 superAdmin 인증을 사용합니다. 앱 재빌드는
필요하지 않습니다. 앱 사용 / Google Play / App Store를 분리하며 첫 실행과
스토어 다운로드, 앱 참여 시간과 독서 시간을 서로 합산하지 않습니다.

- GA 속성: `555135756`. Data API 사용 설정과 런타임 서버 계정의 속성 뷰어
  등록을 완료했습니다. 배포 후 서버에서 실제 보고서 조회 검증이 필요합니다.
- Play 보고서 버킷: `pubsite_prod_4982189337387504901`. 기존 서버 계정에
  Play Console 보고서 조회 권한을 등록했고 활성 상태를 확인했습니다.
  재무·주문·수정·출시 권한은 부여하지 않았습니다. 배포 후 런타임 서버에서
  보고서 접근 검증이 필요합니다. 로컬 사용자 계정에는 해당 접근 권한이 없습니다.
- Apple은 판매 및 보고 역할의 `Koofy Reader Reports` 팀 키를 사용합니다.
  개인 키는 Secret Manager의 `koofy-reader-apple-reports-key`에 보관하고,
  기존 서버 계정에 이 항목의 조회 권한을 연결했습니다. 2026년 11월 5일 판매
  요약 보고서로 API 인증과 쿠피리더 집계를 확인했습니다.

서버 환경변수: `READER_GA_PROPERTY_ID`, `READER_PLAY_REPORT_BUCKET`,
`READER_APPLE_KEY_ID`, `READER_APPLE_ISSUER_ID`, `READER_APPLE_VENDOR_NUMBER`,
`READER_APPLE_KEY_SECRET` (형식: `projects/koofy-reader/secrets/이름/versions/latest`).
로컬 `functions/.env.koofy-reader`에는 GA·Play 식별자, Apple 식별자와
Secret Manager 참조를 설정했습니다. 이 파일은 Git에서 제외됩니다.

연결 설정 후 프로젝트 루트에서 서버 반영:

```sh
firebase deploy --only functions:reader:readerAdmin --project koofy-reader
```

웹은 Quiz_Site 변경을 사용자가 커밋·푸시해 반영합니다. 통계 캐시는 서버에서
30분 유지하며, 원본 보고서의 미제공 날짜는 0건으로 채우지 않습니다.
Apple 보고서가 실제로 제공되었고 앱 신규 수량이 없는 날짜만 0으로 집계합니다.
서버 집계 캐시는 클라이언트 Firestore 접근이 금지된 컬렉션에 저장됩니다.
GA 다운로드 세부 구분에는 이벤트 맞춤 측정기준 `result`, `content_type`,
독서 시간에는 이벤트 맞춤 측정항목 `seconds`(초)가 필요하며 등록 전 기간은
소급되지 않습니다. 현재 앱의 수집 동의 기본값은 변경하지 않았습니다.
