# iOS 출시 준비

## 앱 등록 정보

2026-09-21 Apple Developer와 App Store Connect에서 등록을 확인했다.

| 항목 | 값 |
| --- | --- |
| App Store 이름 | 쿠피리더 |
| 플랫폼 / 기본 언어 | iOS / 한국어 |
| Bundle ID | `com.koofylab.koofyreader` |
| Apple App ID | `6814514729` |
| SKU | `koofy-reader-ios` |
| Developer Team | `W8A4759K5F` (Namho Choi) |

[App Store Connect 앱 정보](https://appstoreconnect.apple.com/apps/6814514729/distribution/info)

## 프로젝트 서명

`ios/Runner.xcodeproj/project.pbxproj`의 Runner 및 RunnerTests에 위 Team을 연결했다. Debug, Profile, Release는 자동 서명을 사용한다.

검증 결과:

- `plutil -lint ios/Runner.xcodeproj/project.pbxproj`: 통과.
- `git diff --check`: 통과.
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -showBuildSettings`: 자동 서명, Team ID, Bundle ID 일치 확인.
- Mac에서 해당 Team의 유효한 Apple Development 서명 인증서를 확인했다. Apple Distribution 서명 인증서는 이번 점검에서 확인되지 않았다.

## 남은 작업

2026-09-21 `1.0.0 (1)` 아카이브 생성과 App Store Connect 업로드에 성공했다. Apple의 빌드 처리 및 TestFlight 그룹 연결 결과는 아래 기록을 확인한다. App Store 심사 제출은 별도 작업이다.

1. 계정 소유자가 Apple Developer의 새 계약을 직접 검토하고 동의한다. 작업 당시 계약 갱신 알림이 표시돼 있었다.
2. `ios/Runner.xcworkspace`를 Xcode에서 열어 계정과 자동 서명을 확인하고, 실제 iPhone에서 실행한다.
3. 서재, 파일 가져오기, 페이지 넘김, 읽던 위치 복원, 광고 동의/ATT 및 리워드 보상을 실제 기기에서 확인한다.
4. `pubspec.yaml`의 버전과 빌드 번호를 확인하고 프로젝트 루트에서 `flutter build ipa --release`를 실행한다. 배포 서명과 프로비저닝이 성공했는지 결과를 확인한다.
5. 생성된 아카이브/IPA를 확인한 뒤 App Store Connect에 업로드하고 TestFlight에서 검증한다.
6. 스크린샷, 설명, 지원/개인정보 URL, 앱 개인정보, 연령 등급, 콘텐츠 권한 및 수출 규정 정보를 실제 동작과 배포 콘텐츠에 맞춰 작성한다.

신규 앱 레코드의 버전은 기본값 `1.0`이다. 제출 전에 빌드의 버전과 맞춘다. 심사 정보의 기본 ‘로그인 필요’ 설정도 계정 로그인이 없는 현재 앱에 맞춰 수정하고 출시 방식을 확인한다. 암호화 신고는 사용 중인 라이브러리까지 검토한 뒤 결정한다.

업데이트할 때에는 Bundle ID와 Team을 유지하고, 업로드할 빌드 번호를 증가시킨다. App Store Connect 앱 레코드를 다시 만들 필요는 없다.

## 2026-09-21 TestFlight 업로드 기록

- `flutter build ipa --release`: `build/ios/archive/Runner.xcarchive` 생성 성공(228.0 MB). 버전 `1.0.0`, 빌드 `1`, 최소 iOS `15.0`, 아키텍처 `arm64` 확인.
- 아카이브 내부 앱에 `codesign --verify --deep --strict` 검증 통과(시스템 인증서 저장소 접근 권한 필요).
- 최초 IPA 내보내기는 Xcode 계정 미등록으로 실패했다. 사용자가 Xcode > Settings > Apple Accounts에서 기존 개발자 계정으로 로그인했다.
- 기존 아카이브에 `xcodebuild -exportArchive -allowProvisioningUpdates`를 실행해 자동 배포 서명 및 업로드 성공: `Upload succeeded`, `EXPORT SUCCEEDED`.
- 내보내기 옵션: `method=app-store-connect`, `destination=upload`, `signingStyle=automatic`, `teamID=W8A4759K5F`, `manageAppVersionAndBuildNumber=false`, `uploadSymbols=true`.
- 업로드 성공 후 동일 아카이브를 `destination=export`로 별도 내보내 로컬 IPA `build/ios/ipa/koofy_reader.ipa`도 생성했다. 파일 크기 36,097,724 bytes, ZIP 무결성 검사 통과, SHA-256 `43ea37559d1df325d27acdfb8fe67fc042100fdb7d45f3242f3ed7b97a428fd0`. 아카이브는 `build/ios/archive/Runner.xcarchive`에 있다.
- 내부 그룹 `쿠피리더 내부 테스트` 생성. 향후 빌드 자동 배포는 끄고 검증할 빌드를 직접 추가하는 방식이다.
- 계정 소유자 본인을 내부 테스터 1명으로 추가했다.
- 로컬 IPA의 `codesign --verify --deep --strict` 검증 통과. `beta-reports-active=true`, `get-task-allow=false`, Team 및 앱 식별자 일치 확인.
- 업로드 성공 후 App Store Connect에서 아직 빌드가 표시되지 않아 내부 그룹에 빌드를 연결하지 못한 상태다. 빌드 처리 결과 또는 Apple의 처리 오류 메일 확인이 필요하며, 현재 상태를 ‘TestFlight 설치 가능’으로 간주하면 안 된다.
- 2026-09-22 Xcode Organizer의 **Validate App**을 직접 실행해 `koofy_reader 1.0.0 (1) validated — Your app successfully passed all validation checks.` 결과를 확인했다. 업로드 전 검증 성공과 Apple의 업로드 후 처리 완료는 별개다.
- 최초 업로드 Delivery UUID: `1a08e15e-ab09-4e38-a78a-983f30a31588`, 전송 완료 시각: 2026-09-21 23:16 KST. Apple 지원 문의 시 앱 ID, 버전/빌드, 전송 시각과 함께 사용할 수 있다.

## 2026-09-22 ITMS-90683 수정

Apple의 처리 결과 메일에서 빌드 1의 거부 원인이 확인됐다. `Runner.app/Info.plist`에 `NSPhotoLibraryUsageDescription`이 누락돼 있었다. Xcode 업로드 및 Validate App 성공만으로 업로드 후 검증까지 통과했다고 판단할 수 없다.

- `file_picker`의 iOS 기본 빌드에는 사진 보관함 API를 사용하는 미디어 선택 코드가 포함된다. 앱의 책/책 묶음 표지 선택은 현재 `FileType.custom`을 사용하지만, 포함된 SDK의 API 참조에도 목적 설명이 요구될 수 있다.
- `ios/Runner/Info.plist`에 ‘서재의 책이나 책 묶음에 사용할 표지 이미지를 선택하기 위해 사진 보관함에 접근합니다.’를 추가했다. 앱 시작 시 사진 권한을 요청하는 코드는 추가하지 않았다.
- `pubspec.yaml`을 `1.0.0+2`로 올려 수정 빌드를 구분한다.
- 재배포 전 소스뿐 아니라 생성된 IPA의 `Payload/Runner.app/Info.plist`에도 해당 설명과 빌드 번호가 들어갔는지 확인한다.
- 수정 빌드 아카이브/IPA 생성 성공. IPA 내부에서 Bundle ID, 버전 `1.0.0`, 빌드 `2`, 사진 보관함 목적 설명을 직접 검증했으며 ZIP 무결성 검사도 통과했다.
- 로컬 IPA: `build/ios/ipa/koofy_reader.ipa`, 36,097,902 bytes, SHA-256 `b3853823504174ef533f4c0f8392366102dd0083faceff94c0235aa79a3ec67a`.
- 2026-09-22 00:12 KST에 빌드 2 재업로드 성공(`Upload succeeded`, `EXPORT SUCCEEDED`). Apple의 업로드 후 처리 결과는 별도로 확인해야 한다.
- App Store Connect에서 빌드 2의 업로드 상태 **완료**를 확인했다. 빌드 1은 **실패**로 표시된다. ITMS-90683으로 인한 빌드 등록 문제는 수정됐다.
- 빌드 2 UUID: `87f56130-4993-4477-9827-c1baf09c87be`. 테스트 안내를 저장했다.
- 내부 그룹 연결 시 Apple의 수출 규정 준수 질문이 먼저 나타나므로 연결은 아직 완료하지 못했다. 암호화 사용 답변 저장은 자동 승인 검토에서 거절됐으며, 법적 신고에 대한 확인/승인이 필요하다. 답변은 제출하지 않았고 `ITSAppUsesNonExemptEncryption`도 임의로 추가하지 않았다.

## 현재 상태: 빌드 2 내부 테스트 연결 완료

2026-09-22 사용자가 수출 규정 답변 처리를 완료했다고 알렸고, 화면에서 수출 규정 정보 요청이 해소된 것을 확인했다. 이후 빌드 `1.0.0 (2)`를 `쿠피리더 내부 테스트` 그룹에 연결했다.

- 빌드 업로드 상태: 완료.
- 연결 그룹: 쿠피리더 내부 테스트(내부, 테스터 1명).
- TestFlight 빌드 목록의 초대 수: 1.
- 외부 테스트 심사 또는 App Store 심사에는 제출하지 않았다.
- 사용자 기기에서 TestFlight 초대를 수락하고 설치/실행을 확인하는 단계가 남았다.


## 2026-09-23 빌드 3: iOS 페이지 분할 수정

- `pubspec.yaml`: `1.0.0+3`. 단일 페이지 열 너비 및 렌더링 시간 초과 이후 재시도 중단 패치를 포함한다. 상세 내용은 `ios-pagination-fix.md` 참조.
- 수정된 리더는 시뮬레이터 및 연결된 iPhone의 별도 UIKit 테스트 호스트에서 통합 테스트 네 가지를 통과했다.
- 원래 Flutter AppDelegate, 운영 Bundle ID, 자동 서명으로 `flutter build ipa --release` 성공.
- 아카이브: `build/ios/archive/Runner.xcarchive`. IPA: `build/ios/ipa/koofy_reader.ipa`(36,098,131 bytes).
- IPA 내부 Bundle ID `com.koofylab.koofyreader`, 버전 `1.0.0`, 빌드 `3`, 최소 iOS `15.0`, 사진 보관함 목적 설명 확인. ZIP 무결성 및 `codesign --verify --deep --strict` 통과.
- IPA SHA-256: `ab1e23ecbe97e154d2b0946d79ed7226b230e711b73b16f421695552b1f88dc3`.
- 2026-09-23 17:04 KST에 App Store Connect 업로드 성공(`Upload succeeded`, `EXPORT SUCCEEDED`). 업로드 로그: `work/ios-release-build3/upload.log`.
- App Store Connect에서 빌드 3 업로드 후 처리 **완료** 확인. 빌드 UUID: `03073183-3b44-4949-965f-0d23fc0db94a`.
- 내부 테스트 연결 전에 ‘수출 규정 관련 문서 누락’ 확인이 다시 요구된다. 현재 암호화 유형 질문 화면을 확인했으며 답변은 제출하지 않았다.

- 빌드 3 한국어 테스트 안내 저장 완료. 그룹 추가 시 암호화 문서 질문이 먼저 표시되어 연결은 대기 중이다. 사용자가 이전에 선택한 답변을 확인할 수 없으므로 임의 제출하지 않고, 현재 열린 질문의 확인·저장을 요청했다.


## 현재 상태: 빌드 3 내부 테스트 연결 완료

2026-09-23 사용자가 빌드 3의 수출 규정 확인을 완료했다. App Store Connect에서 요청이 해소된 것을 확인한 뒤 `1.0.0 (3)`을 기존 `쿠피리더 내부 테스트` 그룹에 추가했다.

- 빌드 3 상세 화면에서 그룹 1개, 내부 테스터 1명 연결 확인.
- 한국어 테스트 안내 저장 완료.
- iPhone의 TestFlight에서 빌드 `1.0.0 (3)`으로 업데이트하여 TXT 페이지 이동, 스크롤↔페이지 전환, 읽던 위치 복원 및 책장 효과를 확인할 수 있다.
- 사용자 기기에서 실제 업데이트 설치 및 수정 확인은 아직 확인하지 않았다.

## 2026-09-26 심사 피드백: ATT 사전 화면 수정

사용자가 전달한 2026-09-25 심사 결과는 `1.0.0 (3)`의 5.1.1(iv) 위반이다. 빌드 1의 ITMS-90683 메일과는 별개이며, 사진 접근 설명은 빌드 2부터 이미 포함되어 있다.

- iOS 첫 실행의 맞춤형/비맞춤형 라디오 선택을 제거했다. 중립적 안내와 `계속` 버튼에서 미결정 상태의 Apple ATT 요청으로 진행한다. 거부·제한·미결정 상태에서는 개인화를 허용하지 않는다.
- `계속`은 추적 동의가 아니다. `systemTracking`은 안내 절차 완료를 나타내며, 매 광고 준비 시 현재 OS 허가를 다시 확인한다. 요청 대기 중에는 광고 초기화나 완료 기록을 공개하지 않는다.
- 기존 `reader_privacy_choice_v1`의 `standard`/`personalized` 및 기록 버전을 유지했다. 업데이트로 기존 비맞춤형 선택을 바꾸거나 ATT를 재요청하지 않는다. `systemTracking` 기록을 Android에서 읽을 경우 비맞춤형으로 처리한다.
- 설정의 광고 방식 표시는 실제 적용 상태를 사용한다. `비맞춤형 광고만 사용`으로 추가 제한할 수 있고, 이 제한을 풀어도 ATT 허가를 우회하거나 시스템 창을 다시 띄우지 않는다. OS 권한은 기기 설정 링크로 확인한다.
- Android 최초 광고 선택 UI는 유지한다. 독서 데이터와 광고 보상은 변경하지 않는다.
- 앱 내 개인정보처리방침의 한국어/영어 iOS 안내를 수정했다. 문서 업데이트 날짜는 2026-09-26이고, 기존 선택을 보존하기 위해 저장 기록 버전은 2026-09-21을 유지한다. 외부 웹 방침과 콘솔은 이번 패치에서 배포하지 않았다.

검증: 개인정보 서비스/UI·광고 공간·공통 테마 테스트 28개 및 Flutter 정적 분석 통과. 권한 대기 중 광고 미설정, 허용·거절·제한·미결정, 기존 거절 복원, 권한 철회, 중복 탭, 요청 오류와 저장 실패 후 재시도를 확인했다. ATT 결과는 테스트 대역으로 검증했으므로 실제 시스템 권한창 확인을 대체하지 않는다.

`flutter build ios --debug --no-codesign` 성공. 생성된 `build/ios/iphoneos/Runner.app/Info.plist`에서 Bundle ID, 현재 로컬 버전 `1.2.0 (6)`, `NSPhotoLibraryUsageDescription` 및 `NSUserTrackingUsageDescription`을 직접 확인했다. 이번 검증은 서명 없는 debug 빌드이며 배포용 IPA 생성·버전 증가·업로드·재심사 제출은 하지 않았다.

재제출 전 기기 확인:

1. 별도 신규 설치 테스트 환경에서 iPhone/iPad의 안내에 허용·거절 사전 선택이 없고, 계속 뒤 실제 시스템 권한창이 표시되는지 확인한다. 기기 설정으로 요청이 제한된 경우 창이 표시되지 않는 것이 정상이다.
2. 허용/거절 모두 서재 진입과 독서가 가능하고, 거절 상태에서 광고 개인화가 활성화되지 않는지 확인한다.
3. 기존 데이터가 있는 설치는 삭제하지 않고 업데이트하여 독서 기록과 기존 광고 거절이 보존되고 반복 요청이 없는지 확인한다.
4. 새 배포 아카이브/IPA 안의 사진 및 추적 목적 설명을 다시 검사하고 새 빌드 번호로 TestFlight에 업로드한다. 이 패치만으로 심사 빌드가 교체되지는 않는다.

되돌리기: UI 수정과 서비스 수정을 함께 되돌려야 한다. 이전 코드가 새 `systemTracking` 값을 모르면 광고 선택을 미완료로 처리하므로, 배포 후 되돌릴 때는 새 기록을 `standard`로 보수적으로 해석하는 호환 처리를 유지한다. 기존 저장소를 삭제하거나 추적 동의로 변환하지 않는다.

## 2026-09-26 배포용 빌드 7 생성 완료 — 업로드 전

- 최신 독서·서재·TTS 변경, 디자인 개선, ATT 사전 화면 수정을 포함했다. 홈 화면 표시 이름을 승인된 `쿠피리더`로 맞췄다.
- 기존 Apple 심사 버전 `1.0.0`을 유지하고 빌드 번호는 `7`로 지정했다. Android용 공통 `pubspec.yaml`의 `1.2.0+6`은 이번 빌드에서 변경하지 않았다.
- 실행 명령: `flutter build ipa --release --build-name=1.0.0 --build-number=7 --export-options-plist=work/ios-release-build7/ExportOptions-export.plist`.
- 자동 서명으로 아카이브와 App Store Connect 배포용 IPA 생성 성공. `destination=export`이며 업로드 명령은 실행하지 않았다.
- 아카이브: `build/ios/archive/Runner.xcarchive`.
- 검증한 고정 파일: `work/ios-release-build7/KoofyReader-1.0.0-7.ipa` (36,290,871 bytes).
- SHA-256: `65ff34f4c0521652dca02f85e93db91583fb76f3540383e5d416a900a0a32436`.
- IPA 내부에서 Bundle ID, 버전/빌드, 표시 이름, 최소 iOS 15.0, 사진 및 추적 권한 목적 설명을 확인했다. ZIP 무결성 검사 및 `codesign --verify --deep --strict` 통과.
- Apple Distribution 서명, Team `W8A4759K5F`, 앱 식별자, `get-task-allow=false`, `beta-reports-active=true` 확인.
- 빌드 로그, 검증 JSON 및 한국어 테스트 안내: `work/ios-release-build7/`.
- App Store Connect 업로드, TestFlight 그룹 연결, 스토어 제목 변경 및 재심사 제출은 아직 하지 않았다. 기기 실측 ATT 확인도 남아 있다.

다음 iOS 빌드는 이 로컬 빌드 기록을 확인하고 `8` 이상의 새 번호를 사용한다. CLI에서 iOS 버전/빌드를 명시하지 않으면 공통 pubspec 값으로 돌아가므로 재배포 시 주의한다.

## 빌드 7 이후 Remote Config 코드 추가

2026-09-26 업데이트 안내 기능과 의존성을 추가했다. **기존 빌드 7 IPA에는 이 변경이 없다.** 사용자가 빌드 전 단계까지만 요청하여 새 IPA/아카이브는 만들지 않았다. 다음 빌드 전에 [Remote Config 운영 문서](remote-config-updates-ko.md)의 테스트/정식 배포 모드와 개인정보 안내 범위를 확인한다. Firebase에 게시한 iOS 안내 스위치는 현재 꺼져 있다.

## 2026-09-26 빌드 8 App Store Connect 업로드

- 사용자 요청 범위: 최신 빌드를 Apple에 업로드하고, 심사에 추가하는 작업은 다음 단계로 남긴다.
- `flutter build ipa --release --build-name=1.0.0 --build-number=8 --dart-define=READER_UPDATE_CHANNEL=store --export-options-plist=work/ios-release-build8/ExportOptions-export.plist` 성공.
- 최신 서재·독서·TTS·디자인·ATT 수정과 Remote Config 업데이트 안내를 포함한다. `store` 채널로 빌드했으며 Firebase 안내 스위치는 변경하지 않았다(양쪽 모두 false).
- 고정 IPA: `work/ios-release-build8/KoofyReader-1.0.0-8.ipa` (36,803,338 bytes).
- SHA-256: `dc5b24e6f8507c64072adfe996bad8b81a33f3db4a93ca3627f487a58b9b9f12`.
- IPA 및 아카이브의 Bundle ID, 버전/빌드, 표시 이름 쿠피리더, 사진·추적 권한 설명 확인. ZIP 무결성 및 `codesign --verify --deep --strict` 통과. 배포용 entitlements의 앱 ID·`get-task-allow=false`·`beta-reports-active=true` 확인.
- `xcodebuild -exportArchive -allowProvisioningUpdates`와 destination=upload 옵션으로 기존 Xcode 계정·배포 서명을 사용했다.
- 2026-09-26 12:50:29 KST에 `Upload succeeded`, `EXPORT SUCCEEDED` 확인. 전송 직후 Apple 서버 처리 중 메시지를 확인했다. 처리 결과는 아래 후속 확인 기록을 따른다.
- 후속 확인: App Store Connect의 빌드 업로드 목록에서 `1.0.0 (8)` 상태 **완료**를 확인했다. 빌드 식별자는 `aca6aaa9-fb83-4566-8d9a-d1553606c76b`이다. TestFlight 진행 상태에는 `수출 규정 관련 문서 누락`이 표시되며, 해당 확인은 심사 준비의 다음 단계로 남겼다.
- 빌드·업로드 로그, 검증 JSON, 한국어 테스트 안내는 `work/ios-release-build8/`에 보관했다.
- 스토어 심사 빌드 교체, 심사 추가·제출, TestFlight 그룹 연결, 스토어 제목·부제 수정은 하지 않았다.

다음 새 iOS 업로드는 빌드 9 이상의 번호를 사용한다. Android용 pubspec 버전은 이번 작업에서 변경하지 않았다.

## 2026-09-27 빌드 9 업로드 및 내부 테스트 준비

- 기존 미커밋 기능 개선과 광고 미노출 안내·오류 코드 기록 개선을 포함해 `1.0.0 (9)`로 생성했다. Android 공통 pubspec `1.3.0+7`은 유지했다.
- `flutter build ipa --release --build-name=1.0.0 --build-number=9 --dart-define=READER_UPDATE_CHANNEL=store --export-options-plist=work/ios-release-build9/ExportOptions-export.plist` 성공.
- 고정 IPA: `work/ios-release-build9/KoofyReader-1.0.0-9.ipa` (50,958,107 bytes), SHA-256 `da43dcf6694c24355db555ec7dc313f593e7f4dd1c9bb095ee58f8379940a48d`.
- Bundle ID `com.koofylab.koofyreader`, 표시 이름 쿠피리더, 버전/빌드, 최소 iOS 15.5, 사진·추적 목적 설명, ZIP 무결성, 시스템 인증서 저장소를 사용하는 배포 서명 검증 및 배포 entitlements 검증 통과.
- 기존 Xcode 계정으로 `xcodebuild -exportArchive -allowProvisioningUpdates`와 upload 옵션을 실행했다. 2026-09-27 21:07:12 KST `Upload succeeded`, `EXPORT SUCCEEDED` 확인. Apple 후처리와 TestFlight 그룹 연결은 아래 후속 기록으로 구분한다.
- 내부 테스트 그룹에는 기존 빌드 2·3만 연결돼 있었고, 테스터의 설치 상태는 `1.0.0 (3)`이었다. 빌드 8이 TestFlight 그룹에 연결되지 않았으므로 사용자에게 업데이트를 안내하는 것만으로 설치할 수 없는 상태였다.
- 빌드·업로드 로그, 검증 JSON, 테스트 안내, 미전송 심사 회신 초안은 `work/ios-release-build9/`에 있다. 새 빌드 실기기 확인 전에는 재심사를 제출하지 않는다.
- 후속 콘솔 확인: 빌드 9 업로드 상태 **완료**, 빌드 ID `143dd5f3-ba3c-43a8-b675-2ff8a26289ef` 확인. 한국어 테스트 안내 저장 완료.
- 기존과 동일한 표준 암호화 알고리즘 및 프랑스 미배포 답변을 저장해 수출 규정 누락을 해소했다. 배포 국가와 Info.plist는 이 작업에서 변경하지 않았다.
- `쿠피리더 내부 테스트` 그룹 연결 완료. 빌드 9 상세 화면에서 그룹 1개·내부 테스터 1명 확인. 사용자의 TestFlight 업데이트 및 실기기 결과를 기다리는 상태다. 심사 빌드 교체·회신 전송·재심사 제출은 아직 하지 않았다.
- 21:12 KST 사용자 업데이트·실행 보고 후 연결된 iPhone 12 Pro에서 `com.koofylab.koofyreader`, `1.0.0 (9)` 설치를 직접 확인했다. Console에서 SDK 개인정보 설정 호출이 관찰됐고 해당 시점 `KoofyAds` 실패 기록은 없었다. 이는 광고 노출 성공·차단 검증이나 충돌 없음의 증거로 확대 해석하지 않는다. 기존 리워드가 유효하면 광고 요청이 생략될 수 있다. 독서·위치 보존 확인은 사용자 기기 테스트 결과를 기다린다.
- 이후 App Store 배포 버전의 연결 빌드를 8에서 9로 교체하고, 광고 공급원·카테고리·광고주 차단 조치와 미노출 안내 개선을 심사 메모에 저장했다. 새로고침 후 빌드 9 연결과 메모 보존을 확인했다. 이전 바이너리는 삭제하지 않았고 기존 자동 출시 설정도 유지했다. 회신 전송과 재심사 제출은 아직 하지 않았으며, 독서·위치 보존에 대한 사용자 테스트 결과를 기다린다.

다음 새 iOS 업로드는 빌드 10 이상의 번호를 사용한다.

### 2026-09-27 빌드 9 재심사 제출 완료

- 사용자 재심사 요청에 따라 저장된 `1.0.0 (9)`와 광고 제한·미노출 안내 개선 심사 메모를 확인하고 `심사 업데이트` → `앱 심사에 다시 제출`을 완료했다.
- 2026-09-27 21:19 KST, 제출 상세 화면과 빌드 9 행 모두 **심사 대기 중**으로 변경된 것을 확인했다. 제출 ID는 `556505cf-1b5e-4369-bbdd-339b3d9cf1e6`이다.
- 반려 대응 내용은 심사 메모에 포함했다. 별도 회신 메시지는 전송하지 않았다. 기존 **승인 후 자동 출시** 설정은 유지했다.
- 사용자 업데이트·실행 보고와 재심사 진행 요청을 근거로 제출했다. 독서 위치 보존 및 광고 노출의 상세 실기기 결과를 별도로 검증 완료했다고 기록하지 않는다.

## 2026-09-26 빌드 8 재심사 준비

- App Store 한국어 이름을 `쿠피리더 - 텍스트 뷰어, TTS`, 부제를 `TXT·EPUB 전자책 읽기와 음성 듣기`로 저장했다. 한국어 설명에 TTS 안내를 추가했다.
- 배포 버전 1.0.0의 연결 빌드를 3에서 8로 바꾸고 저장했다. 제출 세부 화면에서도 `1.0.0 (8)` 연결을 확인했다. 이전 바이너리는 삭제하지 않았다.
- 심사 메모에 Guideline 5.1.1(iv) 수정 사항, 중립적인 계속 버튼, 건너뛰기 제거, 실제 OS 권한 존중, 기존 거부 보존, 신규 설치 확인 절차, 사진 권한 설명 포함 사실, 로그인 불필요와 주요 기능을 영어로 저장했다. 실제 신규 설치에서 ATT 시스템 UI를 검증했다는 주장은 하지 않았다.
- 반려 메시지에 대한 영어 회신은 **초안 저장**했다. 화면의 `초안 계속 작성` / `초안 삭제`로 저장 상태를 확인했다. 회신 전송 및 심사 업데이트/재제출은 하지 않았다.
- 수출 규정 질문을 열어 확인했으나 답변은 제출하지 않았다. 빌드 8은 여전히 `수출 규정 관련 문서 누락` 상태다.
- 공개 웹 개인정보처리방침(영문, 2026-09-21)은 Remote Config 설치 식별자 처리 및 최신 iOS 안내 흐름을 반영하지 않았다. 앱 내부 방침은 이미 수정되어 있으므로 외부 웹 방침과 일치시킨 후 제출한다.
- 기존 출시 방식은 `자동으로 버전 출시`로 확인했다. 이번 작업에서 바꾸지 않았다.
- 앱 개인정보 신고는 이미 게시되어 있고 사용자 ID의 앱 기능 목적, 기기 ID의 광고/분석/추적 목적 등을 확인했다. 이번 작업에서 신고 항목을 변경하거나 재게시하지 않았다. 공개 웹 방침의 Remote Config 설명 누락은 별도로 남아 있다.

## 2026-09-26 공개 개인정보처리방침 배포와 수출 규정 추가 확인

- Quiz_Site의 `lib/legal/koofyReaderPrivacy.json`을 앱 내부 한국어·영어 문서와 동일하게 갱신했다. 업데이트 날짜 2026-09-26, Remote Config 설치 식별자·앱/기기 정보 처리 목적, 독서 정보 미전송, 분석 개인화/A/B 실험 미사용 및 최신 iOS ATT 안내를 포함한다.
- `npm run build` 성공. 기존 이미지 관련 lint 경고 2건만 남고 타입 검사·정적 페이지 생성은 통과했다.
- Quiz_Site 커밋 `9ba33b99a563bb5cbccb0eb66d1e0623d78b9b18`의 한 파일만 기존 main 브랜치에 푸시했다. Vercel 배포 `61pRHZVDmgzi7e2T1JB2Sc7JEeZi` 성공과 공개 URL의 한국어·영어 Remote Config 문구를 직접 확인했다.
- 공개 URL: https://www.koofy.co.kr/koofy-reader/privacy . 앱 내부 문서는 이미 빌드 8에 포함되어 있으므로 이 웹 동기화 때문에 새 앱 빌드를 만들지는 않았다.
- 수출 규정은 빌드 8 내 표준 암호화 구현 포함을 추가 확인했다. 현재 프랑스 배포 설정에서 Apple이 관련 문서를 요구하므로 최종 저장은 보류했다. [근거와 선택이 필요한 항목](ios-export-compliance-build8.md)을 따른다. 배포 국가 변경은 사용자의 결정을 기다린다.
- Apple 회신 전송·재심사 제출 및 배포 국가 변경은 이 작업에서 하지 않았다.

## 2026-09-26 프랑스 제외 및 빌드 8 수출 규정 완료

- 사용자 승인에 따라 프랑스만 배포 대상에서 제외했다. 콘솔에서 174개 국가·지역 및 `프랑스 사용 불가`를 확인했다. 변경 반영 안내는 24시간 이내다.
- 빌드 8에 표준 암호화 알고리즘 사용 및 프랑스 미배포 답변을 저장했다. TestFlight 목록의 빌드 8 상태가 `제출 준비 완료`로 바뀌었으며 수출 규정 누락이 해소됐다.
- 자세한 근거와 답변은 [수출 규정 기록](ios-export-compliance-build8.md)을 따른다. 앱 코드·바이너리 변경, Apple 회신 전송, 재심사 제출은 하지 않았다.

## 2026-09-29 iOS 1.3.0 (10) 업로드 및 심사 준비

- 사용자 요청으로 최신 AdMob 중개·UMP 광고 동의 코드를 포함한 1.3.0(10)을 배포 인증서로 생성했다. `READER_UPDATE_CHANNEL=store` 및 기존 Team W8A4759K5F 자동 서명 사용.
- 산출물: `work/ios-release-build10/KoofyReader-1.3.0-10.ipa`, SHA-256 `81f00583df24330443cf47cc7d9ca77561e1c907018c2534149b39360001b8e5`. ZIP 무결성, 사진·추적 목적 문자열, App ID, 버전·Bundle ID 및 시스템 인증서 저장소를 사용하는 배포 서명 검증 통과.
- Xcode exportArchive로 11:06:03 KST `Upload succeeded`, `EXPORT SUCCEEDED` 확인. App Store Connect 처리 ‘완료’, 빌드 ID `57085591-ea63-42c1-8a64-e4227bb2ebea`.
- 기존과 동일한 표준 암호화 및 프랑스 미배포 답변 저장. 1.3.0 업데이트에 빌드 10 연결하고 변경사항·심사 메모 저장. 기존 자동 출시 설정과 국가를 유지한다.
- Apple 개인정보 신고에 새 Google SDK의 충돌 데이터·기타 진단 데이터 추가 게시. 비연결·비추적으로 신고하고 분석·광고·앱 기능 목적을 안내했다. 나머지 기존 항목 유지.
- 실기기 UMP·AdMob 광고 노출은 이 작업에서 검증하지 않았으며, 심사 메모에도 Google 공급원이 아직 비활성임을 명시했다. 최종 심사 접수는 아래 후속 결과를 따른다.

### 1.3.0 (10) 최종 심사 접수

- 2026-09-29 11:32 KST, **심사를 위해 제출** 완료 후 제출 상세에서 **심사 대기 중**, iOS 1.3.0 및 빌드 1.3.0(10)을 확인했다.
- 제출 ID: `6f91000b-848a-4734-9cec-0248f84fe4f4`.
- 기존 승인 후 자동 출시 설정을 유지했다. 승인·App Store 업데이트 제공 완료를 의미하지 않는다.
- 웹 개인정보처리방침 2026-09-29 AdMob·UMP 안내 공개 반영을 확인한 후 제출했다.
- 증빙: `/tmp/koofy-ads-20260929/apple-submitted.png`.

## 2026-10-02 1.3.3 (11) 아카이브 및 배포 차단

- 최신 앱 변경을 포함해 `READER_UPDATE_CHANNEL=store`로 아카이브 생성 성공.
- `build/ios/archive/Runner.xcarchive` 내부 버전 1.3.3, 빌드 11, Bundle ID 및 사진·추적 목적 설명 확인.
- IPA 내보내기 단계에서 Apple의 `Unable to process request - PLA Update available` 및 `No signing certificate "iOS Distribution" found` 오류가 발생했다. 업로드·심사 제출은 아직 완료되지 않았다.
- 계정 소유자에게 Apple Developer 새 계약 검토·동의 및 App Store Connect 재로그인을 요청했다. 완료 후 같은 아카이브를 배포 서명하여 업로드를 재개한다.
- 로그: `work/ios-release-build11/build.log`. 기존 빌드 IPA가 남아 있더라도 빌드 11 산출물로 사용하면 안 된다.

### 1.3.3 (11) 계약 동의 후 업로드 성공

- 사용자가 새 프로그램 계약 동의를 완료한 뒤 동일 아카이브의 배포 서명과 업로드에 성공했다. 2026-10-02 14:16 KST 로그에서 `Upload succeeded`, `EXPORT SUCCEEDED` 확인.
- App Store Connect TestFlight에서 1.3.3(11), 생성 2026-10-02 14:16, **처리 중**을 확인했다. 업로드 성공과 Apple 처리 완료·심사 접수는 별개다.
- 새 스토어 버전 1.3.3을 생성하고 한국어 출시 노트 및 빌드 11에 맞는 심사 안내를 저장했다.
- 업로드 로그: `work/ios-release-build11/upload-after-agreement.log`.

### 1.3.3 (11) 최종 심사 접수 완료

- 2026-10-02 14:22 KST **심사를 위해 제출** 완료. 제출 상세에서 iOS 앱 1.3.3 / 1.3.3(11) / **심사 대기 중** 확인.
- 빌드 ID: `bb32d7ec-9c8e-4194-a773-99eb883464a4`. 제출 ID: `c15ebd2e-4610-4869-8cc5-463c654e7512`.
- 빌드 처리 완료 후 암호화 유형은 기존과 동일한 표준 암호화 알고리즘, 프랑스 배포는 아니요로 저장했다. 실제 국가 설정에서 174개 사용 가능 및 프랑스 사용 불가를 확인했다.
- 사진·추적 목적 설명, 버전 및 Bundle ID, 시스템 인증서 저장소를 이용한 아카이브 코드 서명 검증 통과.
- 기존 승인 후 자동 출시 / 모든 사용자에게 즉시 업데이트 / 기존 평점 유지 설정을 유지했다. App Store 승인이나 배포 완료를 의미하지 않는다.
- 증빙: `work/ios-release-build11/apple-submitted.png`.

## 2026-10-06 기본 제공 도서 업데이트 1.3.4 (12)

- 사용자 요청으로 새 기본 소설·표지·다음 화 안내 및 설명서 표지를 포함한 1.3.4(12)를 준비한다. 기존 Team W8A4759K5F, Bundle ID, 승인 후 자동 출시 설정을 유지한다.
- `flutter build ipa --release --no-pub --build-name=1.3.4 --build-number=12 --dart-define=READER_UPDATE_CHANNEL=store --export-options-plist=work/ios-release-build12/ExportOptions-export.plist` 성공.
- IPA: `work/ios-release-build12/KoofyReader-1.3.4-12.ipa`, 53,299,658 bytes. SHA-256: `85fcaa1b148638f260679a31a585c3d84907db77cf574090c6aa9ea99b1dfe56`.
- ZIP 무결성, Bundle ID·1.3.4(12)·iOS 15.5·사진/추적 목적 설명·배포 entitlements 확인. 시스템 인증서 저장소 접근 권한을 갖춘 `codesign --verify --deep --strict` 검증 통과. 새 원고·두 표지 및 기존 기본 책 자산 5개가 소스와 일치한다.
- Xcode의 기존 계정으로 exportArchive 업로드를 시작했다. 웹 App Store Connect 세션은 만료되어 사용자에게 기존 계정 재로그인을 요청했다.
- 업로드·Apple 처리·심사 접수 결과는 아래 후속 기록을 따른다. 업로드 전 검사로 실기기 실행 검증을 대신했다고 주장하지 않는다.

### 1.3.4 (12) 업로드 성공

- 2026-10-06 23:21 KST Xcode exportArchive 업로드 성공. 로그의 `Uploaded package is processing.`, `Upload succeeded.`, `EXPORT SUCCEEDED` 및 종료 코드 0을 확인했다.
- 업로드 로그: `work/ios-release-build12/upload.log`. Apple 처리 완료·빌드 선택·최종 심사 접수는 웹 App Store Connect 재인증 후 이어서 확인한다.

### 1.3.4 (12) 심사 준비 완료

- 기존 계정 재로그인 후 새 App Store 버전 1.3.4를 생성하고 한국어 출시 노트 및 새 기본 책·다운로드 안내 경로를 담은 심사 메모를 저장했다.
- Apple 처리 완료된 빌드 12를 연결했다. 빌드 ID: `687a6fc1-6f64-468b-8c20-ed741dabb6f4`.
- 실제 국가 설정에서 174개 사용 가능 및 프랑스만 사용 불가를 확인했다. 기존과 동일한 표준 암호화 알고리즘 및 프랑스 미배포 답변을 저장해 수출 규정 누락을 해소했다.
- 승인 후 자동 출시, 모든 사용자에게 즉시 업데이트, 기존 평점 유지 및 기존 연락처·로그인 불필요 설정을 유지했다. 최종 접수 결과는 아래를 따른다.

### 1.3.4 (12) 최종 심사 접수 완료

- 2026-10-06 23:30 KST **심사를 위해 제출** 완료. 제출 상세에서 **iOS 앱 1.3.4 / 1.3.4 (12) / 심사 대기 중**을 확인했다.
- 제출 ID: `18aaa743-eac1-4708-8ac4-5a2627a25f24`. 제출 항목은 앱 버전 1개다.
- 기존 승인 후 자동 출시 설정을 유지했다. 실제 App Store 업데이트 제공은 Apple 승인 이후다.
- 증빙: `work/ios-release-build12/apple-submitted.png`.

## 2026-10-08 iOS 1.4.0 (13) 업데이트

- 사용자 요청으로 최신 연재 작품·회차 목록, 휴지통 영구 삭제·비우기, 묶음책 관리 및 서재 버튼·비독서 화면 광고 배치 개선을 포함해 빌드했다. 기존 1.3.4(12)의 App Store Connect `배포 준비됨`을 확인한 뒤 새 버전 1.4.0을 생성했다.
- `flutter build ipa --release --no-pub --build-name=1.4.0 --build-number=13 --dart-define=READER_UPDATE_CHANNEL=store --export-options-plist=work/ios-release-build13/ExportOptions-export.plist` 성공.
- IPA: `work/ios-release-build13/KoofyReader-1.4.0-13.ipa`, 53,345,894 bytes. SHA-256 `ab9b451f366707db1fc2f0f8a8f05a75f9f7338b10be0f05326009a7721cc07d`.
- ZIP 무결성, Bundle ID·버전·iOS 15.5·사진/추적 목적 설명·배포 entitlements, 기본 책 자산 5개 및 시스템 인증서 저장소를 이용한 배포 서명 검증 통과. 동일 앱 코드에 대한 Android 릴리스 당시 Flutter 테스트 68개·정적 분석 통과 기록을 확인했다. 이번 작업에서 실기기 독서·광고 노출을 새로 검증했다고 주장하지 않는다.
- 한국어 출시 노트와 영어 심사 메모 저장. 기존 자동 출시·즉시 업데이트·평점 유지 설정을 유지한다. 업로드·Apple 처리·최종 제출 결과는 아래 후속 기록을 따른다.
- 통계 기능과 Remote Config 값은 변경하지 않았다.

### 1.4.0 (13) 업로드 성공

- 2026-10-08 14:40 KST, Xcode 로그의 `Upload succeeded`, `EXPORT SUCCEEDED` 및 종료 코드 0 확인. 업로드 로그: `work/ios-release-build13/upload.log`.
- Apple 처리 완료·빌드 연결·최종 심사 접수는 아직 확인 전이다. 로그인된 Chrome에서 사용자 작업과 제어가 겹쳐 마지막 제출을 잠시 대기한다. 별도 브라우저 프로필에는 Apple 로그인이 없다.

### 1.4.0 (13) Apple 처리 완료 및 수출 규정 확인 대기

- 처리 완료된 빌드 13을 새 버전 1.4.0의 빌드 선택 화면에서 선택했다. 빌드 ID: `c58fe006-4803-4441-bc87-dcac5aaee66b`.
- 수출 규정의 표준 암호화 선택 시 자동 승인 검토가 규제성 선언에 대한 명시적 승인을 요구해 차단했다. 기존 답변(표준 암호화 / 프랑스 미배포)으로 진행할지 사용자에게 확인을 요청했다. 수출 규정 저장과 최종 심사 접수는 아직 미완료다.

### 1.4.0 (13) 최종 심사 접수 완료

- 사용자가 수출 규정 답변을 직접 완료했다고 알려준 뒤 콘솔에서 문서 누락 경고 해소를 확인했다. 빌드 연결을 저장하고 `심사에 추가` → `심사를 위해 제출`을 완료했다.
- 2026-10-08 14:53 KST, 제출 상세의 **iOS 앱 1.4.0 / 1.4.0 (13) / 심사 대기 중** 확인. 제출 ID: `7e6a4d75-24cb-420c-ac2d-fc0b886e83a0`.
- 기존 승인 후 자동 출시·모든 사용자에게 즉시 업데이트·기존 평점 유지 설정을 확인했다. 승인 및 실제 스토어 제공 완료를 의미하지 않는다.
- 증빙: `work/ios-release-build13/apple-submitted.png`. Remote Config는 변경하지 않았다. 승인 후 실제 업데이트 제공을 확인하면 `ios_update_latest_version`을 `1.4.0`으로 지정할 수 있다.
