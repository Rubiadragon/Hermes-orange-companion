#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v0.1.0}"
SOURCE_DIR="${MORANGE_ANIMATIONS_DIR:-$HOME/Library/Application Support/morange-companion/MOrangeAnimations}"
OUT_DIR="${MORANGE_RELEASE_DIR:-dist/release-assets}"
ZIP_NAME="MOrangeAnimations-${VERSION}.zip"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Animation directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME.sha256"

parent_dir="$(dirname "$SOURCE_DIR")"
folder_name="$(basename "$SOURCE_DIR")"

(
  cd "$parent_dir"
  ditto -c -k --sequesterRsrc --keepParent "$folder_name" "$OLDPWD/$OUT_DIR/$ZIP_NAME"
)

shasum -a 256 "$OUT_DIR/$ZIP_NAME" > "$OUT_DIR/$ZIP_NAME.sha256"
du -h "$OUT_DIR/$ZIP_NAME"
cat "$OUT_DIR/$ZIP_NAME.sha256"
