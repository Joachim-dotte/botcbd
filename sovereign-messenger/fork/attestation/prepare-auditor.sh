#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_LOCK="$SCRIPT_DIR/SOURCE.lock"
PATCH_FILE="$SCRIPT_DIR/patches/auditor-embedded-alpha.patch"
OVERLAY_APP="$SCRIPT_DIR/overlay/app"
VENDOR_DIR="$SCRIPT_DIR/vendor/Auditor"

# SOURCE.lock is part of this reviewed integration and contains only shell-safe NAME=value lines.
# shellcheck source=SOURCE.lock
source "$SOURCE_LOCK"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 69
  fi
}

require_command git
require_command install
require_command sha256sum

verify_upstream_identity() {
  local checkout="$1"
  local actual_commit actual_tree
  actual_commit="$(git -C "$checkout" rev-parse HEAD)"
  actual_tree="$(git -C "$checkout" rev-parse 'HEAD^{tree}')"
  if [[ "$actual_commit" != "$AUDITOR_COMMIT" ]]; then
    echo "error: Auditor commit mismatch: $actual_commit" >&2
    exit 65
  fi
  if [[ "$actual_tree" != "$AUDITOR_TREE" ]]; then
    echo "error: Auditor tree mismatch: $actual_tree" >&2
    exit 65
  fi
}

verify_wrapper() {
  local checkout="$1"
  local actual
  actual="$(sha256sum "$checkout/gradle/wrapper/gradle-wrapper.jar")"
  actual="${actual%% *}"
  if [[ "$actual" != "$GRADLE_WRAPPER_JAR_SHA256" ]]; then
    echo "error: pinned Gradle wrapper JAR hash mismatch: $actual" >&2
    exit 65
  fi
  if ! grep -Fqx "distributionSha256Sum=$GRADLE_DISTRIBUTION_SHA256" \
      "$checkout/gradle/wrapper/gradle-wrapper.properties"; then
    echo "error: pinned Gradle distribution hash is absent from wrapper properties" >&2
    exit 65
  fi
}

install_wrapper() {
  local checkout="$1"
  install -m 0755 "$checkout/gradlew" "$SCRIPT_DIR/gradlew"
  install -m 0644 "$checkout/gradlew.bat" "$SCRIPT_DIR/gradlew.bat"
  install -D -m 0644 "$checkout/gradle/wrapper/gradle-wrapper.jar" \
    "$SCRIPT_DIR/gradle/wrapper/gradle-wrapper.jar"
  install -D -m 0644 "$checkout/gradle/wrapper/gradle-wrapper.properties" \
    "$SCRIPT_DIR/gradle/wrapper/gradle-wrapper.properties"
  install -D -m 0644 "$checkout/gradle/verification-metadata.xml" \
    "$SCRIPT_DIR/gradle/verification-metadata.xml"
}

verify_overlay() {
  local checkout="$1"
  cmp -s "$OVERLAY_APP/build.gradle.kts" "$checkout/app/build.gradle.kts" || return 1
  cmp -s "$OVERLAY_APP/src/main/AndroidManifest.xml" \
    "$checkout/app/src/main/AndroidManifest.xml" || return 1
  cmp -s "$OVERLAY_APP/src/main/java/app/attestation/auditor/SovereignAuditorAlpha.java" \
    "$checkout/app/src/main/java/app/attestation/auditor/SovereignAuditorAlpha.java" || return 1
}

if [[ -e "$VENDOR_DIR" ]]; then
  if [[ ! -d "$VENDOR_DIR/.git" ]]; then
    echo "error: refusing to replace non-git path: $VENDOR_DIR" >&2
    exit 65
  fi
  verify_upstream_identity "$VENDOR_DIR"
  verify_wrapper "$VENDOR_DIR"
  if ! git -C "$VENDOR_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "error: existing Auditor checkout does not contain the reviewed alpha patch" >&2
    exit 65
  fi
  if ! verify_overlay "$VENDOR_DIR"; then
    echo "error: existing Auditor checkout does not match the reviewed library overlay" >&2
    exit 65
  fi
  install_wrapper "$VENDOR_DIR"
  echo "Auditor alpha is already prepared at: $VENDOR_DIR"
  exit 0
fi

require_command mktemp
WORK_DIR="$(mktemp -d "$SCRIPT_DIR/.prepare.XXXXXXXX")"
cleanup() {
  case "$WORK_DIR" in
    "$SCRIPT_DIR"/.prepare.*) rm -rf -- "$WORK_DIR" ;;
    *) echo "warning: refusing to clean unexpected temporary path: $WORK_DIR" >&2 ;;
  esac
}
trap cleanup EXIT

CHECKOUT="$WORK_DIR/Auditor"
git init --quiet "$CHECKOUT"
git -C "$CHECKOUT" remote add origin "$AUDITOR_REPOSITORY"
git -C "$CHECKOUT" fetch --quiet --depth 1 origin "$AUDITOR_COMMIT"
git -C "$CHECKOUT" checkout --quiet --detach FETCH_HEAD

verify_upstream_identity "$CHECKOUT"
verify_wrapper "$CHECKOUT"
git -C "$CHECKOUT" apply --check "$PATCH_FILE"
git -C "$CHECKOUT" apply "$PATCH_FILE"

install -m 0644 "$OVERLAY_APP/build.gradle.kts" "$CHECKOUT/app/build.gradle.kts"
install -m 0644 "$OVERLAY_APP/src/main/AndroidManifest.xml" \
  "$CHECKOUT/app/src/main/AndroidManifest.xml"
install -D -m 0644 \
  "$OVERLAY_APP/src/main/java/app/attestation/auditor/SovereignAuditorAlpha.java" \
  "$CHECKOUT/app/src/main/java/app/attestation/auditor/SovereignAuditorAlpha.java"

git -C "$CHECKOUT" diff --check
verify_overlay "$CHECKOUT"

install -d "$SCRIPT_DIR/vendor"
mv -- "$CHECKOUT" "$VENDOR_DIR"
install_wrapper "$VENDOR_DIR"

echo "Prepared GrapheneOS Auditor $AUDITOR_COMMIT as :auditor-alpha"
echo "Smoke build: cd '$SCRIPT_DIR' && ./gradlew :smoke:assembleDebug"
