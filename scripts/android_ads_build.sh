#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-debug}"
OUTPUT="${2:-apk}"
if [[ "$MODE" != debug && "$MODE" != release ]] || [[ "$OUTPUT" != apk && "$OUTPUT" != aab ]]; then
  echo 'Usage: ./scripts/android_ads_build.sh [debug|release] [apk|aab]' >&2
  exit 1
fi
BUILD_TARGET=apk
if [[ "$OUTPUT" == aab ]]; then BUILD_TARGET=appbundle; fi
CMD=(flutter build "$BUILD_TARGET" "--$MODE")
if [[ "$MODE" == debug ]]; then
  CMD+=(--dart-define=LEVELPLAY_TEST_SUITE=true)
  echo 'LevelPlay test suite enabled. Register the device in LevelPlay before testing ads.'
fi
cd "$ROOT_DIR"
flutter pub get
"${CMD[@]}"
