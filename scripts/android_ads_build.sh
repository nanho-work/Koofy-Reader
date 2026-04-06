#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-debug}"   # debug | release
OUTPUT="${2:-apk}"   # apk | aab
ENV_FILE="${ADMOB_ENV_FILE:-$ROOT_DIR/.env.admob}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/android_ads_build.sh [debug|release] [apk|aab]

Examples:
  ./scripts/android_ads_build.sh debug apk
  ./scripts/android_ads_build.sh release aab

Notes:
  - debug: forces Google test ad IDs
  - release: requires .env.admob (or ADMOB_ENV_FILE) with production IDs
EOF
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
  usage
  exit 1
fi

if [[ "$OUTPUT" != "apk" && "$OUTPUT" != "aab" ]]; then
  usage
  exit 1
fi

BUILD_TARGET="apk"
if [[ "$OUTPUT" == "aab" ]]; then
  BUILD_TARGET="appbundle"
fi

CMD=(flutter build "$BUILD_TARGET")

if [[ "$MODE" == "release" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Release mode requires env file: $ENV_FILE" >&2
    echo "Create it from .env.admob.example" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  require_var ADMOB_APP_ID_ANDROID
  require_var ADMOB_BANNER_ANDROID
  require_var ADMOB_REWARDED_ANDROID

  export ORG_GRADLE_PROJECT_ADMOB_APP_ID="$ADMOB_APP_ID_ANDROID"

  CMD+=(
    --release
    --dart-define=USE_ADMOB_TEST_IDS=false
    "--dart-define=ADMOB_BANNER_ANDROID=$ADMOB_BANNER_ANDROID"
    "--dart-define=ADMOB_REWARDED_ANDROID=$ADMOB_REWARDED_ANDROID"
  )
else
  CMD+=(
    --debug
    --dart-define=USE_ADMOB_TEST_IDS=true
  )
fi

echo "Running: ${CMD[*]}"
cd "$ROOT_DIR"
flutter pub get
"${CMD[@]}"
