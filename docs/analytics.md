# 쿠피리더 선택적 사용 통계 — 2026-10-21

## 구현

기존 Firebase 프로젝트 `koofy-reader`의 Android/iOS 앱을 사용한다. 신규 앱이나 GA 속성을 중복 생성하지 않는다. `firebase_analytics 12.6.0`은 현재 firebase_core와 호환되는 버전이다.

- Android: google-services 플러그인이 기존 `android/app/google-services.json`을 리소스로 변환한다. Dart 옵션과 동일 프로젝트/앱이어야 한다.
- iOS: 기존 GoogleService-Info.plist + FirebaseAnalytics/Core (광고 ID 지원 제외).
- 최초 및 기존 사용자에게 별도 선택 화면을 한 번 제공한다. 광고 동의/ATT와 독립적이다. 기본 수집 OFF, 허용한 뒤 ON. 설정 > 개인정보 및 광고에서 변경.
- Analytics 광고 저장·광고 사용자 데이터·개인화 동의는 항상 false. Android 광고 ID와 iOS IDFV 수집 OFF. 광고 SDK의 기존 동의 흐름은 별도다.
- 자동 화면 이름 보고 OFF. 사용자 ID, 책 제목/본문/파일명/경로/검색어/로케이터/원시 예외를 전송하지 않는다.
- 전송 실패가 독서/가져오기/다운로드에 영향을 주지 않는다. 과거 사용 기록은 재전송하지 않는다.

## 이벤트 계약

| 이벤트 | 파라미터 | 의미 |
|---|---|---|
| SDK first_open / session_start / user_engagement | SDK 기본 정보 | 동의 사용자 최초 실행·사용 세션. 설치만 하고 열지 않은 사용자는 측정 불가 |
| book_open | source: guide/bundled/local | 네이티브 엔진 ready 이후. 로컬 책 ID는 전송하지 않음 |
| book_import | format: txt/epub/other, result: start/success/existing/failed/cancelled | 파일별 가져오기 결과. 파일명은 형식 분류에만 사용 |
| series_open | content_id | 공개 연재 상세 페이지 열기 |
| catalog_download | content_type: book/font, content_id, result: start/success/failed | 실제 설치 흐름. 이미지 미리보기 다운로드 제외 |
| tts_start | 없음 | 음성 재생 상태로 전환(재개 포함) |
| auto_turn_start | 없음 | 자동 페이지 넘김 시작/재개 |
| bookmark_add | 없음 | 저장 성공 후 책갈피 수 증가. 삭제 취소도 증가로 집계 가능 |
| font_apply | 없음 | 글꼴 변경 요청. 개인 글꼴명/ID는 전송하지 않음 |
| reading_time | seconds | ready 이후 네이티브 독서 화면 foreground 시간. background/close 시 구간별 전송 |

사용자 정의 이벤트에는 `app_language`(ko/en/ja)를 포함한다. OS/앱 버전은 SDK 기본 차원이다. `local`은 가져온 책과 다운로드 후 로컬 저장된 책 모두 포함한다. 개인 파일 식별은 의도적으로 하지 않는다.

독서 시간은 화면이 활성인 시간으로 실제 집중 독서를 보장하지 않는다. 열린 설정/도구 시간도 포함한다. 강제 종료 전 아직 보고하지 않은 구간은 누락될 수 있다. 수집 거절자는 모든 통계에서 제외되어 스토어 설치 수와 같지 않다. SDK를 처음 추가한 업데이트는 과거 설치일을 복원하지 못한다.

## GA4 콘솔에서 확인/설정

- 프로젝트 설정 > 통합의 GA4 속성, 해당 속성 Android/iOS 데이터 스트림이 위 Firebase 앱과 같은지 확인.
- 이벤트 맞춤 측정기준: `app_language`, `source`, `format`, `result`, `content_type`, `content_id`.
- 이벤트 맞춤 측정항목 `seconds` (초). reading_time 합산으로 독서 활성 시간을 본다.
- 데이터 보관 기간·Google Signals·광고 계정 연결/데이터 공유를 실제 운영 정책과 대조. 코드가 콘솔 설정을 자동 변경하지 않는다.
- `first_open`은 설치 수가 아니다. 신규/재설치 및 동의 시점 영향이 있으므로 Play/App Store 설치 통계와 구분한다.

## 출시 전 필수 확인 (아직 게시/출시하지 않음)

1. DebugView 실기기 검증: Android `adb shell setprop debug.firebase.analytics.app com.koofylab.koofyreader`; 해제는 `.none.`. iOS 실행 인수 `-FIRDebugEnabled`; 해제 `-FIRDebugDisabled`.
2. 신규/기존 사용자 거절 시 이벤트 없음, 허용 후 이벤트 도착, 철회 후 새 이벤트 없음. 앱 재실행에서도 선택 유지.
3. 책 열기→배경 전환→복귀→닫기, 소설/글꼴 다운로드 성공/실패, TXT/EPUB 가져오기, TTS/자동 넘김/책갈피/글꼴 변경을 양 OS에서 확인. 읽던 위치 복구도 확인.
4. `assets/legal/reader_privacy.json`의 3개 언어 변경을 공개 웹 개인정보처리방침에 동기화하고 배포한다. 현재 작업은 Reader 저장소만 수정한다.
5. Play 데이터 보안 및 App Store 개인정보에 Analytics의 기기/앱 식별자·제품 상호작용·사용 데이터·대략적 위치 등의 실제 SDK 처리를 검토/반영. 선택적 수집 및 분석 목적, 광고 SDK의 기존 수집과 구분. 이 문서는 콘솔 선언 완료 증거가 아니다.
6. 버전/빌드 번호를 올려 양 OS 배포. 기존 설치에 원격으로 SDK를 추가할 수 없다.

## 참고

- https://firebase.google.com/docs/analytics/flutter/get-started
- https://firebase.google.com/docs/analytics/debugview
- https://firebase.google.com/docs/analytics/ios/configure-data-collection
- https://firebase.google.com/docs/android/setup

## 이번 패치 검증 결과

- `dart analyze lib test`: 문제 없음. 전체 `flutter analyze`는 기존 `work/` 내 임시 사본과 Firebase CLI 템플릿까지 검사하여 무관한 오류를 보고하므로 실제 앱/테스트 범위로 재검증했다.
- 사용 통계 동의·철회·재시작·개인정보 제외·전송 실패 및 기존 가져오기/다운로드/개인정보: 47개 통과.
- 네이티브 리더 코디네이터·리더 시작·카탈로그/연재 UI: 34개 통과.
- 새 동의 화면 허용/거절 경로: 2개 통과. 합계 83개.
- Android debug APK, iOS debug simulator 빌드 성공. 출시용 빌드/스토어 업로드는 하지 않았다.
- Android JSON과 iOS plist의 프로젝트 `koofy-reader` 및 앱 ID가 Dart Firebase 옵션과 일치함을 확인했다.
- 실제 GA4 DebugView 수신은 아직 검증하지 않았다. 콘솔 설정·웹 방침·스토어 개인정보 항목도 이 패치로 자동 변경되지 않는다.
