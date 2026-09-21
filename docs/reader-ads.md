# LevelPlay 광고와 2시간 리워드

## 구성

- Flutter 플러그인 `unity_levelplay_mediation 9.1.0`, 네이티브 LevelPlay `9.4.0`, Unity Ads 어댑터 `5.5.0`, Unity Ads `4.16.6`을 사용한다. iOS 어댑터 pod 표기는 `5.5.0.0`이다.
- 광고 공급원은 콘솔에 연결된 ironSource와 Unity Ads다. AdMob SDK·어댑터·직접 호출·App ID 설정은 제거했다.
- 키는 `lib/features/ads/config/levelplay_ids.dart`에 있다. SDK 초기화에는 App Key, 광고 객체에는 LevelPlay Ad Unit ID를 사용한다. Unity Ads Game ID/Placement ID는 콘솔 매핑용이다.

| 플랫폼 | App Key | 서재 배너 | 뷰어 배너 | 리워드 |
| --- | --- | --- | --- | --- |
| Android | 283bb581d | rd7fp4ib5ob9wxqa | 2dr1bupao7hqz66b | c3al5bjpm4gizhi5 |
| iOS | 283bb91a5 | ylwd5e3aw6xjman2 | f60hdb7l3a4o9fgt | jppve7gfp2mtrm44 |

## 동작

- 초기화 성공 후 광고 객체를 만든다. 광고 초기화가 독서를 오래 지연시키지 않도록 책을 열 때 최대 1초만 기다리며 준비되지 않으면 해당 독서 세션의 광고를 생략한다. 다음 책 열기에서 다시 확인한다.
- 네이티브 독서 화면을 여는 동안 Flutter 서재 배너는 제거한다. 뒤에 가려진 배너를 중복 요청하지 않는다.
- 네이티브 뷰어 하단은 광고 표시 중에만 320×50 배너와 16pt/dp 컨트롤 간격을 확보한다. 리워드 숨김 중에는 영역 높이가 0이 되어 본문이 확장된다. 광고 로딩·실패만으로는 높이를 바꾸지 않는다. 너비가 320보다 좁으면 광고를 요청하지 않는다.
- 숨김 적용·만료로 높이가 바뀌기 전에 읽던 문장 locator를 보존한다. Android는 기존 재배치 복원 흐름, iOS는 새 본문 높이에서 navigator 재생성을 통해 복원한다. 페이지 수나 페이지 시작은 달라질 수 있지만 같은 문장을 기준으로 복원한다.
- Flutter 서재·설정에서도 광고 영역과 광고용 SafeArea를 제거한다. 남은 시간 안내는 설정 본문에만 표시한다.
- 광고 영역 배경은 독서 테마를 따른다. 광고 소재의 색은 공급자가 결정한다.
- 정상 배너 자동 새로고침은 LevelPlay 콘솔 설정(현재 25초)을 따른다. 네이티브 footer의 60초 상태 확인은 보상 만료 및 실패 재시도를 위한 것으로, 이미 로드된 광고를 추가 요청하지 않는다.
- `onAdRewarded`에서만 로컬 만료 시각을 저장한다. 한 번 시청하면 2시간이며 이미 유효한 숨김 시간은 줄이거나 누적하지 않는다.
- 광고별 이벤트 리스너로 늦게 도착한 보상과 중복 보상을 처리한다. `onAdClosed`는 UI를 해제할 뿐 보상을 지급하지 않는다. 닫힌 뒤 도착한 보상도 설정 화면의 생존 여부와 무관하게 저장된다. 이미 열린 네이티브 뷰어에도 새 만료 시각을 전달한다.
- 설정에 남은 시간을 표시하고 숨김 기간 동안 재시청을 막는다. 앱 재실행 후에도 저장된 만료 시각을 사용한다.
- iOS는 SDK 정적 바이너리 연결을 위해 CocoaPods 정적 프레임워크를 사용한다. SKAdNetwork 목록은 Unity 공식 목록과 ironSource ID를 포함했다. 사용자 추적 동의를 임의로 true로 설정하지 않는다.

## 개발 기기 검증

```sh
flutter run --dart-define=LEVELPLAY_TEST_SUITE=true
# 또는 Android APK
./scripts/android_ads_build.sh debug apk
```

- 설정 화면의 `LevelPlay 광고 연동 테스트` 버튼으로 SDK 초기화 성공 후 테스트 도구를 연다.
- 이 플래그는 진단 도구를 활성화할 뿐 테스트 광고를 강제하지 않는다. 먼저 실제 기기를 LevelPlay 콘솔의 테스트 기기로 등록한다. 릴리스 빌드에서는 이 도구가 활성화되지 않는다.
- Unity Ads/ironSource 각각의 배너·리워드 로드와 표시를 확인한다.
- 서재 배너 → 책 열기 → 뷰어 배너 → 서재 복귀, 폴더블 접기/펼치기, 배경색 변경을 확인한다.
- 리워드 완료 → 모든 배너 숨김 → 앱 재실행 후 유지 → 만료 후 재표시를 확인한다. 중도 종료에는 보상을 지급하지 않는다.
- 인터넷이 없거나 광고가 채워지지 않아도 독서는 가능해야 한다.
- 실기기 광고 제공 여부·계정 승인·스토어 연결 상태는 빌드 성공만으로 검증되지 않는다. 이번 작업에서는 운영 광고 노출을 실행하지 않았다.

## 독서 설정

글자 크기 → 배경 → 읽기 방식(넘김 방식·페이지 배치·전환 효과) → 글꼴 순서다. 연속 스크롤에서는 페이지 배치·효과를 조작할 수 없으며 이전 선택은 유지한다.

## 공식 참고

- https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/plugin-integration
- https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/rewarded-ads-integration
- https://docs.unity.com/en-us/grow/levelplay/sdk/android/networks/guides/unity-ads
- https://docs.unity.com/en-us/grow/levelplay/sdk/ios/networks/guides/unity-ads
- SKAN 목록: https://skan.mz.unity3d.com/v3/partner/skadnetworks.plist.json

## 검증 결과

Flutter 전체 테스트 119개 통과. 마지막 보상 처리 정리 후 관련 테스트 8개 재통과. Android debug APK와 iOS 시뮬레이터 빌드, Flutter 정적 분석 통과. 실제 기기의 네트워크별 광고 로드·표시·보상은 테스트 기기 등록 후 확인해야 한다.

## 광고 영역 접기 검증

숨김·만료 때 Flutter 본문 높이 증가/복원 및 광고 여백 제거 테스트와 관련 리워드 테스트 7개 통과. Android·iOS 빌드 검증. 실기기에서 리워드 적용 후 책 열기, 이미 읽는 동안 만료, 접기/펼치기 및 이어읽기 위치를 확인해야 한다.

## 개인정보 및 광고 선택 (2026-09-21)

- 첫 실행은 `PrivacyGate`에서 명시적인 선택을 받는다. 선택이 없으면 LevelPlay를 초기화하지 않는다. 기존 설치도 선택 기록이 없으면 안내를 표시한다.
- **비맞춤형 광고**를 선택해도 독서를 계속하고 배너·선택형 리워드를 이용한다. 개인정보 설정 전달이 실패하면 광고 요청만 중단하고 독서는 허용한다.
- 맞춤형 광고는 앱 내 허용과 iOS ATT 허용이 모두 있어야 한다. Android에는 ATT를 요청하지 않는다. iOS ATT 미결정·거부·제한 시 개인화 신호를 false로 적용한다. ATT는 앱에서 맞춤형 광고를 직접 선택했을 때만 요청하고 재실행 시 재요청하지 않는다.
- `PrivacyService`가 로컬에 선택·시각·방침 버전을 저장한다. 정책 버전 변경 시 다시 선택한다. 서버 계정이나 동의 기록 업로드는 추가하지 않았다.
- 네이티브 9.4 API `setGDPRConsents`에 `UnityAds`, `IronSource`를 함께 전달한다. 비맞춤형은 두 값 false, `setCCPA(true)`로 처리한다. CCPA true는 판매·공유 거부를 뜻한다. Flutter 9.1의 이전 `setConsent` API 대신 작은 네이티브 채널을 사용한다.
- 설정 > 개인정보 및 광고에서 선택을 변경한다. 변경 시 기존 Flutter 배너를 제거하고 새 선택으로 만든다. 앱 복귀 시 ATT를 다시 확인한다. 네이티브 iOS 독서 화면에서도 ATT 상태가 바뀌면 기존 광고를 버리고 거부 상태를 반영한 후 재개한다.
- 비맞춤형은 개인정보를 전혀 처리하지 않는다는 의미가 아니다. IP, 기기·앱 정보, 광고 이벤트 등 제공·보안에 필요한 처리를 방침과 선택 화면에 안내한다.
- 광고 보상은 기존 `onAdRewarded` 처리 그대로다. 추적 동의 자체에 보상을 제공하지 않는다.

## 방침과 문의 운영

- 앱 오프라인 방침: `assets/legal/reader_privacy.json`
- Quiz_Site 웹 원본 사본: `lib/legal/koofyReaderPrivacy.json` — 내용 변경 시 두 파일을 함께 갱신한다.
- 공개 경로: `https://www.koofy.co.kr/koofy-reader/privacy`, `https://www.koofy.co.kr/koofy-reader/support`
- 웹은 한국어·영어를 제공한다. 앱은 한국어 안내와 오프라인 방침, 웹 최신본 링크를 제공한다.
- 대표 메일: `koofylab@gmail.com`. 문의/광고 신고 화면은 메일 초안만 열며 본문·독서 기록을 자동 첨부하거나 자동 발송하지 않는다. 메일 앱이 없으면 표시된 주소를 복사해 사용한다.
- iOS `NSUserTrackingUsageDescription`과 앱 `PrivacyInfo.xcprivacy`를 추가했다. 앱 전용 파일 시각 조회(C617.1), 앱 설정 UserDefaults(CA92.1)를 선언했다. 각 SDK의 개인정보 manifest도 최종 번들에서 별도로 포함된다. 이것이 App Store Connect 개인정보 답변을 대신하지는 않는다.

## 출시 전 남은 확인

1. Quiz_Site를 배포하고 두 공개 URL이 로그인 없이 열리는지 확인한다. 앱 코드는 최신 버전으로 재설치한다. 이 변경만을 위해 Firebase Functions를 배포할 필요는 없다.
2. 테스트 기기에서 최초 비맞춤형 선택, iOS ATT 허용/거부, 재실행, 설정에서 철회, 기기 설정 변경 후 복귀, 오프라인 독서와 문의 메일 초안을 확인한다. 실제 광고 요청 신호와 각 네트워크의 표시·리워드 지급은 LevelPlay 테스트 기기로 검증한다.
3. 배포 국가를 정한 뒤 해당 지역의 동의 요건과 광고 네트워크 요구사항을 점검한다. 이 자체 선택 화면은 인증 CMP/TCF를 구현한 것이 아니므로 모든 지역의 요구를 충족했다고 간주하지 않는다. 네트워크를 추가하면 동의 전달 대상과 방침도 같이 갱신해야 한다.
4. Apple/Google 콘솔에서 개인정보 URL·지원 URL·데이터 수집/공유·광고·추적·연령 등 실제 동작에 맞는 답변을 등록한다. iOS 서명·프로비저닝·수출 규정 답변과 App Review 제출은 별도다.
5. 배포하는 도서·표지·폰트의 재배포 권한, 문의 처리·삭제 운영 방침은 운영자가 확인한다. 코드에서 확인되지 않은 보유 일수나 권한을 임의로 확정하지 않았다.

공식 기준: [Unity 9.4 동의 설정](https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/regulation-advanced-settings), [Apple 개인정보 및 추적](https://developer.apple.com/app-store/user-privacy-and-data-use/), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### 이번 변경 검증

2026-09-21 기준 `flutter analyze lib test` 오류·경고 없음, Flutter 전체 152개 테스트 통과. 최초 미선택 상태의 광고 차단, 비맞춤형 선택 후 진입, ATT 거부/외부 철회, 저장·네이티브 설정 실패, 320px 큰 글씨 안내와 오프라인 방침 이동을 검증했다. Android debug APK 및 iOS 서명 없는 release 빌드가 통과했고, 양쪽 번들의 최신 방침 자산과 iOS ATT 설명·앱 privacy manifest 포함을 확인했다. Quiz_Site 타입 검사·production 빌드 통과, 로컬 브라우저 360/1280px에서 한국어·영어 전환, 메일 링크 및 가로 넘침 없음을 확인했다. 웹 배포와 실제 기기 ATT/광고 신호 검증은 수행하지 않았다.
