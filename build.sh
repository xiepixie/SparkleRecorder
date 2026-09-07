#!/bin/bash
# Build SparkleRecorder.app and install it to /Applications.
#
# Why /Applications: macOS ties Accessibility / Input Monitoring (TCC) grants to a
# bundle's path *and* code signature. A single bundle at the standard, immutable
# location is the most reliable place for those grants to persist — far better
# than running a copy out of ~/Documents, and it avoids the "every copy needs its
# own grant" trap.
#
# Signing: if a "Developer ID Application" certificate is installed, this script
# signs with it (hardened runtime) — a stable identity, so TCC grants persist
# across rebuilds and the app can be notarized (see notarize.sh). Until then it
# ad-hoc signs, where TCC falls back to the binary's ever-changing cdhash and may
# re-prompt for permissions after each rebuild.
set -euo pipefail

APP_NAME="SparkleRecorder"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_PROFILE="${SPARKLERECORDER_BUILD_PROFILE:-local}"
case "$BUILD_PROFILE" in
    local)
        # Keep release optimization for realistic app behavior, but disable WMO so
        # Swift can reuse per-file incremental build state during daily iteration.
        BUILD_SCRATCH="${ROOT}/.build/local"
        BUILD_DIR="${BUILD_SCRATCH}/release"
        BUILD_SWIFT_ARGS=(-c release --scratch-path "$BUILD_SCRATCH" -Xswiftc -no-whole-module-optimization -Xswiftc -incremental)
        BUILD_LABEL="release, incremental"
        ;;
    distribution)
        # Distribution keeps SwiftPM's default release WMO. It uses a separate
        # cache so an occasional shipping build does not invalidate the fast local
        # incremental graph.
        BUILD_SCRATCH="${ROOT}/.build/distribution"
        BUILD_DIR="${BUILD_SCRATCH}/release"
        BUILD_SWIFT_ARGS=(-c release --scratch-path "$BUILD_SCRATCH")
        BUILD_LABEL="release, WMO"
        ;;
    *)
        echo "error: SPARKLERECORDER_BUILD_PROFILE must be 'local' or 'distribution'." >&2
        exit 2
        ;;
esac
STAGE="${ROOT}/.build/${APP_NAME}.app"        # assembled here first (gitignored)
GENERATED_L10N="${ROOT}/.build/generated-localizations"
# Install location can be overridden (e.g. to build a one-off copy on the Desktop
# without disturbing the /Applications install).
INSTALL_DIR="${SPARKLERECORDER_INSTALL_DIR:-/Applications}"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"   # final location
CONTENTS="${STAGE}/Contents"
INSTALL_STAGING=""
INSTALL_BACKUP=""

cd "$ROOT"

cleanup() {
    rm -rf "$STAGE"
    if [ -n "$INSTALL_STAGING" ]; then
        rm -rf "$INSTALL_STAGING"
    fi
    if [ -n "$INSTALL_BACKUP" ] && [ -e "$INSTALL_BACKUP" ]; then
        if [ ! -e "$APP_BUNDLE" ]; then
            mv "$INSTALL_BACKUP" "$APP_BUNDLE" 2>/dev/null || true
        else
            rm -rf "$INSTALL_BACKUP"
        fi
    fi
}
trap cleanup EXIT

# Regenerate the icon if the source script is newer than the .icns (or it's missing).
if [ ! -f "AppIcon.icns" ] || [ "tools/make_icon.swift" -nt "AppIcon.icns" ]; then
    echo "→ Generating AppIcon.icns..."
    swift tools/make_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
fi

echo "→ Compiling (${BUILD_LABEL})..."
# Extra swiftc flags can be injected, e.g. SPARKLERECORDER_SWIFT_FLAGS="-Xswiftc -DHIDE_PERMISSION_BANNER".
# Unquoted on purpose so multiple flags word-split into separate arguments.
swift build "${BUILD_SWIFT_ARGS[@]}" ${SPARKLERECORDER_SWIFT_FLAGS:-}

echo "→ Bundling ${APP_NAME}.app..."
rm -rf "$STAGE"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "${ROOT}/Info.plist" "${CONTENTS}/Info.plist"
cp "${ROOT}/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"
chmod +x "${CONTENTS}/MacOS/${APP_NAME}"

echo "→ Compiling string catalogs..."
if ! XCSTRINGSTOOL=$(xcrun --find xcstringstool 2>/dev/null); then
    echo "error: xcstringstool was not found. Install a Swift 6-capable full Xcode (16+) and select it with xcode-select." >&2
    exit 1
fi
rm -rf "$GENERATED_L10N"
mkdir -p "$GENERATED_L10N"
for catalog in "${ROOT}/Sources/SparkleRecorder/"*.xcstrings; do
    "$XCSTRINGSTOOL" compile "$catalog" --output-directory "$GENERATED_L10N"
done

# Copy generated runtime localization resources.
lproj_dirs=("${GENERATED_L10N}/"*.lproj)
cp -R "${lproj_dirs[@]}" "${CONTENTS}/Resources/"

# Stamp a monotonically-increasing build number (before signing — editing the
# plist afterwards would invalidate the signature).
BUILD_NUM=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "${CONTENTS}/Info.plist"

if pgrep -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    echo "✗ ${APP_NAME} is still running from ${APP_BUNDLE}." >&2
    echo "  Quit it before installing; replacing a running bundle leaves a stale process" >&2
    echo "  whose TCC permission identity can disagree with the newly installed app." >&2
    exit 1
fi

# Sign the staged bundle before touching the currently installed app. This keeps
# a failed identity lookup, timestamp request, or codesign operation from replacing
# a known-good installation with an unsigned/partially signed bundle.
#   $1 = bundle path, $2 = identity ("-" for ad-hoc), remaining args = codesign flags
sign_app() {
    local target="$1"
    local identity="$2"
    shift 2
    xattr -cr "$target" 2>/dev/null || true
    codesign --force "$@" --sign "$identity" "$target"
}

# Prefer a Developer ID Application identity when one is installed: a stable
# signature means TCC (Accessibility / Input Monitoring) grants persist across
# rebuilds, and it's a prerequisite for notarization. Override by exporting
# SPARKLERECORDER_SIGN_ID="Developer ID Application: Name (TEAMID)". Without a
# Developer ID cert, a stable Apple development/distribution identity is preferred;
# if none exists, the script uses ad-hoc signing.
# List identities once. The trailing `|| true` on each pipeline matters: under
# `set -euo pipefail` a grep with no match exits non-zero and would abort the
# build, so we swallow that and just end up with an empty SIGN_ID.
SIGN_IDS=$(security find-identity -v -p codesigning 2>/dev/null || true)
SIGN_ID="${SPARKLERECORDER_SIGN_ID:-}"
# 1) Prefer a Developer ID Application cert — distribution-ready & notarizable.
if [ -z "$SIGN_ID" ]; then
    SIGN_ID=$(printf '%s\n' "$SIGN_IDS" | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"$/\1/' || true)
fi
# 2) Otherwise any stable identity (e.g. Apple Development) — not for distribution,
#    but a stable code signature is enough for TCC grants to persist across rebuilds.
if [ -z "$SIGN_ID" ]; then
    SIGN_ID=$(printf '%s\n' "$SIGN_IDS" | grep -E "Apple Development|Apple Distribution" | head -1 | sed -E 's/.*"(.*)"$/\1/' || true)
fi
# 3) Otherwise fall back to ad-hoc signing. build.sh must not silently create a
#    private key or change the user's Keychain trust policy. A deliberately created
#    local identity can still be selected explicitly with SPARKLERECORDER_SIGN_ID.

if [ -n "$SIGN_ID" ]; then
    case "$SIGN_ID" in
        *"Developer ID"*)
            echo "→ Signing with Developer ID (hardened runtime): ${SIGN_ID}"
            sign_app "$STAGE" "$SIGN_ID" --options runtime --timestamp
            ;;
        *)
            echo "→ Signing with stable identity (TCC grants persist): ${SIGN_ID}"
            sign_app "$STAGE" "$SIGN_ID"
            ;;
    esac
    SIGNED_WITH="$SIGN_ID"
else
    echo "→ No signing identity found — ad-hoc signing (permissions may re-prompt after rebuilds)."
    sign_app "$STAGE" "-"
    SIGNED_WITH="ad-hoc"
fi

codesign --verify --deep --strict --verbose=2 "$STAGE"

echo "→ Installing to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
INSTALL_STAGING="${INSTALL_DIR}/.${APP_NAME}.app.installing.$$"
INSTALL_BACKUP="${INSTALL_DIR}/.${APP_NAME}.app.previous.$$"
rm -rf "$INSTALL_STAGING" "$INSTALL_BACKUP"
cp -R "$STAGE" "$INSTALL_STAGING"
codesign --verify --deep --strict --verbose=2 "$INSTALL_STAGING"

if [ -e "$APP_BUNDLE" ]; then
    mv "$APP_BUNDLE" "$INSTALL_BACKUP"
fi
if ! mv "$INSTALL_STAGING" "$APP_BUNDLE"; then
    if [ -e "$INSTALL_BACKUP" ]; then
        mv "$INSTALL_BACKUP" "$APP_BUNDLE" 2>/dev/null || true
    fi
    echo "✗ Failed to activate the new app; the previous installation was restored when possible." >&2
    exit 1
fi
INSTALL_STAGING=""
rm -rf "$INSTALL_BACKUP"
INSTALL_BACKUP=""

echo
echo "✅ Installed: ${APP_BUNDLE}"
echo "   Signed:   ${SIGNED_WITH}"
echo "   Run:  open \"${APP_BUNDLE}\""
