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
BUILD_DIR="${ROOT}/.build/release"
STAGE="${ROOT}/.build/${APP_NAME}.app"        # assembled here first (gitignored)
GENERATED_L10N="${ROOT}/.build/generated-localizations"
# Install location can be overridden (e.g. to build a one-off copy on the Desktop
# without disturbing the /Applications install).
INSTALL_DIR="${SPARKLERECORDER_INSTALL_DIR:-/Applications}"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"   # final location
CONTENTS="${STAGE}/Contents"

cd "$ROOT"

# Regenerate the icon if the source script is newer than the .icns (or it's missing).
if [ ! -f "AppIcon.icns" ] || [ "tools/make_icon.swift" -nt "AppIcon.icns" ]; then
    echo "→ Generating AppIcon.icns..."
    swift tools/make_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
fi

echo "→ Compiling (release)..."
# Extra swiftc flags can be injected, e.g. SPARKLERECORDER_SWIFT_FLAGS="-Xswiftc -DHIDE_PERMISSION_BANNER".
# Unquoted on purpose so multiple flags word-split into separate arguments.
swift build -c release ${SPARKLERECORDER_SWIFT_FLAGS:-}

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
    echo "error: xcstringstool was not found. Install full Xcode 15+ and select it with xcode-select." >&2
    exit 1
fi
rm -rf "$GENERATED_L10N"
mkdir -p "$GENERATED_L10N"
"$XCSTRINGSTOOL" compile "${ROOT}/Sources/SparkleRecorder/Localizable.xcstrings" --output-directory "$GENERATED_L10N"
"$XCSTRINGSTOOL" compile "${ROOT}/Sources/SparkleRecorder/InfoPlist.xcstrings" --output-directory "$GENERATED_L10N"

# Copy generated runtime localization resources.
lproj_dirs=("${GENERATED_L10N}/"*.lproj)
cp -R "${lproj_dirs[@]}" "${CONTENTS}/Resources/"

# Stamp a monotonically-increasing build number (before signing — editing the
# plist afterwards would invalidate the signature).
BUILD_NUM=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "${CONTENTS}/Info.plist"

echo "→ Installing to ${INSTALL_DIR}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$INSTALL_DIR"
cp -R "$STAGE" "$APP_BUNDLE"

# Sign the bundle, stripping extended attributes first. Writing into a
# Finder-watched dir (e.g. ~/Desktop) can race in com.apple.FinderInfo/macl that
# codesign rejects as "detritus", so clear-then-sign with one retry.
#   $1 = extra codesign flags (may be empty), $2 = identity ("-" for ad-hoc)
sign_app() {
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true
    if ! codesign --force $1 --sign "$2" "$APP_BUNDLE" 2>/dev/null; then
        echo "  …xattr race; clearing and retrying"
        xattr -cr "$APP_BUNDLE" 2>/dev/null || true
        codesign --force $1 --sign "$2" "$APP_BUNDLE"
    fi
}

# Prefer a Developer ID Application identity when one is installed: a stable
# signature means TCC (Accessibility / Input Monitoring) grants persist across
# rebuilds, and it's a prerequisite for notarization. Override by exporting
# SPARKLERECORDER_SIGN_ID="Developer ID Application: Name (TEAMID)". Falls back to
# ad-hoc signing until a Developer ID cert exists (then grants re-prompt per build).
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
# 3) Fallback: use or create a stable self-signed local certificate "SparkleRecorder-SelfSigned"
#    so that TCC (Accessibility) permissions persist across rebuilds on this Mac.
if [ -z "$SIGN_ID" ]; then
    if printf '%s\n' "$SIGN_IDS" | grep -q "SparkleRecorder-SelfSigned"; then
        SIGN_ID="SparkleRecorder-SelfSigned"
    else
        echo "→ Generating stable self-signed codesigning certificate 'SparkleRecorder-SelfSigned'..."
        CERT_TMP_DIR=$(mktemp -d)
        CERT_CONF_TMP="${CERT_TMP_DIR}/openssl.cnf"
        KEY_PEM="${CERT_TMP_DIR}/key.pem"
        CERT_PEM="${CERT_TMP_DIR}/cert.pem"
        CERT_P12="${CERT_TMP_DIR}/cert.p12"
        cat <<EOF > "$CERT_CONF_TMP"
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = SparkleRecorder-SelfSigned
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
        
        openssl req -x509 -newkey rsa:2048 -keyout "$KEY_PEM" -out "$CERT_PEM" -sha256 -days 3650 -nodes -config "$CERT_CONF_TMP" -extensions ext
        openssl pkcs12 -export -legacy -inkey "$KEY_PEM" -in "$CERT_PEM" -out "$CERT_P12" -passout pass:123456
        security import "$CERT_P12" -f pkcs12 -P 123456 -A -T /usr/bin/codesign
        security add-trusted-cert -p codeSign -r trustRoot "$CERT_PEM"
        
        rm -rf "$CERT_TMP_DIR"
        SIGN_ID="SparkleRecorder-SelfSigned"
    fi
fi

if [ -n "$SIGN_ID" ]; then
    case "$SIGN_ID" in
        *"Developer ID"*)
            echo "→ Signing with Developer ID (hardened runtime): ${SIGN_ID}"
            sign_app "--options runtime --timestamp" "$SIGN_ID"
            ;;
        *)
            echo "→ Signing with stable identity (TCC grants persist): ${SIGN_ID}"
            sign_app "" "$SIGN_ID"
            ;;
    esac
    SIGNED_WITH="$SIGN_ID"
else
    echo "→ No signing identity found — ad-hoc signing (permissions re-prompt per rebuild)."
    sign_app "" "-"
    SIGNED_WITH="ad-hoc"
fi

echo
echo "✅ Installed: ${APP_BUNDLE}"
echo "   Signed:   ${SIGNED_WITH}"
echo "   Run:  open \"${APP_BUNDLE}\""
