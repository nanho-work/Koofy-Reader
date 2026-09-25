# 감사 실행 근거와 재현 방법

2026-09-25, 로컬 작업 트리 HEAD `9b02ac1` + 당시 미커밋 변경. 앱 코드를 변경하지 않은 분석 실행이다.

## 실행 결과

| 검사 | 명령 / 범위 | 결과 |
|---|---|---|
| Flutter | `flutter test --no-pub` | 176 passed |
| Analyzer | `flutter analyze --no-pub lib test pigeons packages/koofy_reader_bridge/lib` | No issues found |
| 임시 재현 | `flutter test --no-pub /tmp/koofy_audit_probe_test.dart` | 7 passed (현재 결함 발생을 기대한 검사) |
| TypeScript | `node functions/node_modules/typescript/bin/tsc -p functions/tsconfig.json --outDir /tmp/koofy-audit-functions` | compile success |
| 서버 단위 | functions를 cwd로 `node --test /tmp/koofy-audit-functions/test/*.test.js` | 15 passed, Node 20.19.2 |
| JavaScript | `node --test tool/test_reader_boundary.mjs` | 2 passed |
| 테마 | `python3 tool/generate_reader_palette.py --check` | Shared palette verified |
| Android | Android Studio JBR + `./android/gradlew -p android :koofy_reader_bridge:compileDebugKotlin --offline` | BUILD SUCCESSFUL, 10 up-to-date tasks |
| iOS | `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED |
| diff 형식 | `git diff --check` | pass |
| 원본 보존 | 감사 시작 259개 tracked/untracked 파일 SHA-256 재비교 | 기존 파일 내용 변화 0 |

사용한 Flutter 경로는 `/Users/choenamho/development/flutter/bin/flutter`, Node는 `/Users/choenamho/.nvm/versions/node/v20.19.2/bin/node`다. iOS 결과는 실행 테스트가 아니라 빌드다. Android 결과도 native bridge compile이며 release AAB 검증이 아니다.

## 감사용 재현 검사

1. 가져온 미열람 TXT의 원본을 지운 뒤 prepare 실패, 서재 항목은 남음.
2. 메모리 저장소의 read 두 개를 barrier로 같은 snapshot에 묶음. import와 download commit 둘 다 성공했지만 목록 길이는 1.
3. 손상 primary/backup을 설정하고 import 후 손상 원문 두 개 모두 새 목록으로 덮어써짐.
4. 같은 PNG를 책/묶음에 넣고 export→restore. 책 cover reset 후 묶음의 PNG도 없어짐.
5. restore 마지막 pref 저장에 disk-full 오류 1회 주입. 재시도 성공 후 책 coverPath와 완독 값이 없음.
6. Dart preferences JSON 왕복이 fontScale 3.5를 허용. native validator 상한 3.0은 소스로 대조.
7. remote image가 있는 EPUB를 server validateUpload는 수용, 앱 preparer는 외부 리소스 오류로 거부.

이 검사는 각각 독립 임시 폴더와 별도 in-memory SQLite를 사용한다. 실제 기기의 파일 선택기 캐시 삭제 시점, 전원 강제 종료, 광고 SDK, native 메모리, 클라우드 배포 상태는 검증하지 않는다.

### 다시 실행

저장소 루트에서 다음 순서로 실행한다. 앱 소스에는 새 파일을 추가하지 않는다. SDK 캐시 접근은 개발 환경 권한에 따라 필요할 수 있다.

```sh
cp docs/audits/2026-09-25/reproduction-probes.dart.txt /tmp/koofy_audit_probe_test.dart
cp docs/audits/2026-09-25/remote-resource-fixture.epub /tmp/koofy-audit-remote.epub
/Users/choenamho/development/flutter/bin/flutter test --no-pub /tmp/koofy_audit_probe_test.dart
```

문서 첨부 Dart는 이 컴퓨터의 기존 `test/library_backup_test.dart` helper를 절대 경로로 import한다. 다른 컴퓨터에서는 해당 import만 저장소 위치에 맞춰 바꿔야 한다.

서버 쪽 EPUB 수용 결과를 다시 확인하려면 TypeScript를 `/tmp/koofy-audit-functions`로 compile하고, 그 폴더의 node_modules를 저장소 `functions/node_modules`로 연결한 뒤 다음 코드로 검사한다. Firebase 배포나 파일 업로드는 수행하지 않는다.

```js
const fs = require('node:fs');
const { validateUpload } = require('/tmp/koofy-audit-functions/src/content.js');
validateUpload('book', 'epub', fs.readFileSync('/tmp/koofy-audit-remote.epub'))
  .then(r => console.log('SERVER_ACCEPTED', r.asset.extension, r.asset.size));
// 감사 결과: SERVER_ACCEPTED epub 1655
```

외부 리소스 fixture는 기존 서버 valid.epub에 `https://example.invalid/image.png` 참조만 추가했다. 검사 중 URL로 네트워크 요청하지 않았다. 서버 helper와 앱 preparer의 수용 범위 비교이며 실제 서비스에 악성 파일을 등록하는 테스트가 아니다.

## 관찰된 경고와 실패 시도의 해석

- Flutter category 테스트: ChoiceChip 탭 좌표 `Offset(408.1, 200.0)`가 root `Size(390.0, 844.0)` 밖이다. 기존 테스트가 통과해도 필터 동작을 입증하지 못한다(F12).
- Drift의 multiple database 경고: 기존 백업 fixture와 감사 fixture가 source/target용으로 별도 `NativeDatabase.memory()`를 만든다. 이 경고만으로 운영 앱이 동일 DB를 중복 open하거나 이미 손상됐다고 판정하지 않았다.
- 최초 Functions 테스트는 cwd를 루트로 실행하여 상대 fixture 경로/폰트 경로 ENOENT가 발생했다. functions cwd로 바로잡아 15개 통과. 이것을 앱 결함으로 보고하지 않았다.
- 새 EPUB 재현 검사의 최초 expected message를 실제 오류 문구와 다르게 작성해 1회 실패했다. 실제 출력은 외부 리소스 거부였으며, 기대 문구를 정정한 최종 7개 검사가 통과했다. 앱 코드는 고치지 않았다.
- Android Gradle은 deprecation 안내가 있지만 현재 compile 성공. 도구chain 업그레이드 시 별도 확인 사항이다.
- iOS/Android native tests는 파일과 주요 assertion을 읽었으나 이번 실행에서는 돌리지 않았다. iOS에 회전/글꼴/페이지/저널 XCTest가 이미 있고, Android에도 rendering/journal/geometry instrumentation이 있다.

## 임시 원본 로그 위치

로그는 OS 임시 파일이므로 영구 보관을 보장하지 않는다. 핵심 결과는 위 표와 보고서에 남겼다.

- `/tmp/koofy-audit-flutter-tests.log`
- `/tmp/koofy-audit-analyze.log`
- `/tmp/koofy-audit-probes.log`
- `/tmp/koofy-audit-functions.log`
- `/tmp/koofy-audit-epub-contract.log`
- `/tmp/koofy-audit-boundary.log`
- `/tmp/koofy-audit-android.log`
- `/tmp/koofy-audit-ios.log`
- `/tmp/koofy-audit-before.json` (파일별 시작 hash)
