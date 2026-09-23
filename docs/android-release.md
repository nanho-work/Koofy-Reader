# Android 최초 릴리스 준비

## 업로드 키 생성

쿠피리더를 처음 등록할 때만 새 업로드 키를 만든다. 이미 Google Play에
업로드한 앱이라면 기존 업로드 키를 먼저 확인한다.

프로젝트 루트의 로컬 터미널에서 실행한다.

```sh
python3 scripts/setup_android_signing.py
```

비밀번호를 두 번 입력한다. 화면에는 표시되지 않으며 명령 인자나 셸 이력에
비밀번호를 넣지 않는다. 인증서 이름은 `Koofy Reader Upload`, 별칭은 `upload`다.
RSA 3072비트, JKS 형식으로 생성하며 저장소와 키에 같은 비밀번호를 사용한다.

- `android/upload-keystore.jks`: 업로드 키. 별도 안전한 장소에 백업한다.
- `android/key.properties`: Gradle 서명 설정. 비밀번호를 포함하므로 공유하지 않는다.
- 두 파일은 Git 제외 대상이며 생성 시 소유자만 읽고 쓸 수 있게 한다.
- 기존 파일이 있으면 중단한다. 업데이트할 때 새 키를 생성하거나 덮어쓰지 않는다.
- 설정 파일의 Unicode escape는 Java Properties의 특수문자 처리를 위한 것으로,
  암호화가 아니다. 비밀번호도 키와 함께 복구 가능한 안전한 장소에 보관한다.

## 빌드와 배포

```sh
flutter build appbundle --release
```

결과는 `build/app/outputs/bundle/release/app-release.aab`다.
빌드 후 업로드 키와 AAB의 인증서 일치, applicationId, 버전 코드,
릴리스 광고 테스트 도구 비활성화, 번들 검증을 확인한다.
현재 버전이 이미 업로드된 적이 있다면 versionCode를 증가시켜야 한다.

AAB는 직접 설치하는 APK가 아니다. Play Console 테스트 트랙을 통해 설치하고
최초 광고 선택, 독서·이어읽기, 다운로드, 광고·보상 기능을 릴리스 버전으로 검증한다.
디버그 앱을 삭제하여 설치하는 경우 기존 기기 내 책과 기록이 사라질 수 있으므로
임의로 삭제하지 않는다.

개인정보·지원 웹페이지 공개, Play Console 앱 정보와 데이터 보안 등 입력,
테스터 등록 및 심사 제출은 별도 작업이다.

## 2026-09-21 릴리스 산출물 검증

- 릴리스 AAB 빌드 성공: `flutter build appbundle --release`
- applicationId: `com.koofylab.koofyreader`
- 버전: `1.0.0` / versionCode `1`
- minSdk `24` / targetSdk `36`, debuggable 및 testOnly 비활성
- 파일 크기: 57,909,487 bytes
- AAB SHA-256: `0347b1a50c3cf5641347ca8c6a593f43b7820fb5420a82e2a05830c50d467613`
- 업로드 키 인증서와 AAB의 서명된 콘텐츠 687개 일치 및 서명 무결성 확인
- Google bundletool 1.18.1 `validate` 통과
- 번들 설정 `PAGE_ALIGNMENT_16K`, 포함된 arm64-v8a/x86_64 라이브러리의 LOAD 정렬 검사 통과
- 최신 개인정보 방침 자산 및 Flutter 네이티브 심볼 메타데이터 포함 확인
- 릴리스에서 LevelPlay 테스트 도구 비활성화 조건 확인

처음 발생한 Flutter 심볼 검사 오류는 Mac에 Android cmdline-tools가 없어서 발생했다.
Google 공식 macOS arm64 배포본을 체크섬 확인 후 기존 Android SDK에 추가했고,
이후 Flutter 릴리스 빌드가 성공했다. 기존 SDK 라이선스 파일은 수정하지 않았다.
`flutter doctor`에는 라이선스 상태를 확인하지 못했다는 경고가 남아 있다.
새 명령줄 도구의 SDK 목록 조회는 성공했으며, 기존 라이선스 파일은 유지했다.
라이선스 일괄 동의 명령은 실행하지 않았다. 경고와 별개로 릴리스 빌드와 번들 검증은 통과했다.

Play Console 업로드·심사·실기기 릴리스 테스트는 아직 하지 않았다.
16 KB 기기에서의 실제 런타임 테스트도 남아 있다.
이 AAB는 최초 비공개 테스트 업로드용이며 정식 출시 승인이나 동작 검증 완료를 뜻하지 않는다.

## 2026-09-22 내부 테스트용 빌드 2

사용자 요청에 따라 현재 배포 범위는 Google Play **내부 테스트**다. 비공개/공개 테스트 및 프로덕션 출시는 진행하지 않는다. 실기기 동작은 사용자가 직접 확인한다.

- 최신 코드로 `flutter build appbundle --release` 성공.
- 패키지 `com.koofylab.koofyreader`, 버전 `1.0.0`, versionCode `2`.
- minSdk `24`, targetSdk `36`, debuggable/testOnly 비활성 확인.
- Google bundletool 1.18.1 검증 통과.
- 기존 업로드 인증서와 번들 콘텐츠 687개 서명 일치 및 무결성 확인.
- 파일 크기 57,909,483 bytes.
- SHA-256 `f9c246ba93478d47ec8e57c45f3f9fd19e607b80bd1b7d730fa186d2e8e50e5d`.
- 사용자가 지정한 koofyLab 계정(`4982189337387504901`)에 쿠피리더 앱 생성 완료. Play 앱 ID: `4973909280783739116`.
- 한국어 기본 언어, 무료 앱, 패키지 이름 확인 완료. 생성 시 정책·수출법 선언은 사용자가 직접 확인하고 앱 만들기를 실행했다.
- 내부 테스트 출시 초안 `1.0.0 (2)` 및 한국어 출시 노트 저장. AAB 업로드와 내부 출시 완료 여부는 아래 후속 기록으로 확인한다.
- 사용자는 Google 그룹 2개를 선호하지만, 현재 내부 테스트 UI에는 이메일 목록만 제공된다. 대안으로 `choi1278@gmail.com` 사용을 승인했다. 공용 이메일 목록 생성 확인은 별도로 대기 중이다.
- Chrome ChatGPT 확장 프로그램의 파일 URL 접근을 사용자 요청으로 활성화한 뒤 AAB 업로드 및 Play Console 처리 완료.
- 출시 검토 화면에서 `2 (1.0.0)`, API 24 이상, target SDK 36, 설치 크기 16.9 MB 확인. ReTrace 매핑과 네이티브 기호 첨부 확인.
- 검토 결과 오류 없이 ‘테스터 미지정’ 경고 1개가 남았다. 자동 승인 검토가 계정 공용 이메일 목록 생성과 테스터 미지정 상태의 출시를 보류했다. 공용 목록 생성에 대한 사용자 확인을 받은 뒤 목록 적용 및 출시를 완료해야 한다. **아직 설치 가능한 내부 테스트 출시는 완료하지 않았다.**
