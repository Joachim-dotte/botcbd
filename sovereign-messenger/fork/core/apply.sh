#!/bin/sh
set -eu

EXPECTED_COMMIT=e11128ce5b0df538c57a0d0b6911de0e88fdb652
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=${1:-}

if [ -z "$TARGET" ] || [ ! -d "$TARGET/.git" ]; then
  echo "usage: $0 /path/to/simplex-chat-v7.0.0" >&2
  exit 64
fi

actual=$(git -C "$TARGET" rev-parse HEAD)
if [ "$actual" != "$EXPECTED_COMMIT" ]; then
  echo "refusing checkout at $actual; expected $EXPECTED_COMMIT (SimpleX v7.0.0)" >&2
  exit 65
fi

check_overlay() {
  src=$1
  rel=${src#"$HERE/overlay/"}
  dst=$TARGET/$rel
  if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    echo "refusing conflicting file: $dst" >&2
    exit 66
  fi
}

find "$HERE/overlay" -type f -print | LC_ALL=C sort | while IFS= read -r src; do
  check_overlay "$src"
done

PATCH=$HERE/integration.patch
if git -C "$TARGET" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  patch_state=applied
elif git -C "$TARGET" apply --check "$PATCH"; then
  patch_state=pending
else
  echo "integration patch neither applies nor cleanly reverses; refusing" >&2
  exit 67
fi

find "$HERE/overlay" -type f -print | LC_ALL=C sort | while IFS= read -r src; do
  rel=${src#"$HERE/overlay/"}
  dst=$TARGET/$rel
  if [ ! -e "$dst" ]; then
    install -D -m 0644 "$src" "$dst"
  fi
done

if [ "$patch_state" = pending ]; then
  git -C "$TARGET" apply "$PATCH"
  echo "Applied Sovereign registry integration."
else
  echo "Sovereign registry integration already applied."
fi
