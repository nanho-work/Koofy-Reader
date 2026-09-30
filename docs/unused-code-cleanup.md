# 미사용 기존 코드 정리

## 2026-09-30 재점검

이번 점검에서는 Android 글꼴 중복 패키징만 수정했다. 아래 추가 정리 후보는 아직 삭제하지 않았다. 기존 미커밋 변경과 사용자 데이터는 보존했다.

### 적용 및 검증

- Android가 iOS Resources 전체와 assets/fonts를 동시에 자산으로 읽어, 같은 기본 글꼴 3개와 catalog.json을 루트 및 Fonts/ 아래에 두 번 포장했다.
- Gradle Sync 작업으로 공유 JS와 번역 아이콘만 추출하고, 글꼴은 기존 Android 로더가 사용하는 루트 경로에 한 번만 포함한다. iOS 글꼴 심볼릭 링크와 원본은 유지한다.
- `:app:mergeReleaseAssets` 성공. 최종 병합 자산에서 글꼴 3개의 SHA-256이 catalog와 일치하고 Fonts/ 중복이 없으며, reader_anchor.js·reader_selection.js·번역 아이콘 2개가 남는 것을 확인했다.
- 기존 AAB의 중복 글꼴 압축 크기 합계는 약 1.03 MB. 새 AAB는 재생성하지 않았으므로 이미 만든 1.3.3(10) 파일에는 아직 이 정리가 반영되지 않았다.

### 추가 정리 후보

| 위치 | 근거 및 조치 후보 |
| --- | --- |
| iOS ReaderSettingsViewController.swift의 translationTapped, speechTapped | 예전 버튼용 @objc 메서드. 해당 클래스의 selector 연결 및 문자열 참조 없음. 현재 번역은 UIAction, 듣기는 테이블 선택에서 콜백을 직접 호출한다. KoofyReaderViewController의 동명 speechTapped는 실제 사용 중이므로 구분해야 한다. |
| legacy_reading_progress.dart의 ReadingLocator.toAnchor | 앱·테스트·브리지 호출 참조 없음. 메서드 단위 정리 후보이며 호환 모델 파일 전체 삭제 대상이 아니다. |
| pubspec.yaml의 intl 직접 의존성 | Dart 앱·테스트에서 직접 import 없음. 제거 시 전이 의존성과 lockfile 변경을 확인해야 하며, 실제 용량 절감은 미측정. |
| .env.admob.example | 현재 스크립트·앱에서 예시 변수들을 읽지 않음. 과거 직접 AdMob 설정 템플릿으로 정리 후보. 실제 LevelPlay AdMob 어댑터 및 플랫폼 앱 ID 설정은 별개이며 유지해야 한다. |
| 작업 폴더의 분석 범위 | 루트 flutter analyze는 work/ 아래 과거 캡처 테스트와 Firebase CLI 예제까지 분석해 10건을 보고함. 운영 코드 문제가 아니며 analysis_options의 work/** 제외를 검토할 수 있다. |

### 보존 판단

- lib의 Dart 파일 70개는 main.dart를 제외하고 앱 내부 import/export/part 참조가 있다. 이 결과가 모든 public 메서드의 사용을 보장하지는 않는다.
- Readium shared/streamer/navigator는 현재 단일 리더 경로에서 사용한다. 과거 lib/features/reader 엔진은 추적 파일에서 발견되지 않았다.
- Readium TTS·OfflineSpeechEngine·Media3는 본문 음성 재생에서 사용한다. ML Kit 번역, LevelPlay·Unity Ads·AdMob 어댑터도 현재 기능 또는 SDK 등록 경로가 있으므로 유지한다.
- sqlite3_flutter_libs는 직접 Dart import가 없어도 Drift NativeDatabase용 네이티브 라이브러리를 제공한다. Pigeon은 pigeons/reader_api.dart 생성 도구다. 미사용으로 판단하지 않는다.
- legacy 호환 파일은 이전 기록·북마크 표시와 원문 보존에 필요하다. 네이티브 생명주기·광고 콜백, Pigeon 생성물, 디자인 생성 원본, 테스트 EPUB, iOS LaunchImage도 유지한다.
- 로컬 디스크 사용량은 build 약 9.4 GB, .dart_tool 약 2.0 GB, work 약 2.4 GB, ios/Pods 약 312 MB, functions/node_modules 약 143 MB였다. 캐시·SDK·릴리스·운영 자료가 섞여 있어 미사용 소스와 구분한다. 이번에는 삭제하지 않았다.

### 확인 범위와 한계

- Flutter 운영 코드·테스트·브리지 Dart 정적 분석: No issues found.
- Firebase Functions: tsc --noEmit 통과(noUnusedLocals 설정 활성).
- 네이티브 선언 참조, selector, 빌드 설정, 자산 경로 및 생성 스크립트, 의존성 사용 경로를 정적으로 확인했다. 별도 네이티브 전용 dead-code 분석기나 모든 기능의 실기기 실행 검증은 수행하지 않았다.
- 배포된 콘솔 설정은 조회·변경하지 않았으며, 릴리스 재빌드·업로드도 하지 않았다.

---

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
