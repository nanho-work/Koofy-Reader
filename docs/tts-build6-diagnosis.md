# Android 빌드 6 책 읽어주기 실패 분석

2026-09-27. 연결된 SM-F956N에서 `versionName=1.2.0`, `versionCode=6` 확인. 기존 앱과 사용자 데이터는 변경하지 않았다.

## 증상과 기기 로그

- 사용자가 듣기 설정의 한국어 음성 목록과 미리 듣기 성공을 확인했다.
- 책의 재생 버튼은 음성 엔진 사용 불가 안내를 표시한다.
- 재현 시 17:17:33.918 Google TTS 서비스 바인딩, 17:17:33.929 연결, 17:17:34.393 연결 설정 후 17:17:34.397 앱 오류 토스트가 확인됐다.
- 삼성 private engine 접근 제한 뒤 Google 엔진으로 연결된다. 이 제한 메시지 자체를 이번 실패 원인으로 판단하지 않는다.

## 배포 바이너리에서 확인한 원인

대상: `work/release/1.2.0-6/koofy-reader-1.2.0-6.aab`. 포함된 proguard.map 및 DEX를 직접 확인했다.

Readium 3.1.2 `Publication.ServicesBuilder`는 서비스 클래스의 `simpleName`을 Map 키로 사용한다. R8 최적화·난독화 이후 원래 서비스 인터페이스 참조가 구현 클래스로 바뀌었으며:

- 본문 추출 `DefaultContentService` → `O5.o`
- 표지 `ResourceCoverService` → `N5.o`

두 클래스의 `simpleName`은 모두 `o`다. 실제 `classes.dex`의 ServicesBuilder 생성자(최적화 후 `I1.c`)에서 `O5.o.getSimpleName()`으로 content 쌍을 만든 뒤 `N5.o.getSimpleName()`으로 cover 쌍을 만들고, Map을 생성한 후 null 값을 제거한다. EPUB 파서는 content factory를 제공하지만 cover 인수는 기본 null이다. 따라서 content 등록이 뒤의 cover=null에 덮인 후 제거된다.

`TtsNavigatorFactory`는 `publication.content()`가 null이면 생성되지 않는다. 앱의 `ReaderSpeech.prepare()`는 이 실패를 null로 반환하고, `start()`가 이를 모두 음성 엔진 사용 불가로 안내한다. 반면 음성 엔진은 factory 생성보다 먼저 준비되어 있으므로 고정 문장 미리 듣기는 가능하다.

이는 개발용 테스트에서는 통과하고 난독화된 배포 빌드에서만 책 읽어주기가 실패하는 원인이다. 정상 엔진 종료·재생성은 별도 개선 후보이며 이번 직접 원인으로 확정하지 않는다.

## 수정 및 검증 계획

1. Readium 서비스 식별에 쓰이는 타입의 이름과 타입 자체가 최적화로 바뀌지 않도록 범위를 제한한 R8 consumer 규칙을 적용한다. 단순히 앱 전체 최적화를 끄는 방식은 사용하지 않는다.
2. 음성 초기화, 본문 추출 서비스 없음, 읽을 문장 없음, 재생 준비 실패를 구분해 안내한다. 진단에는 책 내용이나 파일 경로를 기록하지 않는다.
3. 최적화된 릴리즈 산출물의 서비스 키 충돌 여부와 ContentService 존재를 확인한다.
4. 동일한 `미리 듣기 → 설정 닫기 → 책 재생` 경로와 TXT/EPUB 첫 페이지·중간·끝, 일시 정지·다시 시작을 릴리즈 구성에서 검증한다.

## 패치 및 검증 결과

- bridge의 `consumer-rules.pro`를 연결했다. Readium publication service 인터페이스의 이름과 타입을 보존해 R8의 인터페이스 병합 및 이름 충돌을 차단한다. 앱 전체 최적화를 끄지 않았다.
- `ReaderSpeech`는 음성 엔진 초기화 실패, 본문 서비스 없음, 현재 위치의 읽을 본문 준비 실패를 구분한다. 원시 오류나 본문 없이 실패 범주만 `KoofySpeech`에 기록한다.
- `tool/check_readium_release.py`는 AAB에 포함된 mapping 또는 APK 빌드의 mapping을 검사한다. 기존 6번 AAB에서는 실패했고 수정한 릴리즈 mapping에서는 7개 서비스 식별자 보존으로 통과했다.
- `flutter build apk --release --no-pub` 성공. 에뮬레이터에 실제 릴리즈 APK를 설치하고 기본 안내 책(TXT 변환)을 열어 재생을 확인했다. 시작 설명에서 다음 ‘서재에서 책 찾기’ 항목까지 자동 진행하며 문장 강조와 일시정지 버튼이 유지되는 화면을 확인했다.
- SM-F956N의 별도 테스트 패키지에서 실제 설치된 한국어 음성으로 미리 듣기 → 책 본문 재생 → 백그라운드 중단을 검증했다. 엔진의 실제 `isSpeaking` 상태를 확인했다. 이 계측 테스트 자체는 Debug 구성으로, 실기기 스토어 앱을 교체한 테스트는 아니다.
- 실기기 테스트 2개 통과: 실제 TTS 재생 흐름, 본문 서비스 없음과 엔진 초기화 실패 구분.
- 에뮬레이터 회귀 테스트 5개 통과: 오프라인 음성 정책, 긴 문장 분할, 듣던 문장 복원, 백그라운드·수동 이동 중단과 독서 위치 보존, 초기화 중 이탈 시 지연 재생 차단.

기존 휴대폰의 스토어 앱 `1.2.0 (6)` 및 사용자 데이터는 교체하지 않았다. 이번 APK는 로컬 검증용이며 버전 번호를 올리거나 스토어에 업로드하지 않았다. 향후 배포는 새 build number로 생성하고 해당 산출물을 검사해야 한다. iOS 코드는 이번 Android R8 수정 대상이 아니다.

검사 예:

```sh
python3 tool/check_readium_release.py build/app/outputs/mapping/release/mapping.txt
python3 tool/check_readium_release.py path/to/new-release.aab
```
