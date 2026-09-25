# 감사 후 결함 수정 결과

2026-09-25. [원래 감사 보고서](report.md)의 F01–F12에 대한 코드 수정이다. 대규모 책임 분리, 배포, 콘솔 변경은 포함하지 않는다. 감사 당시의 재현 자료는 수정 전 증거로 보존한다.

## 적용한 수정

| 항목 | 적용 내용 | 주요 파일 / 검증 |
|---|---|---|
| F01 동시 서재 변경 | 앱 isolate 내의 공통 mutation queue로 import, download 설치, 삭제, 묶음 변경, 표지, 완독 기록, 백업·복원을 직렬화. 중첩 repository 호출은 같은 작업에 참여하고 실패 후 다음 작업을 계속 실행 | `lib/core/storage/library_mutations.dart`, 서재 repository들, `library_backup.dart`. 서로 다른 repository 인스턴스의 import/download 동시 실행 회귀 검사 |
| F02 임시 원본 만료 | 새로 가져오는 파일은 검사 후 앱 지원 디렉터리의 고유 폴더에 flush하여 보관하고 그 경로를 목록에 기록. picker 원래 경로는 중복 선택 판정용 `importSourcePath`에만 유지 | `book_repository.dart`, `book.dart`. 읽지 않은 책의 원본을 삭제한 뒤 독서 준비 및 백업 성공 |
| F03 복원 실패·재시도 | 원래 없던 SharedPreferences 키는 rollback 시 빈 문자열 대신 실제 제거. 원래 값이 있으면 그대로 복원 | `local_storage.dart`, `library_backup.dart`. 후반부 키 저장 실패 후 다시 복원하여 표지·완독·묶음 순서 확인 |
| F04 손상 목록 덮어쓰기 | 잘못된 행·중복 ID를 조용히 버리지 않고 목록 손상으로 처리. 정상 보조본이 있으면 손상 원문을 격리 보관하고 복구. 두 사본이 모두 손상이면 변경을 중단 | `book_repository.dart`. 손상된 두 원문과 잘못된 행이 import 후에도 보존되는지 검사 |
| F05 공유 표지 삭제 | 복원 표지는 복원 작업·소유자별 고유 파일명 사용. 기존 공유 표지는 다른 저장 참조가 남아 있으면 물리 파일을 삭제하지 않음 | `book_cover_store.dart`, `library_backup.dart`. 책 표지를 초기화해도 묶음 표지 유지, 마지막 참조 해제 시 정리 |
| F06 무제한 import 파싱 | 읽기 전 원본 용량 검사. EPUB 전체 검증과 메타데이터 파싱은 기존 리더 검증기를 이용해 isolate에서 실행 | `reading_publication_preparer.dart`, `book_repository.dart`. 외부 리소스 EPUB 및 40MiB 초과 EPUB이 목록에 들어오지 않음을 검사 |
| F07 설정 범위 차이 | Dart 저장·백업 검증의 fontScale 상한을 양 플랫폼 리더와 같은 3으로 수정 | `native_reader_store.dart`. 3 허용, 3.5 거부 |
| F08 초기화 오류의 빈 화면 | 초기화 전 Flutter 준비 화면 표시. 실패 시 설명과 재시도 제공. 손상된 legacy snapshot은 원문을 별도 보관한 뒤 원래 legacy 키에서 재구성 | `main.dart`, `app/bootstrap.dart`, `legacy_reader_archive.dart`. 초기화 실패→재시도와 손상 snapshot 보존 검사 |
| F09 다른 책까지 막는 저널 | 네이티브 저널별 오류 분리와 별도 책 식별 파일 추가. 정상 저널은 계속 복구하고 실패한 기록은 ACK하지 않음. 같은 책의 미복구 기록은 새 세션 시작을 막음 | Android `ReaderCheckpointJournal.kt`, iOS `ReaderCheckpointStore.swift`, Dart coordinator. 다른 책의 손상·없는 세션, 본인 책 손상, 식별 불명 기록 시나리오 검사 |
| F10 광고 객체 누적 | LevelPlay rewarded 광고 객체·리스너를 서비스당 하나로 재사용. UI 시도는 닫기 후 정리. auction ID 기준 보상 중복 방지와 저장 직렬화로 이전 시청의 지연 보상을 처리 | `rewarded_ad_service.dart`. 100회 보상 없이 닫아도 광고 객체 1개, 이전 보상 지연 도착·중복·저장 실패·다음 시청 분리 검사 |
| F11 서버 EPUB 검사 차이 | 엔트리 수, 해제 용량, CRC, 실제 리소스/manifest/spine, 문자 인코딩, 외부 링크·스크립트·CSS 검사 보강. 숫자 엔티티로 숨긴 URL 및 복수 style 블록 검사 | `functions/src/content.ts`, `functions/test/epub_validation.test.ts`. 원래 감사의 외부 이미지 EPUB 거부와 정상 EPUB 허용 |
| F12 무효 탭 테스트 | 분류 칩을 실제 가시 영역으로 이동한 뒤 탭. 칩 선택 상태와 다른 분류 도서 제외 여부를 함께 확인 | `test/catalog_page_test.dart` |

리워드 설계는 SDK의 광고 객체 재사용과 닫기 이후 보상 콜백 규칙을 따른다. [Unity 공식 Flutter rewarded 문서](https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/rewarded-ads-integration).

## 데이터 호환성과 수정 범위

- 책 ID, content revision, Locator, SQLite 스키마 버전, 묶음 순서와 기존 저장 키는 유지한다. 초기화·삭제 마이그레이션을 추가하지 않았다.
- `importSourcePath`는 선택적 필드다. 이전 목록도 읽으며, 백업 파일에는 기기별 원래 경로를 넣지 않는다.
- **이미 가져와 둔 오래된 미열람 파일을 일괄 복사하는 마이그레이션은 하지 않았다.** 이번 수정은 새 import부터 적용된다. 기존 책은 기존 경로/리더가 보관한 원본을 계속 사용한다. 이미 사라진 원본을 새로 복구해 주지는 못한다.
- 완전히 손상된 이전 저널에서 책 ID까지 알 수 없으면 다른 책이라고 임의로 추정하지 않고 안전하게 열기를 중단한다. 식별 가능한 손상 기록은 해당 책만 막는다. 새 저널에는 식별 정보를 별도 저장한다.
- iOS의 기존 `previous` fallback 정책은 유지한다. 최신·보조 기록 모두 해독되지 않는 경우 오류로 남기며, 정상 fallback이 있으면 기존 복구 정책을 따른다.
- 기본 서재 본문, 화면 디자인, 페이지 넘김 엔진, 기존 추가 기능과 생성 Pigeon 코드는 이번 수정에서 변경하지 않았다. 기존 미커밋 변경을 reset/stash하지 않았다.
- 신규 원본과 실패한 복원의 staging 파일은 메타데이터 일부가 가리킬 가능성이 있어 임의 삭제하지 않는다. 참조 기반 GC는 후속 작업이다.
- 기존에 업로드된 서버 EPUB을 소급 재검사하거나 자동 삭제하지 않는다. 새 검사는 Functions 배포 후 새 업로드에 적용된다.
- 앱과 Functions는 **아직 배포하지 않았다.** 실기기에 설치되어 있는 앱과 운영 서버는 기존 버전이다.

## 검증 결과

| 확인 | 결과 | 한계 |
|---|---|---|
| Flutter 전체 테스트 | **191개 통과** | 이전 176개에서 회귀 검사 추가. 가짜 저장소·임시 파일·메모리 DB 사용 |
| Dart 정적 분석 | **No issues found** | `lib test pigeons packages/koofy_reader_bridge/lib` |
| Functions TypeScript 컴파일 | **통과** | 산출물은 `/tmp/koofy-fixes-functions`에 생성 |
| Functions 단위 테스트 | **21개 통과** | 로컬 Node 20.19.2. 배포 런타임인 Node 22 및 Firebase emulator/운영 환경은 이번에 검증하지 않음 |
| 공통 JS 페이지 경계 테스트 | **2개 통과** | 실제 WebView 렌더링·프레임 속도 측정은 아님 |
| Android 네이티브 컴파일 | **통과** | `compileDebugKotlin` |
| Android instrumentation 테스트 컴파일 | **통과** | `compileDebugAndroidTestKotlin`. 추가한 저널 검사 포함. 기기에서 실행하지 않음 |
| iOS 앱 시뮬레이터 빌드 | **BUILD SUCCEEDED** | 앱 컴파일 결과이며 XCTest 실행 성공과 다름 |
| iOS 저널 XCTest 7개 실행 시도 | **실행 미완료** | 전용 임시 시뮬레이터는 부팅했으나 Xcode test destination 인식 실패. 별도 `build-for-testing`에서는 Swift 테스트 소스 컴파일 후 Flutter 관련 arm64 심볼 링크 실패. 테스트 인프라 추가 점검 필요 |
| 실기기 광고 / 오프라인 / OS kill | **미검증** | 테스트 더블의 보상 콜백 검증을 실제 광고 SDK 노출 성공으로 간주하지 않음 |
| `git diff --check` | **통과** | 기존 변경 포함 공백 오류 검사 |

Flutter 테스트 중 복원 원본/대상용으로 서로 다른 메모리 DB를 동시에 만드는 테스트에서 Drift의 다중 인스턴스 경고가 나온다. 같은 QueryExecutor를 공유하지 않는 테스트 구성이다. 이 경고를 무시하도록 앱 설정을 바꾸지 않았다.

검증 로그: `/tmp/koofy-fixes-full-final.log`, `/tmp/koofy-fixes-analyze.log`, `/tmp/koofy-fixes-server.log`, `/tmp/koofy-fixes-android.log`, `/tmp/koofy-fixes-android-test.log`, `/tmp/koofy-fixes-ios.log`, `/tmp/koofy-fixes-ios-testbuild.log`, `/tmp/koofy-fixes-ios-tests-final.log`.

## 후속 순서와 배포 전 확인

1. **실기기 회귀 점검:** 여러 TXT/EPUB 동시 가져오기, 가져온 뒤 원본 제거·재시작, 이어읽기, 묶음 표지 변경, 백업 실패·재시도, 광고 취소/보상/재시청. Android와 iOS에서 동일 순서로 확인한다.
2. **복원 중 OS 강제 종료(U01):** 이번 공통 queue는 앱 프로세스가 살아 있는 동안의 순서를 보장한다. SQLite와 SharedPreferences를 하나의 영속 트랜잭션으로 만들지는 않았다. kill 시나리오와 영속 복원 journal은 별도 구현이 필요하다.
3. **추가 의심 항목:** 이전 스키마 실제 fixture(U03), native Locator 상세 형식(U04), SDK 초기화 콜백 영구 누락(U05), 장문·회전·메모리 압박 성능(U06), 로그·운영 권한/호출량(U07/U08), 참조 기반 고아 파일 정리(U09)를 이어서 검증한다. 복원/다운로드의 메타데이터 경쟁(U02)은 공통 queue로 차단했지만 실제 파일 다운로드 중 프로세스 종료까지 검증한 것은 아니다.
4. **구조 분리:** 위 데이터 보존 검증 이후 준비 서비스, 상태 보관, 리더 UI 책임 분리를 진행한다. 이번 패치에 큰 파일 이동을 섞지 않는다.
5. **배포:** 앱 새 빌드와 Functions 배포를 별도로 검토한다. 관리자 검사 수정은 앱 업데이트만으로 운영 서버에 반영되지 않는다.

## 되돌리기

- 현재 작업 트리에는 이 패치 이전의 사용자 변경이 함께 있다. 전체 `git reset`, 파일 전체 checkout, 사용자 데이터 삭제로 되돌리지 않는다.
- 이 문서에 해당하는 변경만 코드 검토 후 역패치한다. 특히 native journal 파일과 `native_reader_store.dart`에는 이전 미커밋 변경도 있으므로 hunk 단위로 분리한다.
- 기존 DB/SharedPreferences와 앱 지원 폴더를 유지한다. 새 import의 앱 소유 경로는 이전 버전도 일반 localPath로 읽을 수 있다. 선택적 `importSourcePath`와 `.identity` 파일은 이전 코드가 읽지 않는다.
- 서버 검증만 문제가 생기면 해당 검사 변경을 독립적으로 되돌릴 수 있다. 등록된 도서, 파일, 사용자 기록을 삭제할 이유가 없다.
- OS kill까지 보장하는 복원 마이그레이션이나 SQLite schema 변경은 이번에 없으므로 데이터 다운그레이드 작업은 필요하지 않다.
