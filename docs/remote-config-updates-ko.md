# 쿠피리더 업데이트 안내 운영 방법

2026-09-26 구현·콘솔 설정 기록. Firebase 프로젝트는 `koofy-reader`다. 이번 작업은 설정 게시·코드 패치·테스트·의존성 준비까지이며 앱 빌드나 스토어 업로드는 하지 않았다.

## 현재 적용 상태

[Firebase Remote Config 콘솔](https://console.firebase.google.com/project/koofy-reader/config/env/firebase)에 구성 버전 1을 게시했다. `android_updates`, `ios_updates` 그룹에 각각 7개, 총 14개 키가 있다. 콘솔의 각 키에도 한글 설명을 넣었다.

| 설정 | Android | iOS |
| --- | --- | --- |
| 안내 활성화 | `false` | `false` |
| 최신 버전 기준값 | `1.2.0` | `1.0.0` |
| 최소 지원 버전 | `1.0.0` | `1.0.0` |

최신 버전 값은 현재 개발·심사 기록을 기준으로 입력한 **비활성 초기값**이다. 모든 사용자가 다운로드할 수 있는 정식 버전임을 뜻하지 않는다. 스토어 설치 가능 여부를 확인하기 전에는 안내를 켜지 않는다.

이번 기능이 없는 이전 앱이나 기존 IPA에는 Firebase 설정만 바꿔도 안내가 생기지 않는다. 새 코드가 포함된 앱을 한 번 배포해야 이후 버전부터 원격 안내가 가능하다. 앞서 만든 iOS `1.0.0 (7)` IPA에는 이 기능이 없다. 다음 iOS 빌드는 8 이상의 번호를 사용한다.

## 사용자에게 보이는 동작

1. 앱 프로세스가 새로 실행될 때 개인정보 안내 이후, 서재에 들어가기 전에 한 번 확인한다. 설정 > 앱 버전에는 실제 설치된 버전과 빌드 번호가 표시된다.
2. 설치 버전이 최신 버전 이상이면 안내 없이 서재로 이동한다.
3. `최소 버전 ≤ 설치 버전 < 최신 버전`이면 제목·문구와 **업데이트 / 나중에**를 표시한다. 나중에를 누르면 그 실행 중에는 다시 표시하지 않는다.
4. `설치 버전 < 최소 버전`이면 **업데이트가 필요합니다** 제목과 필수 문구를 표시한다. 이 경우 나중에는 없고 서재로 진행하지 않는다.
5. 업데이트는 해당 스토어 링크를 외부 앱으로 연다. 스토어를 여는 것 자체가 업데이트 완료를 뜻하지는 않는다. 앱 삭제를 안내하지 않는다.
6. 홈 화면으로 잠깐 나갔다 복귀, 스토어에서 복귀, 책 이동, 화면 재구성은 새 확인을 발생시키지 않는다. 앱을 완전히 종료했다 다시 실행하면 다시 확인한다. OS가 프로세스를 종료했다 재실행한 경우도 새 실행이다.
7. 실시간 설정 구독이나 백그라운드 팝업은 사용하지 않는다. 앱 실행 도중 Firebase 값을 변경해도 다음 실행 때 적용한다.

서버 조회 시간은 3초, 버전 조회까지 포함한 전체 대기는 최대 4초다. 오프라인·요청 제한·시간 초과·SDK 오류·잘못된 설정·다른 앱의 링크는 **독서를 막지 않고 서재로 진행**한다. 실패 시 이전에 캐시된 필수 업데이트 설정으로 차단하지 않는다. 시간 초과 뒤 늦게 응답이 도착해도 그 실행에서는 안내를 끼워 넣지 않는다. 따라서 최소 버전은 온라인 운영 안내이며 보안상 절대적인 접근 통제 수단이 아니다.

스토어 연결에 실패하면 재시도와 복사 가능한 주소를 보여 준다. 최소 버전 차단 중 원격 값을 수정했다면 앱을 종료 후 다시 실행해야 한다.

## 설정 키 설명

두 플랫폼은 각각의 키만 읽는다. Android 버전을 iOS 기준으로 비교하지 않는다.

| Android 키 | iOS 키 | 뜻과 입력 방법 |
| --- | --- | --- |
| `android_update_enabled` | `ios_update_enabled` | Boolean. `true`는 안내 사용, `false`는 모든 업데이트 안내와 최소 버전 차단 중지. |
| `android_update_latest_version` | `ios_update_latest_version` | String. 실제 배포된 최신 버전. 예: `1.3.0`. |
| `android_update_minimum_version` | `ios_update_minimum_version` | String. 계속 사용 가능한 가장 낮은 버전. 일반 업데이트에서는 그대로 둔다. |
| `android_update_title` | `ios_update_title` | String. 선택형 안내 제목. 1~100자. 기본값: 새 버전이 있습니다. |
| `android_update_message` | `ios_update_message` | String. 선택형 안내 본문. 1~2000자. 개선 내용을 간단히 적는다. |
| `android_update_required_message` | `ios_update_required_message` | String. 최소 버전 미만일 때 표시할 본문. 1~2000자. 필요한 이유와 기존 기록 보존 안내를 적는다. 필수 안내 제목은 앱에서 고정한다. |
| `android_update_store_url` | `ios_update_store_url` | String. 아래 쿠피리더 스토어 주소. 다른 앱·사이트 주소, HTTP 주소는 무시한다. |

버전은 숫자 세 부분 `주.부.패치` 형식이다. `1.0.0`처럼 입력하고 `v1.0`, `1.0.0+8`, `빌드 8`은 입력하지 않는다. 숫자로 비교하므로 `1.10.0`은 `1.9.0`보다 높다. 최소 버전은 최신 버전보다 높을 수 없다. 버전이 잘못되면 안내를 표시하지 않는다.

빌드 번호는 진단용 표시이고 원격 비교에는 쓰지 않는다. 예를 들어 iOS `1.0.0 (3)`과 `1.0.0 (8)`은 같은 스토어 버전으로 취급한다. 같은 버전의 TestFlight 빌드 갱신은 TestFlight가 담당한다.

Android 주소:

```text
https://play.google.com/store/apps/details?id=com.koofylab.koofyreader
```

iOS 주소:

```text
https://apps.apple.com/kr/app/id6814514729
```

이 링크는 앱 식별자에 맞게 설정한 주소다. 정식 출시 전에는 일반 사용자에게 설치 페이지가 제공되지 않을 수 있다. 내부 테스트/비공개 테스트 참여 자격을 이 링크나 Remote Config가 부여하지 않는다.

## 일반 업데이트를 알리는 순서

예: Android 1.3.0을 안내하고 1.0.0 이상은 계속 이용하게 할 때.

1. 새 앱을 스토어에 업로드하고 심사·배포를 완료한다. 단계적 배포나 국가·OS 제한이 있다면 안내 대상이 실제로 설치할 수 있는지 확인한다.
2. 콘솔에서 `android_updates`를 펼친다.
3. `android_update_latest_version`을 `1.3.0`으로 바꾼다.
4. `android_update_minimum_version`은 `1.0.0`으로 유지한다.
5. `android_update_title`, `android_update_message`에 변경 내용을 적는다.
6. 설치 링크를 확인하고 `android_update_enabled`를 `true`로 바꾼 후 변경사항을 게시한다.
7. 이 기능을 포함한 이전 버전 앱을 완전히 종료 후 실행해 안내·나중에·스토어 이동을 확인한다. 새 버전에서는 안내가 없는지도 확인한다.

iOS는 `ios_` 키에 같은 순서를 적용한다. Android만 출시됐을 때 iOS 안내까지 켜지 않는다. 테스트를 위해 운영 최소 버전을 높이지 않는다.

## 최소 버전을 올리는 경우

심각한 호환성 문제 등 기존 버전을 계속 지원할 수 없을 때만 사용한다. 최신 버전이 모든 해당 사용자에게 제공되는지 확인한 뒤 최소 버전을 올린다. 최소 버전을 최신 버전과 같게 하면 그보다 낮은 모든 버전에 필수 안내가 나온다.

잘못 설정했다면 해당 플랫폼 `enabled=false`를 게시한다. 앱이 다음에 정상 조회하면 안내를 중지한다. Firebase의 변경 내역에서 이전 템플릿으로 되돌리는 방법도 있지만, 다른 설정까지 되돌아갈 수 있으므로 우선 해당 스위치를 끄는 것이 단순하다.

## 테스트 배포와 정식 배포

앱 컴파일 설정 `READER_UPDATE_CHANNEL`의 기본값은 `store`다. 기본값에서는 플랫폼별 Remote Config를 읽는다. TestFlight 전용/비공개 테스트 전용 산출물에서 정식 스토어 안내를 빼려면 향후 빌드 시 `--dart-define=READER_UPDATE_CHANNEL=testing`을 명시한다. 이 모드에서는 조회와 안내를 모두 생략한다. 자동으로 TestFlight/Play 트랙을 판별하는 기능은 아니다.

동일 테스트 빌드를 정식 출시로 승격할 계획이면 `store` 모드로 만들고, 검증·출시 전까지 서버 스위치를 꺼둔다. 정식 출시 후 실제 설치 가능성을 확인하고 켠다. 운영 서버에서 실험 값을 전체 사용자에게 켜는 방식으로 UI 테스트를 하지 않는다. 이번 UI/로직 테스트는 가짜 설정으로 검증했다.

## 소스와 배포 관리

- `remoteconfig.template.json`: 최초 게시한 두 그룹과 키·한글 설명·기본값.
- `firebase.json`의 `remoteconfig`: 위 파일을 연결한다.
- `lib/features/updates/domain/update_policy.dart`: 버전 비교·최소 버전·스토어 주소 검증.
- `lib/features/updates/data/update_service.dart`: 프로세스 실행당 한 번 조회, 시간 제한, 설치 버전 확인.
- `lib/features/updates/presentation/startup_update_gate.dart`: 안내·나중에·스토어 이동.
- `lib/app/app.dart`: 개인정보 화면 이후 서재 진입 전 연결.

이번에는 Firebase CLI의 `deploy --only remoteconfig --project koofy-reader`로 **Remote Config만** 게시했다. Functions·Firestore·Storage 배포는 하지 않았다. 게시 후 서버 템플릿을 다시 받아 로컬 정의와 14개 키가 일치하는지 확인했다. 로그와 전후 템플릿은 `work/remote-config/`에 있다.

콘솔에서 값을 바꾼 뒤 오래된 로컬 템플릿을 그대로 배포하면 콘솔 변경을 덮어쓸 수 있다. 다음 배포 전에는 서버 템플릿을 먼저 받아 비교·병합한다. 키 이름은 코드와 연결되어 있으므로 임의로 바꾸거나 삭제하지 않는다. Remote Config 값은 앱이 읽을 수 있는 공개 설정이므로 비밀 키·비밀번호를 넣지 않는다.

## 개인정보 및 검증 범위

Remote Config SDK는 Firebase 설치 식별자를 이용한다. 앱의 한국어·영어 개인정보처리방침에 업데이트 확인 목적의 처리 안내를 추가했다. Analytics SDK, 개인화, 실시간 구독, A/B 실험을 활성화하지 않았다. iOS 종속성의 FirebaseABTesting 라이브러리는 Remote Config에 따라 설치되지만 실험을 구성하지 않았다. 외부 웹 방침과 스토어 개인정보 신고는 이번 작업에서 수정하지 않았으므로 다음 제출 전에 업데이트 내용을 맞춰 확인한다.

공식 근거: [Flutter 연동](https://firebase.google.com/docs/remote-config/flutter/get-started), [Firebase 개인정보 안내](https://firebase.google.com/support/privacy).

검증 결과: 업데이트 정책·서비스·UI, 기존 개인정보 화면, 앱 진입, 테마 관련 테스트 24개 및 Flutter 정적 분석 통과. 새 플러그인의 Dart 의존성과 iOS CocoaPods 의존성 설치 완료. Firebase 콘솔 구성 버전 1과 서버 템플릿 일치 확인 완료.

**이번 요청대로 앱 빌드는 만들지 않았다.** 실제 기기의 Remote Config 수신, Android/iOS 스토어 이동, 재시작·백그라운드 복귀는 다음 빌드의 실기기 테스트에서 확인한다. 기존 IPA는 새 기능을 포함하지 않는다.
