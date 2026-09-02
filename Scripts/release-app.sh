#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${PROJECT_DIR}/dist"
APP_DIR="${OUTPUT_DIR}/CodexFloat.app"
DMG_PATH="${OUTPUT_DIR}/CodexFloat.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
DMG_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-float-dmg.XXXXXX")"

cleanup() {
  rm -rf "${DMG_STAGING_DIR}"
}
trap cleanup EXIT

: "${CODEX_FLOAT_SIGNING_IDENTITY:?Set CODEX_FLOAT_SIGNING_IDENTITY to a Developer ID Application certificate}"
: "${CODEX_FLOAT_NOTARY_PROFILE:?Set CODEX_FLOAT_NOTARY_PROFILE to a notarytool keychain profile}"
: "${CODEX_FLOAT_BUNDLE_ID:?Set CODEX_FLOAT_BUNDLE_ID to the public release bundle identifier}"

CODEX_FLOAT_UNIVERSAL="${CODEX_FLOAT_UNIVERSAL:-1}" \
CODEX_FLOAT_SIGNING_IDENTITY="${CODEX_FLOAT_SIGNING_IDENTITY}" \
  "${SCRIPT_DIR}/build-app.sh"

ditto "${APP_DIR}" "${DMG_STAGING_DIR}/CodexFloat.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"
rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"
hdiutil create \
  -volname "Codex Float" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${CODEX_FLOAT_NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type execute --verbose=4 "${APP_DIR}"
(
  cd "${OUTPUT_DIR}"
  shasum -a 256 CodexFloat.dmg > CodexFloat.dmg.sha256
)

echo "Released ${DMG_PATH}"
echo "Checksum ${CHECKSUM_PATH}"
