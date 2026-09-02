#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${PROJECT_DIR}/dist"
APP_DIR="${OUTPUT_DIR}/CodexFloat.app"
SIGNING_IDENTITY="${CODEX_FLOAT_SIGNING_IDENTITY:--}"
VERSION="${CODEX_FLOAT_VERSION:-0.1.0}"
BUILD_NUMBER="${CODEX_FLOAT_BUILD_NUMBER:-1}"
BUNDLE_ID="${CODEX_FLOAT_BUNDLE_ID:-com.local.codexfloat}"

[[ "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]] || {
  echo "Invalid CODEX_FLOAT_VERSION: ${VERSION}" >&2
  exit 2
}
[[ "${BUILD_NUMBER}" =~ '^[0-9]+$' ]] || {
  echo "CODEX_FLOAT_BUILD_NUMBER must contain digits only" >&2
  exit 2
}
[[ "${BUNDLE_ID}" =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' ]] || {
  echo "Invalid CODEX_FLOAT_BUNDLE_ID: ${BUNDLE_ID}" >&2
  exit 2
}

if [[ ! -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]]; then
  "${SCRIPT_DIR}/generate-icon.sh"
fi

if [[ "${CODEX_FLOAT_UNIVERSAL:-0}" == "1" ]]; then
  ARM_SCRATCH="${PROJECT_DIR}/.build-universal-arm64"
  INTEL_SCRATCH="${PROJECT_DIR}/.build-universal-x86_64"
  swift build -c release --package-path "${PROJECT_DIR}" \
    --scratch-path "${ARM_SCRATCH}" --triple arm64-apple-macosx14.0
  swift build -c release --package-path "${PROJECT_DIR}" \
    --scratch-path "${INTEL_SCRATCH}" --triple x86_64-apple-macosx14.0
  ARM_BIN="$(swift build -c release --package-path "${PROJECT_DIR}" \
    --scratch-path "${ARM_SCRATCH}" --triple arm64-apple-macosx14.0 --show-bin-path)/CodexFloat"
  INTEL_BIN="$(swift build -c release --package-path "${PROJECT_DIR}" \
    --scratch-path "${INTEL_SCRATCH}" --triple x86_64-apple-macosx14.0 --show-bin-path)/CodexFloat"
else
  swift build -c release --package-path "${PROJECT_DIR}"
  BIN_PATH="$(swift build -c release --package-path "${PROJECT_DIR}" --show-bin-path)/CodexFloat"
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${APP_DIR}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${APP_DIR}/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "${BUNDLE_ID}" "${APP_DIR}/Contents/Info.plist"
if [[ "${CODEX_FLOAT_UNIVERSAL:-0}" == "1" ]]; then
  lipo -create "${ARM_BIN}" "${INTEL_BIN}" -output "${APP_DIR}/Contents/MacOS/CodexFloat"
else
  cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/CodexFloat"
fi
chmod 755 "${APP_DIR}/Contents/MacOS/CodexFloat"

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  codesign --force --sign - "${APP_DIR}"
else
  codesign --force --options runtime --timestamp \
    --sign "${SIGNING_IDENTITY}" "${APP_DIR}"
fi
codesign --verify --strict "${APP_DIR}"
echo "Built ${APP_DIR}"
