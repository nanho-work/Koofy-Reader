# 선택 번역과 발음 듣기 (2026-09-27)

## 사용자 흐름

독서 설정 → ‘번역 모드 · Google로 번역’ → 하단 번역창 → 본문 단어 길게 누르기 → 선택 손잡이로 문장 범위 조절 → 손을 뗀 뒤 번역. 첫 범위는 영어 → 한국어다. 자동 언어 감지, 전체 책 번역, 단어장 및 문법 분석은 포함하지 않는다.

첫 이용 시 ‘번역 준비 · Wi-Fi’로 언어 데이터를 내려받는다. 준비 후에는 기기 안에서 번역한다. 180초 동안 완료 응답이 없으면 재시도 안내로 바뀐다. 다운로드 자체는 SDK가 관리하므로 모드 종료가 다운로드 취소 완료를 의미하지 않는다. 모델은 다음 이용을 위해 기기에 남는다.

번역창은 모드를 켤 때만 본문 공간을 확보하며 결과가 바뀔 때마다 본문 높이를 바꾸지 않는다. 원문과 번역문은 한 스크롤 영역에 표시한다. 선택은 2,000 UTF-16 코드 단위까지 처리하고 초과 시 범위를 줄이도록 안내한다. 텍스트는 plain text로만 표시한다. Google 공식 attribution 이미지를 테마에 맞게 표시한다.

원문 듣기는 영어, 번역 듣기는 한국어 기기 음성을 사용한다. 자동 재생하지 않으며 선택 발음은 별도 합성기를 사용해 기존 책의 TTS 진행 기록과 읽던 위치를 덮어쓰지 않는다. 책 읽어주기 시작 시 선택 음성을 멈추고, 선택 발음 시작 시 책 읽어주기를 일시 정지한다. 앱 이탈·광고 상호작용·오디오 인터럽트·이어폰 분리 시 멈추며 자동 재생을 재개하지 않는다. Android는 설치된 비네트워크 음성만 사용한다. iOS는 AVSpeechSynthesisVoice 목록에서 해당 언어의 사용 가능한 음성을 선택한다. 실제 음성 설치/발음 품질은 기기 확인이 필요하다.

## 제스처와 상태

- Android는 OS의 길게 누르기 시간 설정을 따른다. 번역 모드에서는 모서리의 DOWN을 선점하지 않는다. 길게 누르기 전 빠른 수평 이동은 기존 페이지 넘김으로 전달하고, 길게 누른 이후에는 텍스트 선택에 맡긴다.
- iOS는 0.55초/8pt 기준의 비차단 길게 누르기 인식기를 페이지 pan보다 우선한다. 실제 텍스트 선택과 손잡이는 WKWebView/Readium이 담당한다. 번역 모드에서는 curl 오버레이가 모서리 터치를 먼저 가져가지 않도록 하고, 빠른 swipe/tap으로 요청한 페이지 전환 애니메이션은 유지한다.
- 선택 중에는 다음/이전 요청을 막는다. 선택 손잡이를 누르거나 selectionchange 직후에는 번역하지 않는다. 추가로 선택값이 500ms 안정된 뒤 번역한다.
- 선택 해제 후 같은 문장 재선택도 다시 번역한다. 세션 generation으로 이전 문장의 지연 응답이 새 문장을 덮어쓰는 것을 막는다.
- 모드가 켜진 전경 상태에서만 200ms 간격으로 현재 문서의 선택 상태를 조회한다. 꺼짐/백그라운드/닫기에서 폴링과 발음을 중단한다. 번역문·선택문은 앱 기록이나 로그로 저장하지 않는다.
- 모드 설정은 해당 독서 세션에서만 유지한다. 책을 새로 열면 꺼진 상태다. 모드 on/off는 기존 Locator 복원 경로로 본문 위치를 유지한다.

## 구현

| 영역 | 파일/역할 |
| --- | --- |
| 공통 선택 상태 | `packages/koofy_reader_bridge/ios/Resources/reader_selection.js`: native selection, touch 종료, 길이 한도. Android에서도 같은 자산 사용 |
| Android 번역/UI | `ReaderTranslation.kt`: ML Kit, 하단 패널, 세대 검사, 선택 발음 |
| Android 제스처 | `ReaderTurnHost.kt`, `ReaderPageTurns.kt`: 선택 중 페이지 요청 금지, 번역 모드 모서리 소유권 |
| iOS 번역/UI | `ReaderTranslation.swift`: ML Kit, 하단 패널, 선택 발음 |
| iOS 연결 | `KoofyReaderViewController.swift`, `ReaderSettingsViewController.swift`: 모드 진입·레이아웃 복원·제스처·수명 주기 |

Android `com.google.mlkit:translate:17.0.3`, iOS `GoogleMLKit/Translate 8.0.0`(MLKitTranslate 7.0.0)을 고정한다. 기존 Firebase 프로젝트의 유료 Cloud Translation API나 사용자 본문 업로드 경로는 추가하지 않는다.

**최소 iOS 버전이 15.0 → 15.5로 변경된다.** ML Kit 요구사항에 맞춰 Podfile, bridge podspec, Runner 설정, AppFrameworkInfo를 함께 갱신했다. Android 최소 API 23은 유지한다. Google의 현재 iOS SDK는 Apple Silicon의 arm64 시뮬레이터를 제외하므로 이 환경의 iPad 시뮬레이터에서 이번 기능 실행은 검증하지 못했다. iOS 기기용 컴파일은 검증하며 실제 iPhone 테스트가 필요하다.

## 검증 범위

- Android 실제 Readium/WebView 계측: 길게 누른 모서리와 빠른 swipe 구분, 선택 시 페이지 이동 차단, 영어→한국어 모델 준비 및 하단 번역 결과, 모드 종료 확인. 초기 별도 SDK 테스트는 화면 없는 실행에서 다운로드 완료를 기다리다 시간 초과했으며, 실제 전경 독서 화면으로 수정한 테스트에서 다운로드·번역을 확인했다.
- JS 선택 상태 검사: 터치 유지 중 번역 금지, 해제 후 debounce, 길이 제한, 선택 해제.
- Flutter 개인정보 화면/선택 정책/독서 준비 회귀 테스트 40개 통과.
- iOS 기기용 Debug 빌드: 서명·업로드 없이 컴파일 확인. 실제 iOS 번역·손잡이 조작·발음은 미검증이다.
- 실제 학생 원서의 번역 품질, iPhone 손잡이 제스처, 회전/폴더블 전환 중 선택 해제, 오프라인 첫 실행/저장 공간 부족, 긴 문장·큰 글씨·가로 화면의 편의성은 실기기 점검 항목이다.

## 배포 전 확인

사용방법 안내와 앱 내부 한·영 개인정보 문서에 온디바이스 번역, Google의 모델 다운로드/SDK 성능·사용 통계를 추가했다. 앱 외부의 웹 개인정보처리방침 및 두 스토어 데이터 공개 항목도 새 SDK에 맞춰 확인해야 한다. 이 작업에서 웹 배포·스토어 변경·심사 제출은 하지 않는다.

앱 설명/도움말에서 Google Translate 사용을 밝히고 공식 링크를 제공한다. 결과 옆 attribution PNG는 Google 공식 배포 ZIP에서 가져왔으며 수정하지 않았다.

- https://developers.google.com/ml-kit/language/translation
- https://developers.google.com/ml-kit/language/translation/android
- https://developers.google.com/ml-kit/language/translation/ios
- https://developers.google.com/ml-kit/terms
- https://developers.google.com/ml-kit/language/translation/translation-terms
- https://cloud.google.com/translate/attribution

## 되돌리기

번역 모드를 끄면 기존 독서 UI로 돌아간다. 이 기능은 책 원본·SQLite 독서 기록·기존 TTS 위치를 변경하는 마이그레이션을 하지 않는다. 기능을 제거할 때는 번역 패널과 모드/제스처 연결, SDK 의존성만 기능별로 되돌린다. 기존 미커밋 변경을 포함한 파일 전체를 초기화하지 않는다. 배포된 최소 iOS 지원 범위를 되돌리는 결정은 SDK 제거 및 빌드 호환성 확인 후 별도로 한다.
