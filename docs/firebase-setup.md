# 쿠피리더 Firebase 기본 설정

프로젝트 ID: `koofy-reader`
Android application ID / iOS bundle ID: `com.koofylab.koofyreader`
설정한 파일 저장소 이름: `koofy-reader.firebasestorage.app`

## 반영 내용

- 사용자가 제공한 Android JSON과 iOS plist의 프로젝트 ID 및 플랫폼 식별자를 확인했다.
- Android application ID·namespace·MainActivity 패키지와 iOS Runner/RunnerTests 번들 ID를 등록 정보에 맞췄다.
- `firebase_core`와 `lib/firebase_options.dart`를 추가했다. 옵션은 제공된 플랫폼 설정 파일에서 추출했으며 Firebase 콘솔에 새 앱을 중복 생성하지 않았다.
- Android/iOS 앱 시작 시 Firebase Core를 명시적 옵션으로 초기화한다. iOS plist는 Runner 리소스에 포함한다. Android는 명시적 Dart 옵션을 사용하므로 google-services Gradle 플러그인은 현재 추가하지 않았다.
- `.firebaserc`의 기본 프로젝트를 `koofy-reader`로 지정했다. 서버·규칙의 운영 반영 상태는 아래 콘텐츠 관리 항목을 참고한다.

## 기존 웹 관리자

Quiz_Site의 기존 npm Firebase SDK를 사용한다. CDN 스크립트를 중복 삽입하지 않는다.

- `lib/admin/firebase/koofy-reader.ts`: 전달받은 웹 설정, 이름이 `koofy-reader-admin`인 별도 Firebase 인스턴스 생성 함수.
- `lib/admin/firebase/client.ts`: 기존 로그인은 명시적으로 `[DEFAULT]` 인스턴스를 선택한다. 쿠피리더 인스턴스가 먼저 만들어져도 로그인 대상이 바뀌지 않는다.
- 쿠피리더용 로그인 화면을 추가하지 않았다.
- 서버는 기존 인증 프로젝트 `slimestrikeforce`의 ID 토큰을 명시적으로 검증하고 `superAdmin` 권한을 확인한다.
- 책·표지·글꼴 관리자 화면과 기존 관리자 토큰을 검증하는 HTTP API를 추가했다. 운영 반영 순서는 [콘텐츠 관리자 문서](reader-content-admin.md)를 따른다.

## 콘텐츠 관리 패치 상태

- Firestore `(default)`의 서울 지역과 Storage 버킷의 `US-EAST1` 생성을 실제 조회로 확인했다.
- 서버, 명시적 접근 규칙, 관리자 책·표지·글꼴 화면, 앱 공개 목록·다운로드와 네이티브 글꼴 연동을 로컬 구현했다.
- 2026-09-20 운영 서버 2개, 규칙, DB 인덱스와 전용 계정·서명 권한을 반영했다. 사용자에게서 관리자 사이트 배포 완료를 전달받았고, 운영 API의 빈 목록 HTTP 200·미인증 HTTP 401·CORS 검사를 통과했다. 첫 콘텐츠 등록과 실기기 다운로드는 다음 확인 단계다. 상세 흐름과 검증 결과는 [콘텐츠 관리자 문서](reader-content-admin.md)에 정리했다.
- 사용자가 Analytics 콘솔 연결을 완료했으나 이번 설정에는 Analytics SDK와 이벤트 수집을 추가하지 않았다.

## 기기 테스트 주의점

이전 `com.example` 식별자와 새 식별자는 OS에서 다른 앱이다. 새 앱 설치 시 기존 테스트 앱의 서재·설정이 자동 이전되지 않는다. 기존 앱은 삭제하지 말고 새 앱에서 테스트용 책을 다시 가져온다. Hot Reload가 아니라 전체 빌드가 필요하다.

서비스 계정 비공개 키는 앱이나 관리자 브라우저에 넣지 않는다. 현재 설정 파일들은 Firebase 클라이언트 등록 정보다.

## 초기 Firebase 기본 설정 검증 (콘텐츠 패치 이전)

- Flutter 정적 분석: 문제 없음.
- Flutter 기존 테스트 84개 통과.
- Android debug APK 빌드 성공.
- iOS Simulator 앱 빌드 성공(코드 서명 제외).
- Quiz_Site TypeScript 검사 통과.
- 실제 Firebase DB/Storage 통신, 배포 및 실물 기기 실행은 이번 검증에 포함하지 않았다.
