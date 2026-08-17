#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BASE="e11128ce5b0df538c57a0d0b6911de0e88fdb652"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD_PATCH="$SCRIPT_DIR/patches/simplex-v7-auditor-build.patch"
SOURCE_OVERLAY="$SCRIPT_DIR/simplex-overlay"
AUDITOR_MODULE="$SCRIPT_DIR/vendor/Auditor/app"

if [[ $# -ne 1 ]]; then
  echo "usage: bash integrate-simplex.sh /path/to/simplex-chat-v7.0.0" >&2
  exit 64
fi
if [[ ! -d "$1" ]]; then
  echo "error: SimpleX checkout does not exist: $1" >&2
  exit 66
fi

SIMPLEX_DIR="$(cd -- "$1" && pwd -P)"
MULTIPLATFORM_DIR="$SIMPLEX_DIR/apps/multiplatform"
UI_SEAM="$MULTIPLATFORM_DIR/common/src/commonMain/kotlin/chat/simplex/common/sovereign/SovereignSecurity.kt"

if [[ ! -f "$MULTIPLATFORM_DIR/settings.gradle.kts" || ! -f "$UI_SEAM" ]]; then
  echo "error: apply the Sovereign UI overlay to SimpleX v7.0.0 before this integration" >&2
  exit 65
fi
if [[ ! -f "$AUDITOR_MODULE/build.gradle.kts" ]]; then
  echo "error: run 'bash $SCRIPT_DIR/prepare-auditor.sh' first" >&2
  exit 66
fi
if ! grep -q '^android.version_name=7.0$' "$MULTIPLATFORM_DIR/gradle.properties"; then
  echo "error: this integration targets SimpleX Android v7.0 only" >&2
  exit 65
fi

if git -C "$SIMPLEX_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$SIMPLEX_DIR" cat-file -e "${EXPECTED_BASE}^{commit}" 2>/dev/null; then
    if ! git -C "$SIMPLEX_DIR" merge-base --is-ancestor "$EXPECTED_BASE" HEAD; then
      echo "error: expected SimpleX v7.0.0 base is not an ancestor of HEAD" >&2
      exit 65
    fi
  elif [[ "$(git -C "$SIMPLEX_DIR" rev-parse HEAD)" != "$EXPECTED_BASE" ]]; then
    echo "error: unable to verify the expected SimpleX v7.0.0 base" >&2
    exit 65
  fi
fi

if git -C "$SIMPLEX_DIR" apply --reverse --check "$BUILD_PATCH" >/dev/null 2>&1; then
  echo "Auditor build integration already applied"
elif git -C "$SIMPLEX_DIR" apply --check "$BUILD_PATCH"; then
  git -C "$SIMPLEX_DIR" apply "$BUILD_PATCH"
  echo "Auditor build integration applied"
else
  echo "error: build patch neither applies cleanly nor appears already applied" >&2
  exit 65
fi

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#"$SOURCE_OVERLAY"/}"
  install -D -m 0644 "$source_file" "$SIMPLEX_DIR/$relative_path"
done < <(find "$SOURCE_OVERLAY" -type f -print0)

echo "Installed the StrongBox-only local QR provider in: $SIMPLEX_DIR"
echo "Build: cd '$MULTIPLATFORM_DIR' && ./gradlew -PsovereignAuditorModuleDir='$AUDITOR_MODULE' :android:assembleDebug"
