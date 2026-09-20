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
