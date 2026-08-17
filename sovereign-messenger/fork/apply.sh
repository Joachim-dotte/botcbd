#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BASE="e11128ce5b0df538c57a0d0b6911de0e88fdb652"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
OVERLAY_DIR="$SCRIPT_DIR/overlay"
PATCH_FILE="$SCRIPT_DIR/patches/sovereign-ui-hooks.patch"

if [[ $# -ne 1 ]]; then
  echo "usage: bash apply.sh /path/to/simplex-chat-v7.0.0" >&2
  exit 64
fi

if [[ ! -d "$1" ]]; then
  echo "error: checkout directory does not exist: $1" >&2
  exit 66
fi

UPSTREAM_DIR="$(cd -- "$1" && pwd -P)"
SETTINGS_FILE="$UPSTREAM_DIR/apps/multiplatform/settings.gradle.kts"
VERSION_FILE="$UPSTREAM_DIR/apps/multiplatform/gradle.properties"

if [[ ! -f "$SETTINGS_FILE" || ! -f "$VERSION_FILE" ]]; then
  echo "error: not a SimpleX multiplatform checkout: $UPSTREAM_DIR" >&2
  exit 65
fi

if ! grep -q '^android.version_name=7.0$' "$VERSION_FILE"; then
  echo "error: this overlay targets SimpleX Android version 7.0 only" >&2
  exit 65
fi

if git -C "$UPSTREAM_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$UPSTREAM_DIR" cat-file -e "${EXPECTED_BASE}^{commit}" 2>/dev/null; then
    if ! git -C "$UPSTREAM_DIR" merge-base --is-ancestor "$EXPECTED_BASE" HEAD; then
      echo "error: expected v7.0.0 base $EXPECTED_BASE is not an ancestor of HEAD" >&2
      exit 65
    fi
  elif [[ "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)" != "$EXPECTED_BASE" ]]; then
    echo "error: unable to verify the expected v7.0.0 base $EXPECTED_BASE" >&2
    exit 65
  fi
fi

if git -C "$UPSTREAM_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
  echo "UI hooks already applied"
elif git -C "$UPSTREAM_DIR" apply --check "$PATCH_FILE"; then
  git -C "$UPSTREAM_DIR" apply "$PATCH_FILE"
  echo "UI hooks applied"
else
  echo "error: UI hook patch neither applies cleanly nor appears already applied" >&2
  exit 65
fi

while IFS= read -r -d '' SOURCE_FILE; do
  RELATIVE_PATH="${SOURCE_FILE#"$OVERLAY_DIR"/}"
  install -D -m 0644 "$SOURCE_FILE" "$UPSTREAM_DIR/$RELATIVE_PATH"
done < <(find "$OVERLAY_DIR" -type f -print0)

echo "Sovereign alpha overlay installed in: $UPSTREAM_DIR"
echo "Tests: cd '$UPSTREAM_DIR/apps/multiplatform' && ./gradlew :common:desktopTest"
echo "Android: cd '$UPSTREAM_DIR/apps/multiplatform' && ./gradlew :android:assembleDebug"
