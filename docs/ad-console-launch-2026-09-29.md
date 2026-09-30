# 광고 콘솔 출시 연결 기록 — 2026-09-29

## 완료 범위

Chrome에 로그인된 Koofy 계정의 콘솔에서 설정하고 저장 결과를 확인했다. 최초 콘솔 작업에 이어 같은 날 앱 SDK·동의 처리를 구현했다. 기존 미커밋 변경을 보존했으며 스토어 업로드·배포는 하지 않았다.

- LevelPlay iOS 앱 `283bb91a5`: Temp → Live app, App Store URL 연결. 표시 이름은 `쿠피리더 - 텍스트 뷰어, TTS`, 분류는 Non-Gaming / Lifestyle: Books & Reference. COPPA Not directed 유지.
- Unity Ads iOS Game ID `800377536`: Store ID `6814514729` 저장.
- App Store URL: https://apps.apple.com/kr/app/id6814514729
- AdMob iOS 앱을 신규 등록하고 해당 Apple 앱에 연결했다. 앱 인증/광고 게재 준비는 아직 완료되지 않았다.
- AdMob Android 기존 앱은 유지했다. Android 공개 스토어 출시 여부는 이번 작업에서 검증하지 않았으며, 스토어 연결 상태를 임의로 출시 완료로 바꾸지 않았다.

## AdMob → LevelPlay 입찰 매핑

아래 광고 단위는 모두 **파트너 입찰** 옵션으로 생성했다. 앱은 기존 LevelPlay App Key / Ad Unit ID를 계속 사용하며 아래 ID를 직접 광고 호출에 사용하지 않는다.

| 항목 | Android | iOS |
|---|---|---|
| LevelPlay App Key | `283bb581d` | `283bb91a5` |
| AdMob App ID | `ca-app-pub-5773331970563455~3449808968` | `ca-app-pub-5773331970563455~6582912109` |
| 배너 Ad Unit ID | `ca-app-pub-5773331970563455/6558861372` | `ca-app-pub-5773331970563455/3465794176` |
| 리워드 Ad Unit ID | `ca-app-pub-5773331970563455/7213467493` | `ca-app-pub-5773331970563455/5829242795` |
| 배너 이름 | `levelplay_banner_android` | `levelplay_library_banner_ios` |
| 리워드 이름 | `levelplay_hide_ads_rewarded_android` | `levelplay_hide_ads_rewarded_ios` |

LevelPlay의 **Google / Bidding**에 각 App ID와 `koofy_banner`, `koofy_rewarded` 인스턴스를 저장했다. 두 플랫폼 모두 **비활성**이다. 비활성화 후 Mediation groups는 `Select`로 표시된다. 활성화 시 배너는 서재·뷰어 두 그룹, 리워드는 해당 리워드 그룹에 다시 배정해야 한다. iOS 배너 이름에 library가 있지만 서재·뷰어 공급용 공통 네트워크 광고 단위로 준비했다.

기존 Android 직접 호출용 배너 `6778679885`, 리워드 `7773760450`은 삭제하거나 변경하지 않았다. 이번 입찰 매핑에는 사용하지 않는다.

## 광고 차단

AdMob 각 쿠피리더 앱 수준에서 다음을 저장했다. 다른 앱이나 계정 전체 제한을 변경하지 않았다.

- 계정 수준 등급 상속을 끄고 **PG**로 제한: T / MA 차단.
- **소셜 카지노 게임** 차단.
- 기존 **도박 및 베팅(만 18세 이상)** 및 **주류** 차단 유지.
- iOS에서 PlayOJO Canada (`1202888212`), Lightning Link Casino-Slots (`1243005112`) 앱 설치 광고 차단 저장.

기존 Unity Ads/LevelPlay의 iOS 심사 대응 제한은 유지했다. 기존 ironSource iOS 비활성, Unity Ads 활성 구성을 바꾸지 않았다. 필터 설정은 부적절한 광고가 절대 나오지 않는다는 보장은 아니므로 실제 광고 검수가 필요하다.

## 인증 확인과 남은 작업

### iOS 앱 인증

- AdMob에서 app-ads.txt 검증 실패/미완료 상태를 확인했다.
- 공개 `https://www.koofy.co.kr/app-ads.txt`는 HTTP 200이며 다음 항목을 포함한다.
  - `google.com, pub-5773331970563455, DIRECT, f08c47fec0942fa0`
  - `unity.com, 92158281, DIRECT, 96cabb5fbdde37a7`
- 공개 App Store 페이지에서 Developer Website 링크를 찾지 못했다. 개발자 웹사이트 연결 누락 또는 크롤링 반영 문제가 의심되지만 검증 실패의 단일 원인으로 확정하지 않았다.
- 출시된 1.0.0에서는 Marketing URL 편집이 잠겨 있어 **1.3.0 업데이트 초안**을 생성하고 `https://www.koofy.co.kr/koofy-reader`를 저장했다. 새 빌드 연결·심사 제출은 하지 않았다. 공개 스토어에는 업데이트 승인·출시 후 반영되므로 현재 인증 해결로 간주하지 않는다.
- 스토어 반영 후 AdMob에서 인증을 재시도하고 앱 준비 상태를 확인한다.

### SDK와 동의 처리 — 구현 및 빌드 검증

- LevelPlay 9.4.0과 Unity Ads 어댑터 5.5.0을 유지하고 AdMob 어댑터 5.4.0을 추가했다. Android Google Mobile Ads 24.9.0 / UMP 4.0.0, iOS Google Mobile Ads 12.14.0 / UMP 3.1.0이다. iOS pod 버전은 AdMob 어댑터 5.4.0.0이다.
- Android Manifest / iOS Info.plist에 위 플랫폼별 AdMob App ID 및 측정 초기화 지연 설정을 추가했다. Google SKAdNetwork ID `cstr6suwn9.skadnetwork`는 기존 iOS 목록에 있다. 전체 파트너 목록의 최신성 검증을 완료한 것으로 간주하지 않는다.
- AdMob 광고를 별도로 만들거나 직접 초기화하지 않는다. 배너·리워드는 기존 LevelPlay 지면과 2시간 보상 처리를 유지한다. 초기화 전 AdMob 최대 등급을 PG로 전달한다.
- 앱 최초 광고 준비 시 Google UMP 상태를 갱신하고 필요한 지역 양식을 표시한다. `canRequestAds`가 false면 모든 광고 요청을 막지만 독서는 가능하다. 한 실행 안에서 중복 요청·실패 재시도 루프를 막고 설정에서 명시적으로 재시도한다.
- 설정에 지역별 개인정보 선택 진입점을 필요할 때 표시한다. 선택 화면을 열기 전에 기존 광고를 제거하고 결과로 다시 구성한다. 기존 ATT 중립 안내와 OS 권한 결정을 유지하며 UMP IDFA 안내는 만들지 않았다. 네이티브 iOS 독서 화면에서 OS 추적 권한을 철회한 뒤 복귀할 때도 AdMob을 포함한 세 공급원에 거부를 전달한다.
- **보수적인 개인화 정책:** UMP `OBTAINED`에는 거부도 포함되므로 이를 개인화 동의로 해석하지 않는다. 동의와 개인정보 선택이 모두 `NOT_REQUIRED`인 경우에만 기존 앱 선택·ATT 허용을 추가 확인해 개인화한다. CMP 적용 지역에서는 허용 응답을 해도 현재 구현은 비맞춤형 광고로 제한한다. `UnityAds`, `IronSource`, `AdMob` 세 공급원에 같은 제한을 전달한다.
- 기존 로컬 사용자 선택의 저장 키와 동의 버전은 유지했다. 문서 갱신일만 2026-09-29로 변경했다. 도서·설정·리워드 기록 마이그레이션은 없다.

### AdMob 개인정보 메시지

쿠피리더 Android/iOS 두 앱만 연결해 게시 완료했다. 다른 앱 메시지는 수정하지 않았다.

| 이름 | 범위 | 설정 |
|---|---|---|
| Koofy Reader - European consent | EEA·영국·스위스 | 동의·동의하지 않음·선택 관리. 거부 버튼은 모든 해당 지역에서 표시. 기본 언어 영어(en). |
| Koofy Reader - US privacy choices | 현재 및 향후 지원 미국 주 | 판매·공유 거부 선택. 기본 언어 영어(en-US). |

두 앱 개인정보 URL은 `https://www.koofy.co.kr/koofy-reader/privacy`로 저장했다. 현재 콘솔의 유럽 메시지 언어 목록에 한국어가 없어 한국어 메시지를 추가하지 않았다. 기본 광고 파트너 목록은 유지했으며 계정 전체 파트너 설정은 변경하지 않았다. 메시지 게시가 실제 기기 표시·모든 지역의 준수 검증을 뜻하지는 않는다.

### 문서 및 남은 배포 순서

1. 앱 방침 `assets/legal/reader_privacy.json`과 Quiz_Site의 `lib/legal/koofyReaderPrivacy.json`에 AdMob·UMP 및 선택 변경 내용을 반영했다. **웹 소스만 변경했으며 웹 배포는 아직 하지 않았다.**
2. 테스트 기기를 등록하고 지역별 양식, ATT 허용/거부, 선택 철회, 네트워크 실패, 광고 no-fill, 배너·리워드와 2시간 보상을 실기기로 확인한다. 실제 운영 광고를 클릭하지 않는다.
3. 웹 방침을 배포하고 스토어 개인정보 답변을 새 SDK 실제 동작과 대조한다. 새로운 서명 빌드를 만들어 검증 후 배포한다. 현재 iOS 1.3.0 초안에는 빌드를 연결하지 않았다.
4. 공개 Apple 개발자 웹사이트 반영 후 AdMob 앱 인증을 재시도한다. 인증·기기 테스트가 끝나면 SDK가 없는 구버전의 영향도 고려해 Google 입찰 그룹 배정과 활성화를 진행한다.

### 이번 검증 범위

- `flutter analyze lib test`: 오류·경고 없음.
- 개인정보 서비스·화면, 광고 영역, 리워드 관련 **35개 테스트 통과**. UMP 미완료 차단, 거부 시 개인화 방지, 명시적 재시도, 중복 선택 화면 방지·철회 등을 포함한다.
- Android debug 및 iOS 서명 없는 release 빌드 검증. Android 최초 빌드의 package_info_plus 산출물 누락은 해당 모듈을 재생성해 해결했다.
- 실기기 UMP 표시·AdMob 광고 로드/보상, 앱 인증 완료, 배포 서명·스토어 업로드는 아직 검증하지 않았다.

### 되돌리기

AdMob 인스턴스는 이미 비활성 상태여서 현재 광고 공급에 참여하지 않는다. 향후 문제가 생기면 Google 인스턴스만 비활성화해 기존 Unity Ads 공급을 유지한다. 생성한 ID는 기록을 남기고 즉시 삭제하지 않는다. 광고 차단 제한은 출시·심사 후에도 완화하지 않는다.

## 공식 참고

- https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/networks/guides/google-bidding
- https://support.google.com/admob/answer/14538460?hl=ko
- https://support.google.com/admob/answer/9363762

콘솔 저장 상태와 메시지 게시 상태를 확인했다. 새 SDK 빌드 검증과 실제 기기 광고 노출 검증은 위와 같이 구분한다.

- https://developers.google.com/admob/android/privacy
- https://developers.google.com/admob/ios/privacy

## 후속 배포 완료 기록 (2026-09-29)

위 초기 작업 시점의 미완료 항목 중 다음을 완료했다.

- 웹 방침 한 파일을 별도 커밋 `53e519a28986a4c94410192e87c99ecc03b18d78`으로 기록했다. 자동 push는 인증 실패했고 사용자가 직접 push를 완료했다. 공개 https://www.koofy.co.kr/koofy-reader/privacy 에서 2026-09-29 및 AdMob·UMP 안내를 확인했다.
- Android 1.3.1(8) 배포 서명 AAB 검증·업로드 및 기존 비공개 Alpha 게시 요청 완료. 데이터 보안의 진단 공유 목적을 보완해 함께 제출했다. 현재 사전 검사·검토 대기이며 승인 후 자동 게시된다.
- iOS 1.3.0(10) 배포 서명 IPA 검증·Xcode 업로드·수출 규정 답변·빌드 연결·최종 심사 접수 완료. 제출 ID `6f91000b-848a-4734-9cec-0248f84fe4f4`, 심사 대기 중이다. Apple 개인정보 신고에 충돌·기타 진단 데이터도 추가 게시했다.
- Google AdMob 공급원은 여전히 비활성이다. 실기기 지역별 UMP·ATT·광고·보상 검증 및 AdMob 앱 인증/활성화는 별도 후속 작업이다.
- 상세 산출물·해시·검증 기록은 `android-release.md`, `ios-release.md`를 따른다.
