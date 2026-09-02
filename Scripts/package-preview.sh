#!/bin/zsh
# Reproducible, explicitly unnotarized Universal 2 preview assets.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
: "${CODEX_FLOAT_VERSION:?Set CODEX_FLOAT_VERSION, for example 0.2.0}"
[[ "${CODEX_FLOAT_VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
  echo "Expected a numeric preview version such as 0.2.0" >&2
  exit 2
}
VERSION="${CODEX_FLOAT_VERSION}"
OUTPUT_DIR="${PROJECT_DIR}/dist/preview-${VERSION}"
APP_DIR="${PROJECT_DIR}/dist/CodexFloat.app"
NAME="CodexFloat-${VERSION}-preview-universal"
IMAGE="${PROJECT_DIR}/docs/Images/codex-float-${VERSION}-feature.png"

# Never replace assets already staged for a release.
[[ ! -e "${OUTPUT_DIR}" ]] || {
  echo "Refusing to overwrite ${OUTPUT_DIR}; choose a new version." >&2
  exit 2
}
[[ -f "${IMAGE}" ]] || { echo "Missing versioned feature image." >&2; exit 2; }

CODEX_FLOAT_UNIVERSAL=1 CODEX_FLOAT_SIGNING_IDENTITY=- \
  "${SCRIPT_DIR}/build-app.sh"
codesign --verify --deep --strict "${APP_DIR}"
architectures="$(lipo -archs "${APP_DIR}/Contents/MacOS/CodexFloat")"
[[ " ${architectures} " == *" arm64 "* && " ${architectures} " == *" x86_64 "* ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist")" == "${VERSION}" ]]

PREVIEW_STAGE="$(mktemp -d /private/tmp/codex-float-preview.XXXXXX)"
cleanup() {
  # Only remove the staging directory created by this invocation.
  if [[ -d "${PREVIEW_STAGE}" && "${PREVIEW_STAGE}" == /private/tmp/codex-float-preview.* ]]; then
    rm -rf "${PREVIEW_STAGE}"
  fi
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"
ditto "${APP_DIR}" "${PREVIEW_STAGE}/CodexFloat.app"
ln -s /Applications "${PREVIEW_STAGE}/Applications"
cp "${PROJECT_DIR}/docs/releases/INSTALL-PREVIEW.txt" "${PREVIEW_STAGE}/READ-ME-FIRST.txt"
cp "${PROJECT_DIR}/LICENSE" "${PREVIEW_STAGE}/LICENSE.txt"
hdiutil create -volname "Codex Float ${VERSION} Preview" \
  -srcfolder "${PREVIEW_STAGE}" -format UDZO "${OUTPUT_DIR}/${NAME}.dmg"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${OUTPUT_DIR}/${NAME}.zip"
cp "${IMAGE}" "${OUTPUT_DIR}/codex-float-${VERSION}-feature.png"
(
  cd "${OUTPUT_DIR}"
  shasum -a 256 "${NAME}.dmg" "${NAME}.zip" "codex-float-${VERSION}-feature.png" > SHA256SUMS.txt
)
echo "Unnotarized preview assets: ${OUTPUT_DIR}"
