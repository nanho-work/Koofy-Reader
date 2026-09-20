# 쿠피리더 책·표지·글꼴 배포

## 구현 범위와 현재 상태

2026-09-20: 로컬 구현 이후 운영 연결까지 반영했다. 사용자에게서 Quiz_Site 배포 완료를 전달받았고 관리자 책 관리 경로가 HTTP 200을 반환하는 것을 확인했다. 쿠피리더 Firebase 함수 2개, 규칙, 인덱스와 전용 계정 권한은 이번 작업에서 배포했다.

- 서버: Koofy-Reader의 `functions/` (TypeScript, Node.js 22, Firebase Functions 2세대).
- 운영 화면: 기존 Quiz_Site 관리자 → 쿠피리더 → 책·표지 / 글꼴.
- 사용자 앱: 내 서재 상단 다운로드 아이콘 → 책 / 글꼴 목록 → 다운로드.
- 책과 표지는 내 서재에 추가된다. 글꼴은 Android/iOS 네이티브 Readium 보기 설정의 마지막 목록에서 선택한다.
- 기존 관리자 로그인 1회만 사용한다. 쿠피리더용 로그인 또는 사용자 앱 로그인을 추가하지 않았다.
- 공개한 콘텐츠는 누구나 내려받는 모델이다. 유료 판매, 구매 권한, DRM, 개인 독서 기록의 서버 동기화는 이번 범위가 아니다.

리소스는 읽기 전용 조회로 확인했다: 프로젝트 `koofy-reader`, Firestore `(default)` / `asia-northeast3`, Storage `koofy-reader.firebasestorage.app` / `US-EAST1`. 함수는 DB와 같은 서울에 둔다. 업로드 처리와 미국 버킷 간에는 지역 간 전송이 발생할 수 있다.

## 관리자 사용 순서

1. 기존 총괄 관리자 계정으로 로그인하고 쿠피리더를 선택한다.
2. 책 또는 글꼴 이름, 제작자, 설명, 배포 권한·이용 조건을 작성하고 **초안 만들기**를 누른다.
3. 책은 EPUB 또는 TXT 한 개와 표지를 올린다. 글꼴은 실제 파일에 맞는 굵기(예: Light 300, Regular 400, Bold 700)를 선택하고 OTF/TTF를 각각 올린다.
4. 등록 파일과 정보를 확인한 뒤 **앱에 공개**를 누른다.
5. 앱의 다운로드 목록을 새로고침하고 받는다. 글꼴은 책을 열어 보기 설정에서 선택한다.
6. 이미 공개한 항목을 수정하면 기존 공개 버전은 그대로 유지된다. **수정 내용 공개**를 누를 때 새 스냅샷으로 교체한다.

비공개 전환은 신규 목록 조회와 신규 다운로드 주소 발급을 막는다. 이미 받은 파일은 기기에 남고, 이미 발급한 서명 URL은 최대 5분간 유효하다.

초안에서 파일 제외는 공개 중인 스냅샷을 바로 바꾸지 않는다. 여러 관리자가 같은 버전을 수정하면 서버가 409 충돌을 반환한다. 새로고침 후 최신 상태에서 다시 작업한다.

## 데이터와 접근 경계

Firestore:

- `readerContent/{id}`: kind, 제목·제작자·설명·이용 조건, revision, 초안 assets, published, publishedContent, updatedAt.
- `publishedContent`: 공개 시점 메타데이터·파일 목록·version을 함께 저장한 불변 스냅샷.
- `readerAudit/{id}`: 관리자 UID, 작업, 대상 ID, 변경 revision, 시각. 서버 전용 기록이며 조회 UI는 아직 없다.

Storage: `readerContent/{id}/{uploadUUID}/{slot}.{extension}`. 파일은 덮어쓰지 않는다. SHA-256, 크기, 확장자, 콘텐츠 유형을 함께 저장한다.

`readerAdmin`은 Authorization Bearer의 Firebase ID 토큰을 **기존 프로젝트 `slimestrikeforce`**의 Admin Auth 인스턴스로 검증하고 `superAdmin === true`를 요구한다. 화면의 로그인 여부만 믿지 않으며 요청에서 신뢰할 프로젝트 ID를 받지 않는다. 토큰의 서명·발급자·대상·만료를 SDK로 검증한다. 매 요청 계정 조회를 하는 토큰 폐기 확인은 사용하지 않으므로, 권한을 회수해도 이미 발급된 토큰의 잔여 수명(통상 최대 1시간) 동안 권한이 남을 수 있다. 즉시 폐기가 필요하면 기존 인증 프로젝트에서의 최소 조회 권한과 `checkRevoked`를 별도로 적용해야 한다.

`readerCatalog`는 공개 스냅샷만 읽는다. 파일 요청 시 공개 상태, 공개 버전과 슬롯을 다시 확인하고 5분 유효 GCS 서명 URL을 발급한다. 초안 경로와 임의 Storage 경로는 서명하지 않는다.

Firestore/Storage SDK의 클라이언트 직접 읽기·쓰기는 모두 거부한다. 서버는 서비스 계정으로 처리한다. 관리자 브라우저나 앱에 서비스 계정 비공개 키를 넣지 않는다.

CORS 허용 주소는 `READER_ADMIN_ORIGINS`에 쉼표로 지정한다. 기본은 `https://admin.koofy.co.kr,http://localhost:3000`. 실제 관리자 호스트가 다르면 정확한 origin을 추가해야 한다. CORS는 관리자 권한 검증을 대체하지 않는다.

## 파일 제한과 기기 저장

- TXT: 입력 및 UTF-8 변환 후 최대 20MiB. UTF-8(BOM 선택), BOM이 있는 UTF-16 LE/BE, CP949/EUC-KR을 읽고 UTF-8·LF로 저장한다. 빈 내용, 읽을 수 없는 인코딩, 본문에 사용할 수 없는 제어 문자는 거부한다.
- EPUB: 최대 20MiB, 암호화되지 않은 가변 레이아웃 EPUB. ZIP 경로·중복·암호화 플래그·팽창 크기, container/OPF 구조를 검사한다. 메타데이터 읽기는 개별 2MiB/합계 8MiB로 제한한다. EPUBCheck의 전체 규격 검증을 대체하지 않는다. `encryption.xml`이 있는 EPUB는 글꼴 난독화만 있는 경우도 현재 제외한다.
- 표지: 최대 5MiB, 정지 PNG/JPEG/WebP, 최대 2,500만 픽셀. 서버에서 최대 900×1200 WebP로 재인코딩한다.
- 글꼴: 파일당 최대 10MiB, 정적 OTF/TTF, 100~900의 100 단위 굵기. SFNT 서명·테이블 경계·필수 테이블을 검사한다. 가변 글꼴·WOFF는 지원하지 않는다.
- 목록: 40개씩 페이지 조회. 앱은 스크롤 아래의 더 보기로 다음 목록을 읽는다.

앱은 비공개 앱 저장소 `cloud_reader/books`와 `cloud_reader/fonts`에 저장한다. 다운로드 중에는 `.part` 파일을 사용하고 크기와 SHA-256이 일치한 후 이름을 바꾼다. 모든 글꼴 굵기의 다운로드가 끝나야 `fonts/catalog.json`을 원자적으로 교체한다. 네이티브 리더도 해시·경로·파일 헤더를 다시 검사하고 잘못된 글꼴은 제외한다.

글꼴 ID는 `remote_<32자리 ID>`, CSS 이름은 안전한 고정 접두어와 ID로 만든다. Android와 iOS는 동일한 다운로드 manifest를 읽으며 WebView의 기존 로컬 파일 공급 방식을 사용한다. 기존 폰트 변경 시 위치 복원·책장 넘김 처리 경로는 유지한다.

책 공개 버전은 별도 로컬 책 ID를 갖는다. 새 버전을 받더라도 이전 책과 읽던 위치는 덮어쓰지 않는다. 동일 버전을 다시 받으면 중복 등록하지 않는다. 내려받은 파일은 오프라인에서 쓴다.

이번 패치에는 삭제·자동 정리 작업을 추가하지 않았다. 이전 공개 파일과 미참조 파일은 복구/기존 다운로드를 위해 보존한다. 저장량이 커지면 참조·보존 기간을 기준으로 별도 정리 작업을 추가해야 하며, 버킷 전체에 단순 기간 삭제 정책을 적용하면 현재 공개 파일도 지워질 수 있다.

## 운영 반영 상태와 재배포

다음 항목을 운영에서 확인했다.

- `readerAdmin`, `readerCatalog`: 서울 / Node.js 22 / 2세대 / `ACTIVE`.
- Firestore·Storage 보안 규칙 및 Firestore 인덱스 배포 완료.
- 런타임 전용 계정 생성, 프로젝트 DB 권한·버킷 파일 권한·자기 계정에 한정한 서명 권한 설정 완료.
- 책·글꼴 목록 HTTP 200. 현재 두 목록 모두 공개 콘텐츠 0개다.
- 관리자 미인증 접근 HTTP 401, 허용하지 않은 origin HTTP 403, 업로드 preflight HTTP 204.
- 함수 빌드 이미지의 7일 보관 정책 설정. 대상은 서울의 `gcf-artifacts` 저장소이며 책·글꼴 버킷의 파일은 삭제하지 않는다.

첫 배포에서는 새 서비스 계정이 Storage에 전파될 때까지 지연이 있었고, 두 함수의 최초 생성 중 공용 소스 버킷 생성 충돌이 발생했다. 재시도로 두 함수 모두 생성됐다. 재현 가능한 배포 스크립트에는 IAM 재시도와 함수별 순차 배포를 넣었다. 또한 CLI가 실제 배포 성공 후 이미지 정리 정책 미설정만을 이유로 실패 코드를 반환하는 경우를 명시적으로 처리한다. 다른 배포 오류는 성공으로 처리하지 않는다.

Node.js 22와 Firebase CLI 15 이상, 인증된 gcloud가 있는 환경에서 다음을 실행한다. 기존 역할과 리소스를 통째로 교체하지 않고 필요한 항목을 추가한다.

```sh
bash tool/deploy_reader_backend.sh --apply
```

이미 권한 설정이 끝난 프로젝트에서 코드·규칙만 다시 반영하려면 기존 `npm --prefix functions run deploy`를 사용할 수 있다. 이 명령도 `reader` 코드베이스만 대상으로 한다.

아래는 적용한 설정의 상세 절차다.

1. 배포 환경에 Node.js 22와 Functions SDK 7을 지원하는 최신 Firebase CLI를 준비한다. 전체 Functions 에뮬레이터를 사용할 때는 최신 CLI에 맞는 Java 21 이상도 준비한다. 로컬의 기존 CLI 14는 Functions SDK 7 실행에 호환 문제가 있어 아래 통합 테스트에서는 HTTP 핸들러를 별도 테스트 서버로 실행했다.
2. `koofy-reader`에 `koofy-reader-api` 런타임 서비스 계정을 만든다. 함수 설정의 serviceAccount는 `koofy-reader-api@koofy-reader.iam.gserviceaccount.com`이다.
3. 이 계정에 프로젝트의 `roles/datastore.user`, 해당 버킷에 한정한 `roles/storage.objectAdmin`, 자기 서비스 계정 리소스에 한정한 `roles/iam.serviceAccountTokenCreator`를 부여한다. 마지막 권한은 서명 URL 생성의 `signBlob`에 필요하다. IAM Service Account Credentials API를 활성화한다. 배포 주체에는 해당 서비스 계정을 사용하는 권한이 필요하다. 기존 Slime 프로젝트 IAM 권한은 이 토큰 검증 방식에 추가할 필요 없다.
4. `functions/.env.example`을 `functions/.env.koofy-reader`로 복사해 실제 관리자 origin을 지정한다. 에뮬레이터 전용 환경변수를 운영에 설정하지 않는다.
5. `npm --prefix functions ci`, `npm --prefix functions test`를 실행한다.
6. Koofy-Reader 루트에서 `firebase deploy --project koofy-reader --only functions:reader,firestore,storage`를 실행한다. 인덱스가 준비될 때까지 기다린다. 규칙은 기존 기본 규칙을 모두 거부 정책으로 교체한다.
7. Quiz_Site 기존 호스팅에 변경분을 배포한다. `NEXT_PUBLIC_READER_ADMIN_URL` 기본값은 `https://asia-northeast3-koofy-reader.cloudfunctions.net/readerAdmin`이며 다른 URL이면 빌드 전에 설정한다. 관리자 로그인 환경변수는 기존 Slime 설정을 유지한다.
8. 테스트용 글꼴 1개와 EPUB·표지를 초안 등록 → 공개 → 실기기 다운로드 → 오프라인 재실행 → 글꼴 적용을 확인한다. 이 단계에서 실제 서비스 계정의 서명 권한과 Storage 다운로드를 검증한다.

최소 인스턴스는 0, 함수별 최대 인스턴스는 3이다. 관리자 함수는 이미지/ZIP 처리 메모리를 위해 동시 처리 1·512MiB, 공개 API는 동시 처리 20·256MiB다. 최대 인스턴스는 비용 상한선이 아니며 다운로드 트래픽과 파일 보관에도 사용량 비용이 발생한다.

## 검증

- Flutter 분석: 문제 없음. 테스트 89개 통과(다운로드/무결성/원자적 글꼴 설치/버전 분리 신규 5개 포함).
- Android debug APK, iOS Simulator 앱 빌드 성공.
- Android/iOS 실제 네이티브 글꼴 manifest 테스트 각각 1개 통과: 검증된 글꼴 등록, 손상 글꼴 제외, 번들 글꼴 유지.
- Quiz_Site TypeScript 검사 및 Next.js 프로덕션 빌드 성공.
- 서버 단위 테스트: 인증 입력, 메타데이터·revision, 공개 스냅샷, EPUB·TXT·표지·글꼴 검증.
- 서버 통합 테스트: 실제 HTTP 핸들러 + Auth/Firestore/Storage 에뮬레이터. 발급 프로젝트·권한 거부, 업로드·공개·초안 분리·동시 수정 충돌·비공개, 클라이언트 직접 읽기/쓰기 거부. 서명 URL 생성만 테스트용 signer로 대체한다.
- 운영 클라우드 배포 및 목록·인증 차단·CORS 검증 완료. `node tool/verify_reader_backend.mjs`로 콘텐츠 생성 없이 재확인할 수 있다.
- 실제 GCS 서명 파일 다운로드, 관리자 로그인 후 첫 업로드, 실기기 전체 흐름은 아직 미검증이다. 공개 콘텐츠가 없어 파일 다운로드 검사를 수행하지 않았으며 IAM 설정 확인과 실제 다운로드 성공을 구분한다.
- 첫 콘텐츠 공개 후 `node tool/verify_reader_backend.mjs --assets`는 각 종류의 첫 항목에 대해 서명 URL 발급과 파일 크기·SHA-256을 검사한다. 서명 URL이나 토큰을 로그에 출력하지 않는다.

## 지금 사용자에게 남은 확인

1. 배포한 관리자에서 기존 총괄 계정으로 로그인한다.
2. 배포 가능한 글꼴 1개를 초안으로 만들고 굵기에 맞는 파일을 업로드한 뒤 공개한다.
3. 다운로드 기능이 포함된 앱에서 글꼴 목록 새로고침 → 다운로드 → 책 열기 → 보기 설정에서 선택한다.
4. EPUB 또는 TXT와 표지도 같은 방식으로 공개하고 앱의 내 서재 추가를 확인한다.
5. 네트워크를 끈 뒤 받은 책을 다시 열고 글꼴·읽던 위치를 확인한다.

서버 통합 테스트는 루트에서 빌드한 뒤 다음처럼 실행한다:

```sh
npm --prefix functions run build
firebase emulators:exec --project demo-koofy-reader --only auth,firestore,storage 'node --test functions/test/emulator-runner.cjs'
```

이 명령은 운영 데이터에 쓰지 않는다. 테스트가 다른 프로젝트의 인증을 다루므로 에뮬레이터 singleProjectMode는 false다.

## 관리자 TXT 업로드 패치

- 관리자 책 파일 선택은 `.epub,.txt`를 허용한다. 대문자 확장자도 처리한다.
- 초안의 본문 슬롯은 `epub` 또는 `txt` 중 하나다. 다른 형식으로 업로드하면 기존 본문 슬롯을 초안에서 교체한다. 표지와 기존 공개 스냅샷은 유지한다.
- 앱은 TXT도 크기·SHA-256 검증 후 `.txt` 파일과 표지를 로컬 서재에 등록한다. 읽을 때 기존 TXT → Readium EPUB 준비 과정을 사용하며, 오프라인 재실행 시 같은 책 ID와 변환 결과를 유지한다.
- 새 앱은 책 목록 요청에 `supportsTxt=1`을 보낸다. 이를 보내지 않는 구버전 앱에는 TXT 배포본을 목록에서 제외해 알 수 없는 파일 형식 오류를 막는다. 페이지 커서는 필터 전 문서 기준으로 유지한다.
- 반영 순서: `readerAdmin`·`readerCatalog` 함수 배포 → Quiz_Site 관리자 사이트 배포 → 새 앱 빌드로 업데이트. 이번 변경에는 Firebase 규칙 변경이 필요 없다.
- 실제 등록 확인: 초안 정보 저장 → TXT와 표지 업로드 → 앱에 공개 → 업데이트한 앱의 책 다운로드 목록 새로고침 → 다운로드·읽기·오프라인 재실행.
