# 미사용 기존 코드 정리

> 과거 단계의 구현·검증 기록입니다. 현재 단일 리더 전환 상태는 [Readium 전환 문서](readium-cutover.md)를 따릅니다. 아래의 기존 리더 선택·보존 설명은 현재 실행 경로가 아닙니다.

2026-09-19. 새 서재 UI·네이티브 Readium 연결을 유지하고, 기존 앱과 테스트에서 소비하지 않는 코드 및 의존성만 제거했다. 사용자 데이터나 파일을 삭제하는 마이그레이션은 포함하지 않는다.

## 판단 기준

- `lib/main.dart`에서 import/export/part 연결을 따라 확인한 결과, 기존 Dart 파일은 모두 앱 진입 경로에 연결되어 있었다. 파일이나 리더 폴더를 통째로 제거하지 않았다.
- Dart 구문 트리의 메서드 선언, 전체 코드의 호출·프로퍼티 접근, 저장 형식과 파일 자원의 사용 경로를 함께 확인했다. 메서드 이름 검색만으로 삭제하지 않았다. 예를 들어 `PaginatedText.operator []`는 `pages[left]`·`pages[right]`로 사용되므로 유지한다.
- 테스트에서 사용 중인 엔진 API와 Flutter 프레임워크가 호출하는 생명주기 콜백은 유지했다. 삭제한 API에 대한 테스트 케이스를 없애거나 검증 조건을 약화하지 않았다.

## 제거 내용

| 대상 | 제거 항목 | 현재 사용 경로 |
| --- | --- | --- |
| `AppConstants` | 이전 서재 그리드 상수 6개 | 새 서재가 가용 폭·글자 배율로 배치 계산 |
| `AppConstants` | `readerStructureIndexPrefix` | 구조 인덱스는 준비된 콘텐츠 캐시의 일부로 저장 |
| `BookRepository` | `readBookContent` 선언·구현과 테스트 대역의 대응 메서드 | `readPreparedBookContent` 사용 |
| `PaginatedText` | `toBreakOffsets`, `fromBreakOffsets` | 현재 페이지 범위와 문자열 접근 사용 |
| `ReaderLayoutController` | `resolveTapAction`, `ReaderTapAction` enum | `ReaderNavigationController.resolveTapCommand` 사용 |
| `ReaderSearchController` | `findQueryOffsets` | `ReaderEngine` → `ReaderSearchService` → 문서 검색 사용 |
| `ReaderEngine` | `locatorForOffset` | 진행률 저장·검색에서 필요한 Locator 생성 경로는 유지 |
| `RewardedAdService` | 참조 없는 `isReady` getter | 기존 광고 로딩·표시·재로딩 흐름 유지 |
| 의존성 | `cupertino_icons`, `hive`, `hive_flutter` | Material 아이콘과 SharedPreferences/SQLite 사용 |

함수·접근자 7개, 상수 7개, enum 1개를 정리했다. 코드와 테스트 대역에서 134줄을 제거했다. `flutter pub get --offline`으로 잠금 파일을 갱신했으며 제거된 의존성 3개 외의 버전 변경은 없었다.

## 유지한 항목

- 기존 리더의 라우트·페이지네이션·위치 복원·검색·책갈피·설정: 기존 기록을 이어 읽는 데 사용한다.
- SharedPreferences 마이그레이션과 이전 독서 기록 필드: 기존 저장 형식을 읽는 데 필요하다.
- `assets/fonts/`의 글꼴: 기존 리더의 글꼴 선택·저장된 글꼴 키로 동적 로딩한다. 정적인 파일명 참조가 없다는 이유로 제거하지 않는다.
- 샘플 책, 광고 기능, 플랫폼 실행 코드, 이전 설계 기록.
- 이번에 추가한 서재 화면, 독서 상태 통합, 네이티브 코드, SQLite v2 및 Pigeon 계약.

## 검증 명령

- 정적 분석: 이상 없음.
- Flutter 전체 테스트: 기존 124개 모두 통과. 테스트 케이스 수와 검증 조건 유지.
- Android 디버그 APK 및 iOS 시뮬레이터 앱: 모두 빌드 성공.
- 제거한 패키지의 import, `pubspec.yaml` 선언, `pubspec.lock` 항목이 남아 있지 않음을 확인.

```sh
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
git diff --check
```

네이티브 본문 코드와 브리지 계약은 변경하지 않았다. 이 정리는 기존 리더 전체 제거 또는 독서 기록 형식 이전을 의미하지 않으며, 실제 폴더블 기기의 추가 검증 범위는 기존과 같다.
