# 네이티브 리더 G1 구현 기록

> 과거 단계의 구현·검증 기록입니다. 현재 단일 리더 전환 상태는 [Readium 전환 문서](readium-cutover.md)를 따릅니다. 아래의 기존 리더 선택·보존 설명은 현재 실행 경로가 아닙니다.

작성일: 2026-09-19

Flutter 서재에서 공식 Readium Kotlin/Swift 전체 화면을 여는 첫 통합 패치의 기록이다. 최초에는 표지 왼쪽 위 책 아이콘으로 새 리더를 열었다. 이후 [메인 서재 패치](library-home-implementation.md)에서 새 책은 새 리더로, 저장된 책은 최근 기록을 만든 리더로 열도록 변경했다. 명시적인 리더 선택은 책 더보기 메뉴에 있다. 기존 SharedPreferences 책 목록·위치·책갈피를 덮어쓰지 않는다. G2~G5 전체 리팩터링 또는 출시 검증 완료를 의미하지 않는다.

## 실행 환경

| 항목 | 고정·확인한 버전 |
| --- | --- |
| Flutter / Dart | 3.35.7 stable / 3.9.2 (`.fvmrc`) |
| Readium Kotlin | 3.1.2, 공식 EPUB navigator |
| Readium Swift | 3.11.0, CocoaPods |
| Pigeon | 26.0.1 |
| Drift | 2.28.2 |
| Android | 앱 최소 API 24 (Flutter 3.35.7 기본값), compile/target SDK 36, core library desugaring |
| iOS | 최소 iOS 15, Swift 5.10 |
| 이번 iOS 빌드 도구 | Xcode 26.3 (17C529) |

```sh
flutter pub get
dart run pigeon --input pigeons/reader_api.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

iOS는 `ios` 디렉터리에서 `pod install`을 실행하고 `Runner.xcworkspace`를 연다. `Podfile.lock`과 `pubspec.lock`을 함께 관리한다. iOS 시뮬레이터 빌드는 `flutter build ios --simulator --debug --no-pub`로 실행한다. 배포용 서명·실기기 실행은 별도 검증 대상이다.

Android 네이티브 복구 테스트는 에뮬레이터/기기를 연결한 후 `android`에서 `./gradlew :koofy_reader_bridge:connectedDebugAndroidTest`로 실행한다. iOS 네이티브 테스트는 Xcode의 `Runner` scheme에서 `RunnerTests`를 선택해 시뮬레이터로 실행한다. iOS 테스트에는 고유한 한글 문단 `p60`을 실제 표시 범위에서 검사하는 Readium 렌더링 테스트가 포함되어 있다. 테스트 코드가 존재하는 것과 해당 환경에서 통과한 것은 구분한다.

## 구현 구조

| 경로 | 책임 |
| --- | --- |
| `packages/koofy_reader_bridge` | Flutter 플러그인, 공식 Readium 호스트, 네이티브 체크포인트 |
| `pigeons/reader_api.dart` | Dart/Kotlin/Swift 공통 명령·이벤트 규격과 생성 경로 |
| `lib/features/native_reader/data` | 원본 보관·TXT 변환·EPUB 검사, Drift/SQLite 기록 |
| `lib/features/native_reader/application` | 세션 생성, 복구, 직렬 DB 반영, 저장 확인 |
| `lib/features/native_reader/presentation` | 준비·오류·닫기 상태, 네이티브 진입 화면 |

네이티브 독서 화면에서 페이지 이동·글자 크기·테마·페이지/스크롤·열 배치를 처리한다. 본문은 Flutter `TextPainter`로 다시 분할하지 않는다. EPUB의 로컬 본문·리소스를 Readium에 전달한다.

G1 공통 API는 `openReader`, `closeReader`, `goTo`, `applyPreferences`, `pendingCheckpoints`, `acknowledgeCheckpoint`다. 이벤트 종류는 `ready`, `locationChanged`, `preferencesChanged`, `closed`, `error`다. `openReader` 응답은 접수이고, `ready`는 네이티브 본문 표시 준비 이벤트다. Pigeon의 전달 완료는 DB 저장 확인이 아니다.

설정은 글자 배율, 열 요청(자동/1/2), 스크롤 여부, 밝게/종이색/어둡게다. 두 플랫폼 SDK의 글자 크기는 배율로 전달한다. 엔진이 표시하는 위치 개수나 장 내부 페이지 수는 글자 크기·화면 변경과 무관한 종이책 쪽수가 아니다.

## 위치 저장과 복구

1. 네이티브에서 안정된 위치와 설정을 세션별 복구 파일에 기록한다.
2. Dart coordinator가 이벤트를 직렬 처리한다. SQLite는 Dart 한 곳에서만 쓴다.
3. `publicationId`·콘텐츠 리비전·영구 세션 세대·순서를 검증하고 트랜잭션으로 반영한다.
4. commit 후에만 해당 세션·순서에 ACK를 보낸다. 오래된 ACK는 새로운 네이티브 기록을 삭제하지 않는다.
5. 다음 책 열기 전에 미확인 기록을 먼저 복구하고 SQLite에서 새 세대를 발급한다.

진단용 `error`는 위치 기록이 아니므로 체크포인트를 대체하거나 ACK하지 않는다. 잘못된 복구 기록과 DB 쓰기 실패는 성공 처리하지 않는다. 네이티브 호스트가 과거 Intent/화면 복원 인자만으로 오래된 위치를 저장하지 않도록 한다.

G1 위치 테이블은 `publicationId + contentRevision` 기준이다. 현재 배치의 페이지 번호 대신 Readium Locator JSON을 보관한다. Android SDK의 기본 위치 이벤트는 본문 자원·진행률 중심이며, 문장 단위의 정확한 앵커 복원을 보장하지 않는다. iOS는 첫 표시 요소 Locator를 활용한다. 두 플랫폼의 실제 문맥 일치와 반복 재배치 검증은 G2 기준을 적용한다.

## TXT·EPUB 지원 범위

- TXT 원본은 그대로 보관하고 안정적인 문서 주소·문단 ID를 가진 내부 EPUB 3으로 변환한다. 동일한 입력과 변환 규칙은 동일한 결과를 만든다.
- `publicationId`는 기존 서재의 `book.id`, `contentRevision`은 실제 읽기용 EPUB 바이트의 SHA-256이다. 원본/변환본이 달라지면 예전 Locator를 무조건 재사용하지 않는다.
- UTF-8, BOM이 있는 UTF-16을 엄격히 해석한다. CP949 등 다른 인코딩은 안내와 함께 거절한다. 인코딩 선택 UI는 아직 없다.
- DRM 없는 정적 리플로우 EPUB을 원형 보관한다. 표준 IDPF/Adobe 글꼴 난독화는 허용한다. DRM·고정 레이아웃·본문 스크립트·외부 리소스 등 G1 범위 밖 콘텐츠는 명시적으로 거절한다.
- EPUB 검사에는 경로 이탈·ZIP 구조와 CRC·해제 크기·manifest/spine·본문 XML 검사 등이 포함된다. 임의의 EPUB 전체 표준 적합성 검사를 대신하지 않는다.
- 원본 TXT 20 MiB, EPUB 40 MiB, EPUB 해제 합계 128 MiB, 개별 항목 32 MiB, XML/CSS 문서 4 MiB 한도가 있다.
- 기존 원본이 없어도 준비가 완료된 책은 앱 소유 복사본으로 다시 연다. 변환 결과가 손상되면 보관된 원본에서 복구한다.

## 검증 결과

| 항목 | 결과 |
| --- | --- |
| `flutter analyze --no-pub` | 이상 없음 |
| `flutter test --no-pub --reporter expanded` | 94개 모두 통과 (기존 66개 + 신규 28개) |
| 원본·변환·입력 검사 | 신규 15개 테스트 통과 |
| 위치 DB·세션·ACK·오류 이벤트 | 신규 11개 테스트 통과 |
| 열기 도중 뒤로가기 | 신규 위젯 테스트 2개 통과 |
| Android debug APK | 빌드 성공, API 36 에뮬레이터에서 서재 실행 확인 |
| Android 네이티브 테스트 | 최신 소스 instrumentation 7개 모두 통과, 건너뜀 없음: 복구 기록 5개 + Readium 실제 렌더링 2개 |
| Android 본문 | 한글 TXT→EPUB 본문 표시·다음 페이지·서재 복귀·재개방 확인. 샘플의 같은 문단과 장 내부 `2/2` 표시 복원 |
| Android 글자 크기 | 100%→110% 변경 후 기존 문단 표시 유지, 복원 시간 초과 없음 |
| Android 재시작·회전 | 앱 프로세스를 다시 시작한 뒤 110% 설정·같은 문단 복원. 가로 회전 후 문단 표시 유지 |
| Android 두 페이지·문단 복원 | 120개 한글 문단의 `p-060` 초기 복원·다음 이동·140% 글자 변경·명시적 위치 복원 통과. 폭 914dp 가로 화면에서 실제 CSS 두 열과 다음 펼침 이동 확인 |
| iOS debug 앱·네이티브 테스트 빌드 | Xcode `build-for-testing` 성공 |
| iOS 네이티브 테스트 | 전용 iPad Pro 11 M5 / iOS 26.3 시뮬레이터에서 5개 모두 통과: 복구 기록 4개 + Readium 실제 렌더링 1개 |
| iOS 두 페이지·문단 복원 | 120개 한글 문단의 `p60` 이동, 150% 글자·종이색 변경 후 실제 문단 표시 범위와 CSS 두 열 확인, 정상 닫기 |
| iOS Flutter 연결 수동 확인 | 전용 iPad에서 서재의 새 리더 버튼 → TXT 준비 → 네이티브 본문 → 110% 글자 변경 → 서재 복귀 → 재개방 후 본문·설정 유지 확인 |
| iOS 실제 저장 경로 | 수동 실행 후 SQLite `reader_positions`의 세대 2·순서 2, 글자 배율 1.1, 본문 href 확인. 닫은 뒤 네이티브 체크포인트 디렉터리가 비어 있어 commit→ACK 정리 확인 |
| iOS 설정 창 | 기존 AA 컨텍스트 메뉴에서 키보드가 나타나는 현상을 재현. 읽기 입력 포커스를 해제한 네이티브 선택 창으로 수정 후 키보드 없이 열림·110% 설정 표시·종이색 적용·서재 복귀 확인. 수정 후 네이티브 5개 테스트 재통과 |

새 테스트는 이전 세션·중복 순서 무시, DB commit 이후 ACK, 실패한 쓰기 보존, 파일 DB 재개방 후 세대 증가, 진단 이벤트의 위치 덮어쓰기 방지, 준비/복구 중 취소를 포함한다. 기존 앱의 사용자가 보고한 구동 실패는 기기·파일·증상이 아직 특정되지 않아 해결 확인으로 계산하지 않는다.

Android 수동 실행은 API 36 `Medium_Phone` 에뮬레이터의 debug 앱, `assets/books/sample_1.txt`(새벽의 쿠피)로 진행했다. 원본 SHA-256은 `eb30e9bdc82e9da4c851f0a4eb097ff416bf8a6f758b129e884b78455f96c9f7`이다. 재개방 전후의 화면에서 “한 문단을 더 넣어 스크롤 길이를 확보합니다.” 문단이 같은 위치에 표시되는 것을 확인했다. 짧은 샘플 한 건의 결과를 긴 책·모든 설정 조합의 정확한 앵커 보장으로 확대하지 않는다.

두 페이지 검사에서 Readium 기본 CSS의 `60em` 조건이 일부 넓은 화면에서도 한 열을 표시하는 문제가 확인됐다. Koofy는 공식 reading-system CSS 설정 API로 열 수·폭을 지정하고, 가용 폭 700dp/pt를 기준으로 자동 배치를 한 열 또는 두 열로 결정한다. 좁은 화면·스크롤은 한 열이며 Android의 분리/가림 힌지는 안전한 한 패널로 대체한다. SDK 배포 파일을 직접 수정하지 않는다. 양 플랫폼 렌더링 테스트는 실제 두 열인지 확인하여 단순 설정 전달 성공과 구분한다.

Android의 수동 서재 실행 검증 이후 에뮬레이터 저장 공간 때문에 최신 전체 앱 재설치는 완료하지 못했다. 이후의 시작 중 닫기·초기 앵커 보존·두 열 CSS 수정은 최신 소스의 APK 빌드와 더 작은 네이티브 테스트 APK 실행으로 검증했다. 두 열 표시는 수정 후 실제 renderer 테스트에서 통과했다. 기존 에뮬레이터의 앱·데이터를 지워 공간을 확보하지 않았다.

검증에 사용한 Android 에뮬레이터·전용 ADB 서버는 종료했다. iOS 전용 임시 시뮬레이터는 검증 후 종료·삭제했고 기존 시뮬레이터 데이터는 보존했다. TalkBack/VoiceOver 실사용, 실제 폴더블, 기기용 release 실행은 미검증이다.

## 남은 단계

- G2: 실제 폴더블 힌지·회전·분할 창, 한쪽/양쪽 반복 변경, 표시 앵커 검증, 프로세스 종료·채널 단절·저장 오류 주입, Android↔iOS Locator 교환.
- G3: CP949 인코딩 선택, 더 넓은 EPUB 입력 집합, EPUBCheck, 변환 중단·재시도와 큰 파일 성능.
- G4: 기존 기록 백업·마이그레이션, 새 리더를 기본 경로로 전환, 검색·책갈피·선택 기록 UI의 통합.
- G5: Android release/iOS 실기기 빌드, 접근성·성능·메모리 검증, 양 플랫폼 CI.

실제 폴더블에서 양쪽 페이지 품질, 강제 종료 직전의 모든 위치, 기존 기록 자동 이전, 상용 DRM, TTS·동기화·PDF·만화는 이번 패치의 완료 항목으로 표시하지 않는다. 상세 합격 기준은 [독서 검증 계획](reader-validation-plan.md)을 따른다.
