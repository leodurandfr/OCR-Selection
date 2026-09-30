#!/usr/bin/env bash
# release.sh — build a notarized OCR Selection .dmg and (optionally) publish it
# as a GitHub Release.
#
#   1. archive the Release configuration (universal: arm64 + x86_64);
#   2. export it signed with Developer ID (hardened runtime + secure timestamp);
#   3. wrap the app in a drag-to-Applications .dmg, signed as well;
#   4. notarize the .dmg with notarytool and staple the ticket;
#   5. with PUBLISH=1, create the GitHub Release vX.Y and upload the .dmg.
#
# No secrets live here: the notarization credentials come from a notarytool
# keychain profile, created once with
#   xcrun notarytool store-credentials OCRSelectionNotary \
#     --apple-id <apple-id> --team-id 7C2S8B9978
# (it prompts for an app-specific password from account.apple.com).
#
# Env (all optional):
#   NOTARY_PROFILE  keychain profile name        (default: OCRSelectionNotary)
#   SKIP_NOTARIZE=1 stop after signing the .dmg  (local smoke test)
#   PUBLISH=1       create the GitHub Release and upload the .dmg
# The version is the project's MARKETING_VERSION; bump it in Xcode first.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="OCRSelection"
DISPLAY_NAME="OCR Selection"
TEAM_ID="7C2S8B9978"
NOTARY_PROFILE="${NOTARY_PROFILE:-OCRSelectionNotary}"

# xcodebuild must come from Xcode, not the Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# SwiftPM's package cache is a bare git repo; safe.bareRepository=explicit
# (set by some git configs) makes package resolution fail.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }

if [[ "${PUBLISH:-0}" == "1" && -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  echo "Working tree is dirty — commit before publishing a release." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ---------------------------------------------------------------------------
step "1/5 Archive (Release)"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
xcodebuild \
  -project "$REPO_ROOT/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -quiet \
  archive

# ---------------------------------------------------------------------------
step "2/5 Export signed with Developer ID"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates \
  -quiet

APP="$BUILD_DIR/export/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Exported app not found: $APP" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "  version $VERSION ($BUILD)"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Authority=Developer ID Application|Timestamp|Runtime Version)'

# ---------------------------------------------------------------------------
step "3/5 Build the .dmg"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
if command -v create-dmg >/dev/null; then
  # create-dmg lays out the Finder window through AppleScript; --skip-jenkins
  # falls back to a plain window when Finder automation isn't allowed.
  create-dmg \
    --volname "$DISPLAY_NAME" \
    --window-size 540 360 \
    --icon-size 112 \
    --icon "$APP_NAME.app" 140 170 \
    --app-drop-link 400 170 \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG" "$STAGE" >/dev/null \
  || create-dmg --skip-jenkins --volname "$DISPLAY_NAME" --app-drop-link 400 170 \
       "$DMG" "$STAGE" >/dev/null
else
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
fi
# Sign with the exact certificate the export used (matching the identity by
# name trips over the accented "é" and over duplicate Developer ID certs).
( cd "$BUILD_DIR" && codesign -d --extract-certificates="$BUILD_DIR/cert" "$APP" 2>/dev/null )
IDENTITY="$(shasum -a 1 "$BUILD_DIR/cert0" | awk '{print toupper($1)}')"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "  → $DMG"

# ---------------------------------------------------------------------------
step "4/5 Notarize + staple"
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "  SKIP_NOTARIZE=1 → skipped (the .dmg will be rejected by Gatekeeper)."
else
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m \
    | tee "$BUILD_DIR/notarytool.log"
  if ! grep -q 'status: Accepted' "$BUILD_DIR/notarytool.log"; then
    SUBMISSION_ID="$(awk '/^  id:/ {print $2; exit}' "$BUILD_DIR/notarytool.log")"
    echo "Notarization failed. Details:" >&2
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
shasum -a 256 "$DMG" | tee "$DMG.sha256"

# ---------------------------------------------------------------------------
step "5/5 GitHub Release"
if [[ "${PUBLISH:-0}" != "1" ]]; then
  echo "  PUBLISH=1 not set → skipped."
elif [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "Refusing to publish a .dmg that isn't notarized." >&2
  exit 1
else
  TAG="v$VERSION"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" --clobber
  else
    git -C "$REPO_ROOT" tag -a "$TAG" -m "$DISPLAY_NAME $VERSION" 2>/dev/null || true
    git -C "$REPO_ROOT" push origin "$TAG"
    gh release create "$TAG" "$DMG" \
      --title "$DISPLAY_NAME $VERSION" \
      --generate-notes \
      --notes "Requires macOS 26 or later. Download **$APP_NAME-$VERSION.dmg**, open it and drag OCR Selection into Applications."
  fi
  gh release view "$TAG" --json url --jq .url
fi

step "Done: $DMG"
