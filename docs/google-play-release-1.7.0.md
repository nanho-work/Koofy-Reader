# Google Play 1.7.0 (16)

2026-10-21 제출 실행 완료. Play Console에서 “검토 중인 변경사항”으로 이동했으며 빠른 사전 검사가 진행 중이다. 검사 통과 후 심사로 전달되며, 승인 완료나 공개 완료를 의미하지 않는다.

- 패키지: `com.koofylab.koofyreader`
- 프로덕션 전체 출시: 178개 국가·지역, 100%
- 관리형 게시: 사용 중지 (승인 후 자동 게시)
- 제출: 앱 번들 1건 + 한국어/영어/일본어 이름·짧은 설명·전체 설명 9건
- 소개 원고: `docs/store-listings-1.7.0.json`
- 아이콘과 기존 현지화 스크린샷 유지
- AAB: `work/release/1.7.0-16/KoofyReader-1.7.0-16.aab`
- SHA256: `b2c9c45a409f7efc2df006b4c16fc11f041d59e352c189fee0302929e60dbb37`
- 증빙: `work/release/1.7.0-16/play-submitted.png`

## 확인

Release 빌드 성공, 번들 검증 및 서명 확인, 기존 업로드 인증서 일치, Readium 서비스 ID 7개 보존 검사 통과. Play 처리 결과 지원 기기 감소 0. minSdk 24 / targetSdk 36.

공개 개인정보처리방침(2026-10-21)에 선택적 Analytics와 로컬 평가 요청 기록 반영 확인. 기존 Play 데이터 보안의 앱 상호작용·대략적 위치·기기 ID에는 분석 목적이 이미 포함되어 있어 이번 제출에서 변경하지 않았다. 광고 SDK의 수집도 있으므로 데이터 유형 전체를 선택적 수집으로 바꾸지 않았다.

실기기 GA4 DebugView 수신은 미검증이다. Apple 출시/개인정보 선언은 이번 Android 제출 범위에 포함하지 않았다. Remote Config 값도 변경하지 않았다. Git 커밋·푸시는 소유자가 진행한다.
