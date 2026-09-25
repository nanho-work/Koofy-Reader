# 단계별 개선·회귀 검증·되돌리기 계획

> 이 문서는 수정 전 감사/계획입니다. 이후 적용 내용과 남은 검증은 [결함 수정 결과](fixes.md)를 확인하세요.

이 문서는 실행 계획이다. **아래 변경은 아직 적용하지 않았다.** 감사 결과는 [report.md](report.md)를 따른다. 기존 독서 엔진과 사용자 데이터, 작업 트리의 미커밋 변경을 유지한다.

## 작업 원칙

- 기능 결함 수정과 동작을 바꾸지 않는 리팩터링을 서로 다른 변경 단위로 만든다. 하나의 큰 “전체 정리” 패치로 제출하지 않는다.
- 현행 사용자 데이터 fixture와 실패 재현을 먼저 확보한다. 테스트 통과를 위해 동작 보장을 줄이거나 데이터 초기화를 넣지 않는다.
- 저장 형식이 바뀌는 작업은 기존 키/책 ID/content revision/Locator/묶음 순서를 보존하고, 읽기 호환을 먼저 넣은 뒤 쓰기를 바꾼다.
- 메모리 파일의 임시 copy만으로 운영 DB 백업이 일관적이라고 가정하지 않는다. 실제 DB snapshot은 writer를 정지·flush하고 SQLite backup/checkpoint 방법을 사용한다.
- 네이티브 동작 변경은 같은 fixture와 의미를 양 플랫폼에서 검증한다. OS별 UI/수명 API 차이는 유지한다.
- 모든 단계에서 배포·콘솔 변경은 별도다. 이 계획을 실행해도 자동 출시하지 않는다.

## 0단계: 안전한 수정 기준선 만들기 — 테스트/문서만

### 할 일

1. 기존 미커밋 변경의 소유권을 유지한 작업 기준선과 변경 파일 목록 기록. 현재 감사는 259개 파일 hash로 보존 확인했다. 사용자 변경을 임의 stash/reset/checkout하지 않는다.
2. 감사 재현 7개를 정식 회귀 테스트로 옮긴다. 현재 “결함이 발생함” assertion을 실제 수정 단계에서 “보존되어야 함” assertion으로 바꾼다.
3. 과거 SQLite v1/v2/v3 및 현 v4 fixture, SharedPreferences 정상/손상/일부 누락 fixture, 미ACK native journal을 준비한다.
4. F12 테스트 수정: 다른 분류 도서 포함, ChoiceChip 가시 영역까지 스크롤, 선택 상태·제외 결과 확인, hit-test warning 실패 처리.
5. Functions 테스트를 Node 22에서 실행하는 표준 명령을 정하고, emulator 테스트와 단위 테스트 결과를 분리한다.

### 완료 기준 / 되돌리기

- 새 재현 검사는 현재 결함에서 예상대로 실패해야 한다. 기존 176개를 삭제하거나 완화하지 않는다.
- 실행 자료는 임시 폴더/가짜 저장소만 사용한다. 데이터 형식 변경이 없으므로 테스트·문서 변경만 되돌릴 수 있다.

## 1단계: 데이터 보존 결함 수정 — 기능 수정

아래 1A~1E를 각각 작고 검토 가능한 패치로 나눈다. 1A의 저장 경계가 복원 변경과 맞물리므로 먼저 정의한다.

| 순서 | 대상 | 변경 | 완료 기준 |
|---|---|---|---|
| 1A | F01, U02 | 목록의 모든 변경을 repository 내부에서 직렬화. import/download/remove/restore가 같은 mutation 경계를 사용. UI busy와 분리 | 두 동시 성공 작업의 책이 모두 남고, 삭제와 설치 순서가 명확. 실패 후 queue의 다음 작업도 수행 |
| 1B | F02, F06 | 검증→앱 소유 원본 staging→flush/rename→목록 commit. 메타데이터는 bounded inspector에서 추출 | import 직후 원본 삭제/앱 재시작을 해도 열기·백업 가능. copy 실패 시 반쪽 항목 없음 |
| 1C | F04 | load 결과를 absent/valid/recovered/corrupt로 구분. 손상 원문 격리, corrupt 상태의 자동 덮어쓰기 금지 | 원문 손상 + backup 정상 복구; 모두 손상 시 명시 오류와 원문 보존. 새 import가 손상 evidence를 지우지 않음 |
| 1D | F03, F05 | LocalStorage remove 지원 및 rollback의 부재 상태 복구, 항목별 고유 표지 저장/기존 공유 참조 보호 | 어느 저장 단계에서 한 번 실패해도 retry 후 완독·표지·순서가 모두 일치. 한 표지 변경이 다른 표지에 영향 없음 |
| 1E | U01 | 복원 계획과 영속 operation journal. 각 단계 재시작 때 roll-forward/rollback을 판단할 수 있도록 기록 | 파일 stage/메타데이터/SQLite/완료 표시 각각 직후 kill해도 다음 실행에서 상태 설명과 복구 가능 |

### 권장 인터페이스

아래 이름은 설계 제안이며 그대로 클래스를 많이 만들라는 의미는 아니다.

```text
LibraryRepository.mutate(command) -> LibraryChange
  read-current → validate → commit 을 한 큐/transaction에서 수행
  결과: revision, changedBookIds, warnings

LibrarySourceStore.stage(pickedFile) -> StagedSource
  결과: ownedPath, format, hash, validatedMetadata
  commit 전 중단되면 stage만 정리; 외부 사용자 원본은 삭제하지 않음

LibraryLoadResult = absent | valid(snapshot) | recovered(snapshot, issue) | corrupt(rawRefs)

RestorePlanner.plan(backup, currentSnapshot) -> RestorePlan
  추가할 책/표지/완독, 유지할 기존 상태, 충돌, 필요한 파일/용량

RestoreExecutor.execute(plan, operationId) -> RestoreResult
  같은 operationId 재시도는 멱등적
  committed 결과를 검증한 후에만 완료 안내
```

단기적으로 기존 SharedPreferences 형식을 유지하면서 queue와 복원 journal을 추가할 수 있다. 장기적으로 서재/묶음/표지 참조/완독을 SQLite transaction 하나로 통합하면 U01을 단순화할 수 있지만, **데이터 이관은 별도 단계**다. 이번 결함 수정과 동시에 저장소 전체를 교체하지 않는다.

### 기존 데이터 이관과 되돌리기

- 책 ID를 새로 만들지 않고 원본 경로만 앱 소유 경로로 교체한다. 원본/새 파일 둘 다 유효한 동안 먼저 새 경로를 검증한다. 없는 파일은 “재연결 필요”로 표시하고 독서 기록을 보존한다.
- 기존 primary/backup raw를 보존한 뒤 새로운 검사/복구 상태를 기록한다. 임의로 damaged 값을 정상 빈 목록으로 바꾸지 않는다.
- 공유 표지는 기존 참조 전체를 확인한 후 ID별 복사를 만든다. 모든 참조 이관 완료 전 공유 원본을 삭제하지 않는다.
- rollback은 앱 삭제/DB drop이 아니라 이전 reader가 읽을 수 있는 metadata snapshot과 file references의 복구로 설계한다. 기존 데이터보다 오래된 코드가 새 저장 포맷을 안전하게 읽는지 먼저 확인한다.
- OS kill 복구가 보장되기 전에는 “원자적 복원”이라고 사용자에게 설명하지 않는다.

## 2단계: 계약과 실패 격리 — 기능 수정

### 2A. 설정·콘텐츠 계약 (F07, F11, U04)

- 기본값, nullable 의미, 수치 범위, 폰트 ID, 테마/page style enum을 작은 명세로 정의한다.
- 초기에는 동일 JSON fixture를 Dart/Swift/Kotlin에서 검증하는 방식으로 시작한다. 생성기가 이득인 규모가 되면 기존 Palette 생성 방식을 참고한다.
- EPUB은 로컬 허용 범위와 배포 허용 범위를 구분하되 `배포 허용 ⊆ 앱 허용` 관계를 보장한다. 외부 리소스·script·fixed layout·파일 수/해제 한도·누락 spine fixture로 서버/앱 모두 검사한다.
- Locator/책갈피는 href뿐 아니라 네이티브가 읽을 수 있는 구조인지 검사한다. 검증 실패한 기존 레코드를 조용히 삭제하지 않고 복구 목록에 보존한다.

완료 기준: 0.5/3.0 경계와 3.5 거부 또는 안전 복구 결과가 세 플랫폼에서 같다. 서버가 배포 가능한 모든 대표 fixture를 앱에서도 준비할 수 있다. 새 보안 검사를 이미 캐시된 콘텐츠에 적용할 때 policy version을 사용한다.

### 2B. 오류 영향 범위 (F08, F09)

- runApp 이후 BootstrapState로 migration/loading/blocked/recoverable 상태 표시. 사용자가 재시도하거나 로컬 진단을 확인할 수 있도록 한다.
- 저널별 성공/격리/검증불가 결과를 반환하고, 정상 레코드는 순서대로 복구한다. 손상된 책만 자동 위치 저장을 제한한다.
- `ReaderError(code, recoverability, safeMessage, diagnosticsId)` 같은 작은 오류 계약으로 내부 경로·SDK 메시지를 기본 UI에서 분리한다. 유용한 원인 정보까지 catch-all로 없애지 않는다.

완료 기준: 하나의 손상 저널이 다른 책을 막지 않고, 손상 원문이 남으며, 오래된/중복 이벤트가 여전히 최신 위치를 덮지 못한다. 재시작 후 정상 책 위치가 바뀌지 않는다.

### 2C. 광고 attempt 수명 (F10, U05)

- 닫기 이후 지연 보상 허용, attempt별 단 한 번 지급, persistence 실패 재시도/안내, 영구 미도착 객체 정리를 각각 정의한다.
- 초기화 timeout과 재시도의 attempt ID를 구분한다. 이전 attempt의 늦은 성공/실패가 새 attempt 결과를 덮지 않도록 한다.
- 동의 거부/ATT 거부/설정 변경 중 광고 요청·기존 banner 제거 시점을 fake SDK와 실기기에서 검증한다.

되돌리기: 설정/저널 포맷의 이전 reader 호환 유지, 기능별 변경 단위 revert. 원문 격리 폴더와 사용자 기록은 rollback에서도 삭제하지 않는다. 광고 정리 변경을 되돌려도 이미 지급된 만료 시각을 줄이지 않는다.

## 3단계: 책임 분리 — 동작 유지 리팩터링

1. **Flutter 서재:** 순수 ShelfSnapshot 계산 → 액션 orchestration → presentation widget 순서. part extension이 State를 계속 직접 조작하는 형태로 파일만 나누지 않는다.
2. **준비기:** source store / bounded inspector / TXT converter / cache를 분리. 먼저 같은 입력에 같은 publication bytes와 contentRevision이 나오는 snapshot 검사를 고정한다. 불필요한 변환 결과 변경은 사용자의 기존 위치를 다른 revision으로 만들 수 있다.
3. **백업:** Codec/Planner/Executor를 분리하되 저장 경계는 하나. backup JSON 키 변경이나 새로운 충돌 정책은 별도 기능 패치로 취급한다.
4. **카탈로그:** API/verified downloader/installer 및 설치 상태 snapshot. Riverpod이 HTTP부터 파일 commit까지 직접 중복 수행하지 않게 한다.
5. **네이티브 리더:** 마지막으로 NavigationSession의 상태 전이를 분리. Android/iOS 한쪽씩 진행하되 매번 기존 동작 fixture를 양쪽에서 실행한다.

### 네이티브 상태 경계

```text
opening → restoring → ready
ready → relayout → restoring → ready
ready → preparingTurn → interactiveTurn → committingTurn → ready
interactiveTurn → cancelled → ready
(any active state) → closing → closed
(error) → recoverable / failed (늦은 callback은 세대 확인 후 무시)
```

현재의 capture/layout/render generation을 무작정 하나로 합치지 않는다. 각각이 막는 stale callback을 테스트로 고정한 뒤, Session이 상태와 세대의 단일 소유자가 되게 한다. VC/Activity는 UI를 갱신하고 `ready/failed/snapshot` 결과를 받는다.

완료 기준: 동일 fixture의 Locator/저널 sequence/DB 결과, 설정 적용, 텍스트 내용·페이지 이동 의미가 전후 동일. bridge API/DB schema를 바꿔야 한다면 이 단계의 단순 리팩터링과 분리한다.

되돌리기: 한 책임 이동당 독립 commit. 데이터 포맷 변경 없음이 원칙이므로 해당 commit만 revert 가능해야 한다. 생성 바인딩과 원본 Pigeon을 부분적으로 되돌리지 않는다.

## 4단계: 측정 기반 성능·자원 개선

### 먼저 측정할 시나리오

| 입력/상황 | 기록할 값 |
|---|---|
| TXT 1/10/20MiB, 장 구분 있음/없음 | first open/warm open P50·P95, Dart main isolate blocking, RSS peak, 변환 횟수 |
| EPUB 5/20/40MiB 및 이미지·spine 많은 책 | 준비/검증/Readium ready 시간, 임시 heap, 지원 한도 오류 안내 |
| 서재 100/1,000권, 카탈로그 100/1,000개, 폰트 다수 | 전체 JSON/manifest 조회 횟수, 첫 결과 시간, 스크롤 rebuild/raster 시간 |
| 연속 100회 넘김·역방향·반쯤 취소 | frame capture latency, dropped frames, RSS가 안정 구간에 도달하는지 |
| 회전/접힘 20회, 광고 숨김/만료, background/foreground | locator drift 0, stale callback 횟수, WebView/bitmap 증가 여부 |
| 삭제/재설치/백업 실패/복원 반복 | 파일·DB 용량, live reference 대비 orphan bytes, cleanup 후 보존 검증 |

처음 측정 전 절대적인 “몇 ms 이내/몇 MB 이내” 목표를 임의로 약속하지 않는다. 기준 기기·OS·refresh rate·프로파일 모드를 고정하고 사용자 체감 기준과 첫 baseline으로 합의한다.

### 측정 후 우선 후보

- 준비 캐시 hit이면 변환 반복 생략. converter/policy version과 metadata 포함 키로 내용 동일성 유지.
- TextPublicationMap을 필요한 legacy migration 시에만 만들거나 isolate 결과로 전달.
- 설치 여부 한 번에 조회, 실제 변경된 항목만 갱신.
- iOS journal I/O를 순서 있는 writer로 이동하되 **저장 전에 이벤트를 보내지 않는다**. 닫기/background flush deadline 검증.
- orphan cleanup은 먼저 dry-run 통계와 참조 무결성 검사. 읽던 revision·백업 복원 중 stage·사용자 외부 파일은 정리하지 않는다.
- 프레임 캐시 크기는 현재 상한을 유지하면서 측정. 무조건 prefetch를 늘려 빠르게 보이게 하지 않는다.

되돌리기: 최적화 경로와 기존 경로의 결과 동등성 검사를 유지. 이전 캐시/원본은 당장 제거하지 않고 새 캐시 miss 시 안전한 재준비 가능. 정리 정책은 grace period 뒤 삭제하며 먼저 목록만 산출한다.

## 5단계: 청소와 운영 검사 자동화

- `.env.admob.example`, 직접 미사용 `intl`을 하나씩 정리하고 lockfile 변화 확인. 네이티브 등록·동적 글꼴·legacy 데이터 접근 코드는 보존.
- CI를 수동 release 빌드만이 아니라 PR 정적 분석/Flutter tests/JS/Palette/Node 22 서버 tests와 플랫폼별 native tests로 구분. Flutter 버전도 재현 가능하게 고정한다.
- Pigeon/Palette/branding 생성 검사는 임시 출력→diff 방식으로 수행. 일반 감사/빌드가 기존 소스를 고치지 않게 한다.
- Functions emulator에서 admin 없음/다른 issuer/일반 사용자/revision conflict/삭제 중 실패와 재시도/미공개 다운로드 거부 검사.
- 실제 배포 상태는 별도 read-only 운영 체크: rules/IAM/CORS/지역/최대 instance/예산 알림/스토어 바이너리 버전/SDK 매핑. 자동 변경하지 않는다.

완료 기준: 소스 원본과 생성 결과 일치, 기능/기기 회귀 통과, 불필요한 의존성 제거에 따른 새 version upgrade 없음. 되돌리기는 제거 commit 복원이며 사용자 데이터 마이그레이션은 포함하지 않는다.

## 필수 회귀 테스트 표

| 구분 | 사례 | 통과 조건 | 방식 |
|---|---|---|---|
| 서재 저장 | import 2건 + 다운로드 + 삭제 순서 교차 | 지정된 명령 순서에 해당하는 최종 항목/묶음 참조 유지 | 저장소 단위·fault injection |
| 원본 보존 | 10권 import, 9권 미열람, picker cache 제거 | 10권 모두 독서·백업 가능 | 임시 파일 + 양 OS 파일 선택 실기기 |
| 원본 실패 | 크기 초과·읽기 권한 없음·복사 disk full | 실패 항목만 제외, 다른 파일 계속, 반쪽 metadata 없음 | 단위/실기기 |
| 손상 복구 | primary만 손상 / primary+backup 손상 | 복구 또는 명확한 오류, raw 보존, 무언 덮어쓰기 없음 | 저장소 단위 |
| 표지 | 같은 그림의 책 2권+묶음 복원 후 하나 reset | 나머지 표지 파일·참조 유지 | backup/CoverStore 단위 |
| 복원 재시도 | 각 pref write/DB commit 한 번 실패 | 재시도 후 표지·완독·순서·위치·전역 설정 동일 | fault injection |
| 복원 중 종료 | staging/각 commit 경계에서 process kill | 다음 실행에서 재개/복구, 유령 항목/자료 소실 없음 | 별도 test app/native harness |
| 데이터 업데이트 | SQLite 1/2/3→4, 기존 key/legacy cache | locator·책갈피·설정 보존, 기존 위치 덮어쓰기 없음 | migration fixtures |
| 세션 | old/duplicate/out-of-order callback, ACK 뒤 최신 write | 최신 위치/전역 설정만 보존 | 기존 coordinator/store/native journal tests 확장 |
| 저널 오류 | 한 책 JSON/previous 손상, orphan session | 관련 책 복구 안내, 다른 책 사용, raw 보존 | native + coordinator |
| 글자 설정 | 0.5/3/3.5, nullable spacing, remote font 누락 | 양쪽 같은 수용/거부·복구, 전역 적용 | Dart/Kotlin/Swift 계약 |
| 책 호환성 | 외부 CSS/image/script, encrypted/fixed layout, ZIP 경계 | 배포 허용 파일은 앱에서 준비 가능, 악성/미지원 거부 | TS+Dart 공통 fixture |
| 이어읽기 | 단일↔두 열↔스크롤·폰트 변경 후 종료 재오픈 20회 | 같은 문자가 보이고 누적 전후 이동 없음 | iPhone/iPad/Galaxy Fold 실기기 |
| 페이지 넘김 | tap/button/drag, 상·중·하 모서리, 반쯤 취소/빠른 연속 | 정확히 한 번 이동/취소, 글자/이미지 일치 | native automation + 실기기 |
| 검색 | 재검색 중 이전 결과, 닫기, 결과 0/500, 반환 위치 | 오래된 결과 무시·자원 정리·원위치 복귀 | native 테스트 |
| 책갈피 | 100개/긴 이름/이모지/저장 실패/삭제 취소 | 무언 삭제·잘린 UTF-16 데이터 없음 | codec + native UI |
| 끝 안내 | 한 화면 장·최종 spine·두 열·RTL | 끝에서만 안내, 확인 후 다음 권, 자동 완독 없음 | JS + native |
| 광고 | 보상 before/after close/duplicate/never, 저장 실패 | 1회 지급·2시간 보존·누적 객체 제한·실패 안내 | fake SDK + test ads |
| 광고 영역 | 리워드 시작/만료와 재조판·닫기 동시 | 영역 제거/복원, 본문 앵커 보존 | 실기기 |
| 동의 | standard, personalized+ATT denied, OS에서 ATT 변경 | 독서 가능, 설정과 SDK 요청 상태 일치 | fake + 양 OS 실기기 |
| UI | 빈 목록·오프라인·긴 제목·200% 글씨·좁은 폭·힌지 | clipping/overflow/탭 불가 없음, retry/cancel 명확 | widget + native accessibility |
| 청소 | 고아 파일 dry run, legacy/source/revision 참조 포함 | live 자료는 삭제 후보에서 제외 | 파일 fixture |

## 바로 다음 패치 범위 제안

**첫 패치는 0단계 + 1A~1D의 데이터 보존을 대상으로 하되, 검토 단위를 나누는 것이 좋다.** 그 다음 재시작 복구(1E)와 계약 정합성(2단계)을 진행한다. 네이티브 리더 대규모 분리는 그 이후다. 단계별 검증 결과를 기준으로 다음 범위를 정한다.
