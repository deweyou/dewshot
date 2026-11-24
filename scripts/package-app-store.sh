#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${FRAME_APP_STORE_APP_IDENTITY:?Set FRAME_APP_STORE_APP_IDENTITY to an Apple Distribution identity.}"
: "${FRAME_APP_STORE_INSTALLER_IDENTITY:?Set FRAME_APP_STORE_INSTALLER_IDENTITY to a Mac Installer Distribution identity.}"
: "${FRAME_APP_STORE_PROFILE:?Set FRAME_APP_STORE_PROFILE to the Mac App Store Connect provisioning profile.}"

if [[ ! -f "$FRAME_APP_STORE_PROFILE" ]]; then
    echo "Mac App Store Connect provisioning profile not found: $FRAME_APP_STORE_PROFILE" >&2
    exit 1
fi

case "$FRAME_APP_STORE_APP_IDENTITY" in
    "Apple Distribution: "*|"3rd Party Mac Developer Application: "*) ;;
    *)
        echo "The app must use an Apple Distribution or Mac App Distribution identity." >&2
        exit 1
        ;;
esac
case "$FRAME_APP_STORE_INSTALLER_IDENTITY" in
    "3rd Party Mac Developer Installer: "*|"Mac Installer Distribution: "*) ;;
    *)
        echo "The installer must use a Mac Installer Distribution identity." >&2
        exit 1
        ;;
esac

if ! security find-identity -v -p codesigning | grep -F "\"$FRAME_APP_STORE_APP_IDENTITY\"" >/dev/null; then
    echo "App distribution signing identity not found in the keychain." >&2
    exit 1
fi
if ! security find-identity -v | grep -F "\"$FRAME_APP_STORE_INSTALLER_IDENTITY\"" >/dev/null; then
    echo "Installer distribution signing identity not found in the keychain." >&2
    exit 1
fi

OUTPUT_ROOT="${FRAME_APP_STORE_OUTPUT_ROOT:-$ROOT_DIR/.build/app-store}"
mkdir -p "$OUTPUT_ROOT"
STAGING_DIR="$(mktemp -d "$OUTPUT_ROOT/.staging.XXXXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
PROFILE_PLIST="$STAGING_DIR/profile.plist"
ENTITLEMENTS="$STAGING_DIR/dewShot.entitlements"

security cms -D -i "$FRAME_APP_STORE_PROFILE" > "$PROFILE_PLIST"
TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROFILE_PLIST")"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
PACKAGE_CONFIGURATION="$(FRAME_APP_VARIANT=production FRAME_APP_SANDBOX=1 FRAME_APP_OUTPUT_ROOT="$STAGING_DIR" \
    "$ROOT_DIR/scripts/package-app.sh" --print-configuration)"
BUNDLE_ID="$(sed -n 's/^FRAME_BUNDLE_ID=//p' <<< "$PACKAGE_CONFIGURATION")"
APP_DIR="$(sed -n 's/^FRAME_APP_PATH=//p' <<< "$PACKAGE_CONFIGURATION")"

if [[ -z "$BUNDLE_ID" || "$APP_ID" != *."$BUNDLE_ID" || "$APP_ID" == *"*"* ]]; then
    echo "The provisioning profile must use the explicit production bundle ID ($BUNDLE_ID)." >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$PROFILE_PLIST" >/dev/null 2>&1 ||
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$PROFILE_PLIST" 2>/dev/null || true)" == true ]]; then
    echo "Use a Mac App Store Connect profile for TestFlight." >&2
    exit 1
fi

FRAME_APP_VARIANT=production FRAME_APP_SANDBOX=1 FRAME_APP_OUTPUT_ROOT="$STAGING_DIR" \
    FRAME_REQUIRE_TELEMETRY=1 FRAME_CODESIGN_IDENTITY=- "$ROOT_DIR/scripts/package-app.sh"
# Embed the profile bytes without browser download metadata.
cat "$FRAME_APP_STORE_PROFILE" > "$APP_DIR/Contents/embedded.provisionprofile"
xattr -r "$APP_DIR" > "$STAGING_DIR/app-xattrs.txt"
if grep -Eq '(^|: )com\.apple\.quarantine$' "$STAGING_DIR/app-xattrs.txt"; then
    echo "The staged app contains quarantine attributes that the Mac App Store rejects." >&2
    exit 1
fi
cp "$ROOT_DIR/scripts/app-sandbox.entitlements" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
codesign --force --sign "$FRAME_APP_STORE_APP_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
SIGNED_TEAM="$(codesign -dv --verbose=2 "$APP_DIR" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ "$SIGNED_TEAM" != "$TEAM_ID" ]]; then
    echo "The app signing identity and provisioning profile belong to different teams." >&2
    exit 1
fi
codesign -d --extract-certificates="$STAGING_DIR/signer" "$APP_DIR"
PROFILE_CERT_HASH="$(plutil -extract DeveloperCertificates.0 raw -expect data -o - "$PROFILE_PLIST" \
    | base64 -D | shasum -a 256 | cut -d ' ' -f 1)"
SIGNED_CERT_HASH="$(shasum -a 256 "$STAGING_DIR/signer0" | cut -d ' ' -f 1)"
if [[ "$SIGNED_CERT_HASH" != "$PROFILE_CERT_HASH" ]]; then
    echo "The provisioning profile does not authorize the certificate used to sign the app." >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP_DIR/Contents/Info.plist")"
PACKAGE_NAME="dewShot-$VERSION-build.$BUILD-AppStore.pkg"
productbuild --sign "$FRAME_APP_STORE_INSTALLER_IDENTITY" --component "$APP_DIR" /Applications \
    "$STAGING_DIR/$PACKAGE_NAME"
pkgutil --check-signature "$STAGING_DIR/$PACKAGE_NAME"
DSYM="$ROOT_DIR/.build/release/dewShot.dSYM"
app_uuids="$(dwarfdump --uuid "$APP_DIR/Contents/MacOS/dewShot" | awk '{print $2,$3}')"
symbol_uuids="$(dwarfdump --uuid "$DSYM" | awk '{print $2,$3}')"
if [[ -z "$app_uuids" || "$app_uuids" != "$symbol_uuids" ]]; then
    echo "The release dSYM does not match the packaged executable." >&2
    exit 1
fi
symbols_name="${PACKAGE_NAME%.pkg}.dSYM.zip"
ditto -c -k --keepParent "$DSYM" "$STAGING_DIR/$symbols_name"
mv -f "$STAGING_DIR/$symbols_name" "$OUTPUT_ROOT/$symbols_name"
mv -f "$STAGING_DIR/$PACKAGE_NAME" "$OUTPUT_ROOT/$PACKAGE_NAME"
echo "Packaged $OUTPUT_ROOT/$PACKAGE_NAME for Transporter."
