# 페이지 전환 효과 — 구현 전 재검수

검수일: 2026-09-20
상태: 구현 전 검토 기록. 아래 항목은 검토 당시의 설계와 합격 기준이다.
후속 구현과 실제 검증 결과는 [페이지 전환 효과 구현](page-turn-implementation.md)을 참조한다.
범위: 보기 설정의 `바로 넘기기 / 책장 넘기기`, 실제 본문 양면 표현, 손가락 추적, 단면·펼침 전환.
초기 지원 콘텐츠는 현재 리더와 동일한 비보호 리플로우 EPUB이다. 고정 레이아웃·PDF·DRM을 이번 기능 때문에 새로 지원한다고 가정하지 않는다.

## 결론

구현 가능한 기능이지만 현재 Readium의 설정 하나로 제공되지는 않는다.
Flutter와 Readium의 본문 레이아웃을 유지하고, 네이티브 페이지 공급·터치 제어·전환 상태 관리를 확장한다.
Android OpenGL ES와 iOS Metal을 처음부터 필수로 확정했던 제안은 수정한다.
실제 페이지 공급이 성립하는지 먼저 검증하고, 렌더러는 필요한 표현과 측정 결과에 따라 선택한다.

## 코드에서 확인한 사실

- Android: Readium Kotlin 3.1.2. ReaderActivity가 EpubNavigatorFragment를 직접 호스팅한다.
- iOS: Readium Swift 3.11.0. KoofyReaderViewController가 EPUBNavigatorViewController를 직접 호스팅한다.
- 양쪽 모두 공개 설정에서 현실적인 양면 페이지 컬을 켜는 옵션은 발견되지 않았다.
- 주변 publication position/HTML 리소스의 preload는 완성된 화면 페이지 bitmap 캐시와 다르다.
- Android 공개 JavaScript 실행은 현재 HTML에 한정되며, 주변 리소스와 내부 pager는 앱에서 자유롭게 접근할 수 있는 공개 인터페이스가 아니다.
- iOS EPUBSpreadView의 WKWebView와 PaginationView는 내부 구현이다. snapshotView는 UIView 복사본이며 GPU 텍스처를 공급하는 API가 아니다.
- 공개 drag 관찰 API만으로 두 플랫폼의 기존 WebView/scrollView 이동이 차단된다고 볼 수 없다.
- Android applyReaderPreferences는 scheduleRelayout을, iOS apply는 navigator 재생성을 수행한다. 전환 효과만 바꾸는 경우 이 경로를 그대로 쓰지 않는다.
- 독서 설정은 현재 publication ID와 content revision별 preferences_json에 저장된다. 앱 전체 공통 설정이라고 가정하지 않는다.
- 네이티브 복구 저널과 Flutter DB는 모두 ReaderPreferences의 필드를 직렬화한다. UI 필드만 추가하면 재실행·복구에서 누락된다.

주요 근거 파일:

- `pigeons/reader_api.dart`
- `lib/features/native_reader/data/native_reader_store.dart`
- `packages/koofy_reader_bridge/android/src/main/kotlin/com/koofy/reader/bridge/ReaderActivity.kt`
- `packages/koofy_reader_bridge/android/src/main/kotlin/com/koofy/reader/bridge/ReaderCheckpointJournal.kt`
- `packages/koofy_reader_bridge/ios/Classes/KoofyReaderViewController.swift`
- `packages/koofy_reader_bridge/ios/Classes/ReaderCheckpointStore.swift`
- 고정된 Readium 소스의 Android R2WebView/EpubNavigatorFragment, iOS EPUBSpreadView/PaginationView

## 수정한 설계

### 1. 페이지 공급

각 이미지에는 정확한 원본/대상 Locator, 본문 영역, 읽기 방향, 레이아웃 세대 번호를 묶는다.
단순히 전역 페이지 번호를 증가시켜 목표 위치를 추정하지 않는다.

미리보기용 페이지 생성은 현재 독서 위치와 복구 저널에서 분리한다.
현재 navigator를 임시로 앞뒤로 이동시킨 뒤 되돌리는 방식은 기본안으로 채택하지 않는다.
내부 페이지 렌더링을 재사용할 수 있는 제한된 Readium 확장을 우선 검토한다.
별도 preview navigator가 필요하면 동일한 viewport/CSS/폰트/본문 정책을 보장하고,
추가 WebView의 메모리·로딩·실제 캡처 가능성까지 실험해야 한다.

숨기거나 화면 밖으로 이동시킨 WebView를 캡처하면 정상 이미지가 나온다고 가정하지 않는다.
Android postVisualStateCallback은 뷰 부착·표시 조건이 있으며 PixelCopy는 실제 표면 내용을 복사한다.
iOS takeSnapshot도 현재 설정에서 실제 페이지가 렌더링되는지 확인해야 한다.
고정 delay만으로 준비 완료를 판단하지 않고 폰트/그림/레이아웃 및 시각적 준비 완료를 확인한다.

펼침 화면은 실제 두 열 viewport 전체를 렌더링하고 엔진의 column/gutter 영역으로 분리한다.
반쪽 너비의 독립 WebView 두 개로 다시 배치하면 원래 줄바꿈·페이지 경계와 달라질 수 있다.

이미지는 메모리에만 보관한다. 네이티브에서 GPU로 전달하며 Flutter 채널로 매 프레임 이미지를 전송하지 않는다.
캐시 키에는 publication revision, Locator, viewport pixel size, density, 열 수, font/theme/layout revision을 포함한다.
세대가 바뀌면 늦게 도착한 이전 캡처 결과를 폐기한다.

### 2. 전환 제어

제안 상태 흐름:

`idle → dragging → settling → committing → idle`

- 취소: `dragging/settling → idle`, 기존 확정 Locator 유지.
- 완료: 실제 navigator가 목표 본문을 표시했음을 확인한 뒤 위치 기록 갱신.
- 미리보기 렌더링 이벤트는 사용자 독서 이벤트로 저장하지 않는다.
- 종료/백그라운드/회전/접힘은 상태별로 정리하며, 미완료 목표를 저장하지 않는다.
- 중복 탭·빠른 반대 방향 드래그에 대한 중복 이동을 막는다.
- 다른 세션 또는 이전 레이아웃의 완료 콜백은 무시한다.

기존 journal → Flutter DB commit → ACK 흐름은 유지한다.
새 전환 상태를 기존 복구 이벤트의 sequence/generation 검증과 연결해야 한다.

### 3. 터치와 바로 넘기기

탭, 스와이프, 이전/다음 버튼, 키보드·접근성 이동을 하나의 전환 정책으로 연결한다.
`goForward(animated=false)`만 바꾸고 Readium의 자체 스와이프를 남기는 것은 완전한 바로 넘기기가 아니다.
드래그 중 기존 pager가 동시에 움직이지 않도록 명시적인 제어 지점을 마련한다.
텍스트 선택과 링크 동작은 그대로 유지하며, 모퉁이/가장자리 드래그와 본문 long-press를 구별한다.
시스템 뒤로가기·홈 제스처를 가로채지 않는다.

### 4. 보기 설정

- 이름: 페이지 전환 효과.
- 옵션: 바로 넘기기 / 책장 넘기기.
- 기본값: 바로 넘기기.
- 연속 스크롤에서는 책장 효과를 적용하지 않으며 선택값은 보존한다.
- 효과만 변경하면 재페이지네이션과 navigator 재생성을 하지 않는다.
- 기존 저장 범위를 유지하는 최소 패치는 책별 저장이다. 앱 공통으로 바꾸는 경우 별도 정책·저장소가 필요하다.
- Pigeon 원본, 생성된 Dart/Kotlin/Swift, 네이티브 저널, DB JSON, 기본값·검증·테스트를 함께 변경한다.
- 기존 기록에 신규 필드가 없으면 바로 넘기기로 읽는다. 기존 Locator는 유지한다.
- 신규 스타일 설정은 실제 효과가 제공되는 빌드에서만 사용자 메뉴에 노출한다.

### 5. 단면과 펼침의 양면 규칙

펼침 LTR 예시: [10,11] → 앞면 11/뒷면 12 → 완료 [12,13].
이 숫자는 예시이며 EPUB의 인쇄 쪽 번호 또는 고정된 전역 페이지 번호를 뜻하지 않는다.
장 경계에서 빈 칼럼이나 spread가 생기면 엔진이 만든 실제 슬롯을 따른다.
RTL 출판물은 이전/다음 및 접힘 방향을 읽기 방향에 따라 매핑한다.

단면은 1회 완료에 한 화면씩 진행한다. 펼침의 두 쪽 증가 규칙을 재사용하지 않는다.
단면에서 뒷면에 새 본문을 표시하는 연출은 아래에 드러날 다음 본문과 중복될 수 있다.
POC에서 단면용 앞/뒤/아래 매핑을 명시하고, 모든 쪽이 순서대로 한 번씩 도달되는지 검증한다.
단면의 뒷면 미리보기는 읽기 진행을 확정하지 않으며 렌더러가 임의로 두 쪽 이동하지 않는다.

## 렌더러 선택

| 플랫폼 | 첫 검증 대상 | 고급 대안 |
|---|---|---|
| Android | Canvas의 경로·클리핑·bitmap mesh로 요구한 곡면/양면을 표현 가능한지 확인 | OpenGL ES: 독립 양면 텍스처, 곡면 메시, 그림자 제어 |
| iOS | UIKit UIPageViewController.pageCurl + isDoubleSided | Metal: 손가락 위치·곡률·그림자의 세밀한 제어 및 양 플랫폼 표현 통일 |

Canvas는 2D 메시 API이지 자동 종이 물리 엔진이 아니다. 양면·겹침·그림자는 별도 구현이 필요하다.
UIKit pageCurl은 Readium에서 직접 제공하는 옵션이 아니므로 페이지 공급·입력 연결 문제는 별도로 해결해야 한다.
UIKit의 기본 제스처가 정확한 손가락 추적·모퉁이 제어 요구를 충족하는지도 확인한다.
iOS 설치 SDK 헤더에서는 pageCurl, isDoubleSided, spine, 완료와 취소를 구분하는 delegate를 확인했다.
따라서 UIImage 페이지 공급 POC에는 UIKit을 먼저 사용하고, 곡률·그림자·플랫폼 간 일치 요구를 충족하지 못하면 Metal로 교체하는 순서를 추천한다.
단순 평면 회전 효과가 동작했다고 현실적 페이지 컬이 검증됐다고 하지 않는다.
표현 제어가 부족하거나 성능 측정 결과가 나쁘면 GPU 구현으로 진행한다.

## 패치 단계 및 합격 기준

### A. 페이지 공급 기술 검증

앱의 프로덕션 읽기 경로를 바꾸기 전에 다음을 확인한다.

- Android/iOS 각각 실제 EPUB에서 현재·이전·다음 화면을 정확한 이미지와 Locator로 공급.
- 단면·펼침, 장 경계, 긴 한글 문단, 삽화, 늦은 폰트 로딩 검증.
- preview 생성 전후 현재 본문·lastLocator·journal·Flutter DB 위치가 동일.
- 글자 크기·테마·회전·접힘 이후 이전 세대 이미지는 사용되지 않음.
- 이미지 생성 실패/취소/메모리 부족에 대한 기본 전환 경로 확보.

### B. 전환 구현과 통합

위 합격 기준을 만족하는 provider를 사용해 드래그, 복귀, 양면 렌더링을 구현한다.
보기 메뉴, 설정 저장, 효과만 바꾸는 경로, 기본 전환을 함께 연결한다.
Readium 수정이 필요하면 버전 고정된 fork 또는 재현 가능한 patch로 관리한다.
Pods나 Gradle 캐시를 직접 수정한 상태를 최종 구현으로 남기지 않는다.

### C. 기능·성능 검증

- 취소/완료/빠른 역방향/연속 이동/책 끝/장 경계에서 본문 누락·중복 이동 없음.
- 펼침·단면 전환, 글자 크기 변경, 재열기 반복에서 기존 문자 위치 보존.
- 양 플랫폼에서 스크롤·텍스트 선택·링크·접근성 및 동작 줄이기 회귀 확인.
- 기존 기록의 신규 필드 누락, 신규 기록 복구, 오래된 이벤트, ACK 경합 테스트.
- 최초 본문 시간, 준비된 페이지의 입력-첫 프레임 지연, 캡처 시간 p50/p95, 프레임 누락, 최대 메모리, fallback 횟수 측정.
- 60Hz에서 16.7ms는 목표 프레임 예산이다. 현재 달성한 측정치가 아니며 120fps를 보장하지 않는다.
- 시뮬레이터 결과만으로 폴더블 실기기 성능을 판정하지 않는다.
- curl 시작 전에 이미지 준비 여부를 판단한다. 이미 시작된 드래그 중에는 갑자기 기본 넘김으로 교체하지 않는다. 진행 중 자료가 무효화되면 취소·재배치 정책으로 정리한다.
- 이미지 준비가 안 된 경우의 기본 전환은 예외 처리다. 대부분 기본 전환으로 빠지는 구현을 책장 기능 완료로 판정하지 않는다.

## 참고

- Android WebView visual state: https://developer.android.com/reference/android/webkit/WebView#postVisualStateCallback(long,%20android.webkit.WebView.VisualStateCallback)
- Android PixelCopy: https://developer.android.com/reference/android/view/PixelCopy
- Android Canvas: https://developer.android.com/reference/android/graphics/Canvas
- Apple UIKit page curl: https://developer.apple.com/documentation/uikit/uipageviewcontroller/transitionstyle-swift.enum/pagecurl
- Apple double-sided: https://developer.apple.com/documentation/uikit/uipageviewcontroller/isdoublesided
- Apple 앞뒤 페이지 공급 규칙: https://developer.apple.com/documentation/uikit/uipageviewcontroller/setviewcontrollers(_:direction:animated:completion:)
- Apple WKWebView snapshot: https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot(with:completionhandler:)
