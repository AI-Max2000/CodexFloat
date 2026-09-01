#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_ICON="${PROJECT_DIR}/Resources/AppIcon.svg"
OUTPUT_ICON="${PROJECT_DIR}/Resources/AppIcon.icns"
ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-float-icon.XXXXXX")"
ICONSET_DIR="${ICON_WORK_DIR}/AppIcon.iconset"

cleanup() {
  rm -rf "${ICON_WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${ICONSET_DIR}"

typeset -a icon_specs=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for spec in "${icon_specs[@]}"; do
  size="${spec%%:*}"
  filename="${spec#*:}"
  sips -s format png -z "${size}" "${size}" "${SOURCE_ICON}" \
    --out "${ICONSET_DIR}/${filename}" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICON}"
echo "Generated ${OUTPUT_ICON}"
