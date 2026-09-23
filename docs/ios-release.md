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
