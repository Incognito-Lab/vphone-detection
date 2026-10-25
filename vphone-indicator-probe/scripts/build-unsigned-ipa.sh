#!/usr/bin/env bash
set -euo pipefail

# Build and package the iOS device app without signing. Run from any directory:
#   scripts/build-unsigned-ipa.sh [output-directory]
# Relative paths are resolved from vphone-indicator-probe. Both the output
# directory and VPHONE_DERIVED_DATA_DIR must remain inside the ignored build/.
# APP_VERSION is a numeric major.minor.patch version (default 0.1.0), and
# BUILD_NUMBER is a numeric build number (default 1).

usage() {
  cat >&2 <<'EOF'
Usage: build-unsigned-ipa.sh [output-directory]

Builds VPhoneIndicatorProbe-unsigned.ipa and its .sha256 sidecar. The optional
output directory and VPHONE_DERIVED_DATA_DIR may be absolute or relative to
vphone-indicator-probe, but must be beneath its ignored build/ directory.
APP_VERSION must be numeric major.minor.patch; BUILD_NUMBER must be numeric.
EOF
}

if [ "$#" -gt 1 ]; then
  usage
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$APP_ROOT/build"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_unsigned_ipa.py"

OUTPUT_DIR="${1:-$BUILD_ROOT/UnsignedIPA}"
case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$APP_ROOT/$OUTPUT_DIR" ;;
esac

DERIVED_DATA_DIR="${VPHONE_DERIVED_DATA_DIR:-$BUILD_ROOT/UnsignedDerivedData}"
case "$DERIVED_DATA_DIR" in
  /*) ;;
  *) DERIVED_DATA_DIR="$APP_ROOT/$DERIVED_DATA_DIR" ;;
esac

APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'APP_VERSION must be numeric major.minor.patch; got: %s\n' "$APP_VERSION" >&2
  exit 64
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  printf 'BUILD_NUMBER must be numeric; got: %s\n' "$BUILD_NUMBER" >&2
  exit 64
fi

for tool in xcodebuild python3 codesign; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required tool not found in PATH: %s\n' "$tool" >&2
    exit 69
  fi
done

mkdir -p "$BUILD_ROOT"
python3 "$VERIFY_SCRIPT" validate-paths \
  --app-root "$APP_ROOT" \
  --build-root "$BUILD_ROOT" \
  --output-dir "$OUTPUT_DIR" \
  --derived-data-dir "$DERIVED_DATA_DIR"
mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA_DIR"

IPA_NAME="VPhoneIndicatorProbe-unsigned.ipa"
SHA_NAME="$IPA_NAME.sha256"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
SHA_PATH="$OUTPUT_DIR/$SHA_NAME"
if [ -d "$IPA_PATH" ] || [ -d "$SHA_PATH" ]; then
  printf 'Refusing to replace a directory at an artifact path.\n' >&2
  exit 73
fi

STAGING_DIR="$(mktemp -d "$BUILD_ROOT/.unsigned-ipa.XXXXXX")"
cleanup() {
  if [ -n "${STAGING_DIR:-}" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

printf 'Building unsigned Release device app...\n'
xcodebuild \
  -project "$APP_ROOT/VPhoneIndicatorProbe.xcodeproj" \
  -scheme VPhoneIndicatorProbe \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  'CODE_SIGN_IDENTITY=' \
  'DEVELOPMENT_TEAM=' \
  "MARKETING_VERSION=$APP_VERSION" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Release-iphoneos/VPhoneIndicatorProbe.app"
if [ ! -d "$BUILT_APP" ]; then
  printf 'Expected build product was not created: %s\n' "$BUILT_APP" >&2
  exit 1
fi

STAGED_IPA="$STAGING_DIR/$IPA_NAME"
STAGED_SHA="$STAGING_DIR/$SHA_NAME"
python3 "$VERIFY_SCRIPT" package \
  --app "$BUILT_APP" \
  --ipa "$STAGED_IPA" \
  --expected-version "$APP_VERSION" \
  --expected-build "$BUILD_NUMBER"
python3 "$VERIFY_SCRIPT" sha256 --ipa "$STAGED_IPA" --output "$STAGED_SHA"

mv -f "$STAGED_IPA" "$IPA_PATH"
mv -f "$STAGED_SHA" "$SHA_PATH"
printf 'Unsigned IPA: %s\nSHA-256:      %s\n' "$IPA_PATH" "$SHA_PATH"
