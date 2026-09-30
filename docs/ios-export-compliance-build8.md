# iOS 빌드 8 수출 규정 확인 기록

확인일: 2026-09-26. 대상: `com.koofylab.koofyreader`, `1.0.0 (8)`.

## 확인 근거

- `ios/Podfile.lock`: ReadiumStreamer 3.11.0이 CryptoSwift 1.10.0에 의존한다. Firebase Remote Config, ironSource/Unity 광고 SDK도 포함한다.
- 앱 자체 Dart 코드의 crypto 용도는 파일 무결성 및 식별용 SHA-256/MD5다. ReadiumStreamer의 CryptoSwift 호출은 EPUB 글꼴 난독화 해제용 SHA-1이다. DRM 콘텐츠는 앱 준비 단계에서 거부한다.
- 그러나 배포 아카이브의 dSYM에는 `CryptoSwift.AES`의 암호화/복호화 구현 심볼이 남아 있다. 광고 SDK의 `ISEncryption`, `IronSource.LPMCrypto`도 확인했다. 호출 경로가 제한적이라는 이유만으로 바이너리에 구현이 없다고 단정할 수 없다.
- IPA Runner와 dSYM UUID가 모두 `0243DB1F-8CED-361D-B015-3FC3E57405C3`으로 일치한다. 근거 심볼 목록은 `work/export-compliance-build8/linked-crypto-symbols.txt`에 보관했다.
- Apple은 암호화를 사용뿐 아니라 포함하는 앱도 수출 규정 판단 대상으로 설명한다. 따라서 확인한 빌드에서 `위에 언급된 알고리즘에 모두 해당하지 않음` 또는 `ITSAppUsesNonExemptEncryption=false`를 자동 적용하지 않았다.

## 최초 콘솔 확인 (아래 완료 기록 이전)

- 빌드 8의 수출 규정 화면에서 `Apple의 운영 체제 내 암호화를 대체하거나 이와 병행하여 사용하는 표준 암호화 알고리즘`을 선택해 후속 질문을 확인했다. 최종 저장은 하지 않았다.
- 현재 가격 및 사용 가능 여부: 175개 국가/지역. 펼친 실제 목록에 **프랑스**가 포함된다.
- `프랑스에서 앱을 배포할 예정입니까?`에 `예`를 선택하면 **앱 암호화 문서 섹션에서 문서를 업로드하고 승인받아야 한다**는 안내가 표시된다.
- 현재 선언은 미완료이며 국가 설정도 유지했다. 프랑스 제외 또는 프랑스 유지 후 문서 준비 중 사용자의 결정을 요청했다. 허위로 프랑스 미배포를 신고하거나 임의로 국가를 제외하지 않는다.

## 당시 검토한 다음 단계

프랑스를 제외하도록 결정하면 실제 배포 국가에서 프랑스를 먼저 제외하고 저장한 뒤, 해당 배포 계획에 맞게 수출 규정 답변을 완료한다. 프랑스 유지 시 Apple이 요구하는 문서의 보유 여부와 적용 요건을 확인한다. 문서 필요 여부의 법적 판단과 미사용 암호화 구현을 제거한 새 빌드 검증은 이 기술 확인 기록만으로 완료되지 않는다.

## 2026-09-26 사용자 결정 및 저장 완료

- 사용자가 프랑스 제외를 명시적으로 승인했다. App Store Connect에서 프랑스만 해제하고 변경 확인을 저장했다.
- 저장 후 `사용 가능 여부(174개 국가 또는 지역)` 및 `프랑스 사용 불가`를 확인했다. 콘솔 안내에 따르면 변경 사항은 24시간 이내에 적용된다. 나머지 국가와 향후 신규 국가 자동 제공 설정은 유지했다.
- 빌드 `1.0.0 (8)`의 암호화 유형은 `Apple의 운영 체제 내 암호화를 대체하거나 이와 병행하여 사용하는 표준 암호화 알고리즘`, 프랑스 배포 질문은 `아니요`로 저장했다.
- 저장 후 수출 규정 정보 제공 버튼이 사라졌고, TestFlight 빌드 목록에서 빌드 8의 상태가 `제출 준비 완료`로 표시됨을 확인했다. 기존 수출 규정 관련 문서 누락 상태는 해소됐다.
- 앱 바이너리와 Info.plist는 변경하지 않았다. 이 기록은 콘솔 답변 및 상태 확인이며 모든 관할의 수출 관련 의무를 법적으로 검증했다는 의미는 아니다. 프랑스 배포 또는 암호화 구성이 변경되면 요건과 답변을 다시 확인한다.
- Apple 반려 회신 전송과 재심사 제출은 하지 않았다.

## 공식 참고

- [Apple 수출 규정 개요](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Apple 암호화 문서 요건](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
