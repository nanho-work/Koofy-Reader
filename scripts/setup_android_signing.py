#!/usr/bin/env python3
"""Create the first Android upload key interactively; never replace existing keys."""

import getpass
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def properties_value(value):
    # Java Properties.load(InputStream) uses ISO-8859-1. Escape every UTF-16
    # code unit so spaces, backslashes, punctuation and Korean survive intact.
    encoded = value.encode("utf-16-be")
    return "".join(
        "\\u" + encoded[index:index + 2].hex()
        for index in range(0, len(encoded), 2)
    )


def check_destination(root):
    for relative in ("android/upload-keystore.jks", "android/key.properties"):
        target = root / relative
        if target.exists() or target.is_symlink():
            raise RuntimeError(f"이미 존재하는 파일은 덮어쓰지 않습니다: {relative}")
        ignored = subprocess.run(
            ["git", "check-ignore", "--quiet", "--", relative], cwd=root,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", relative], cwd=root,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if ignored.returncode != 0 or tracked.returncode != 1:
            raise RuntimeError(f"Git 제외 설정부터 확인해야 합니다: {relative}")


def find_keytool():
    candidates = []
    if os.environ.get("JAVA_HOME"):
        candidates.append(Path(os.environ["JAVA_HOME"]) / "bin/keytool")
    candidates.append(Path(
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
    ))
    executable = shutil.which("keytool")
    if executable:
        candidates.append(Path(executable))
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise RuntimeError("keytool을 찾지 못했습니다. Android Studio 또는 JDK를 확인해 주세요.")


def create_signing(root, keytool, password):
    check_destination(root)
    work = root / "work"
    work.mkdir(exist_ok=True)
    previous_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="signing-", dir=work) as folder:
            stage = Path(folder)
            key = stage / "upload-keystore.jks"
            environment = os.environ.copy()
            environment["KOOFY_UPLOAD_PASSWORD"] = password
            result = subprocess.run([
                keytool, "-genkeypair", "-noprompt", "-storetype", "JKS",
                "-keystore", str(key), "-alias", "upload", "-keyalg", "RSA",
                "-keysize", "3072", "-validity", "10000",
                "-dname", "CN=Koofy Reader Upload, O=Koofy Lab",
                "-storepass:env", "KOOFY_UPLOAD_PASSWORD",
                "-keypass:env", "KOOFY_UPLOAD_PASSWORD",
            ], env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            environment.pop("KOOFY_UPLOAD_PASSWORD", None)
            if result.returncode:
                raise RuntimeError("키 생성에 실패했습니다. JDK와 비밀번호 조건을 확인해 주세요.")
            key.chmod(0o600)
            properties = stage / "key.properties"
            properties.write_text(
                "# Local signing credentials. Do not commit or share.\n"
                "storeFile=../upload-keystore.jks\n"
                "keyAlias=upload\n"
                f"storePassword={properties_value(password)}\n"
                f"keyPassword={properties_value(password)}\n",
                encoding="ascii",
            )
            properties.chmod(0o600)
            # Hard links publish complete files atomically without overwriting
            # a destination created by another process in the meantime.
            destination = root / "android/upload-keystore.jks"
            os.link(key, destination)
            try:
                os.link(properties, root / "android/key.properties")
            except BaseException:
                destination.unlink()
                raise
    finally:
        os.umask(previous_umask)


def main():
    if not sys.stdin.isatty():
        raise RuntimeError("직접 입력할 수 있는 로컬 터미널에서 실행해 주세요.")
    root = Path(__file__).resolve().parent.parent
    check_destination(root)
    keytool = find_keytool()
    print("쿠피리더 전용 업로드 키와 로컬 서명 설정을 생성합니다.")
    print("입력한 비밀번호는 화면에 표시되지 않습니다. 6자 이상으로 입력하세요.")
    password = getpass.getpass("비밀번호: ")
    confirmation = getpass.getpass("비밀번호 다시 입력: ")
    if password != confirmation:
        raise RuntimeError("비밀번호가 일치하지 않습니다. 파일은 생성하지 않았습니다.")
    if len(password) < 6 or any(character in password for character in "\x00\r\n"):
        raise RuntimeError("비밀번호는 줄바꿈 없이 6자 이상이어야 합니다.")
    create_signing(root, keytool, password)
    print("완료: 업로드 키와 서명 설정을 생성했습니다. 비밀번호는 출력하지 않습니다.")
    print("android/upload-keystore.jks와 비밀번호를 안전한 별도 장소에 백업하세요.")
    print("android/key.properties에도 비밀번호가 있으므로 공유하지 마세요.")
    print("이제 Codex에 '키 생성 완료'라고 알려주시면 릴리스 빌드를 진행합니다.")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\n입력을 취소했습니다.", file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, OSError) as error:
        print(f"중단: {error}", file=sys.stderr)
        sys.exit(1)
