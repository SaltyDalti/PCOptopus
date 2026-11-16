#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build --product PCOptopus -c debug
BIN=".build/debug/PCOptopus"
APP="$ROOT/dist/PCOptopus.app"
INSTALL_APP="/Applications/PCOptopus.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PCOptopus"
chmod +x "$APP/Contents/MacOS/PCOptopus"

# Entitlements: not sandboxed — Full Disk Access can apply.
cat > "$APP/Contents/Resources/PCOptopus.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <false/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
ENT

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>PCOptopus</string>
  <key>CFBundleIdentifier</key>
  <string>local.pcoptopus.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PCOptopus</string>
  <key>CFBundleDisplayName</key>
  <string>PCOptopus</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>PCOptopus scans Desktop for old unused files when recommending storage reclaim. It never deletes without you.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>PCOptopus scans Documents for old unused files when recommending storage reclaim. It never deletes without you.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>PCOptopus scans Downloads for old installers and unused files when recommending storage reclaim. It never deletes without you.</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>PCOptopus only reads volumes you point it at for storage health. It never deletes without you.</string>
</dict>
</plist>
PLIST

# Prefer a persistent local signing identity so Full Disk Access survives rebuilds.
SIGN_ID=""
SIGN_ID="$("$ROOT/Scripts/ensure-signing-identity.sh" 2>/dev/null || true)"
SIGN_ID="${SIGN_ID//$'\n'/}"

ENTITLEMENTS="$APP/Contents/Resources/PCOptopus.entitlements"
SIGN_KEYCHAIN="${HOME}/Library/Keychains/pcoptopus-signing.keychain-db"
sign_app() {
  local target="$1"
  if [[ -n "$SIGN_ID" ]]; then
    # Unlock dedicated keychain (known password) so codesign never pops login UI.
    if [[ -f "$SIGN_KEYCHAIN" ]]; then
      security unlock-keychain -p "pcoptopus-signing" "$SIGN_KEYCHAIN" >/dev/null 2>&1 || true
    fi
    # No --options runtime: hardened runtime + self-signed often breaks local FDA/TCC.
    codesign --force --deep \
      --sign "$SIGN_ID" \
      --keychain "$SIGN_KEYCHAIN" \
      --identifier "local.pcoptopus.app" \
      --entitlements "$ENTITLEMENTS" \
      "$target"
  else
    # Ad-hoc fallback (TCC resets after each rebuild — avoid this).
    codesign --force --deep \
      --sign - \
      --identifier "local.pcoptopus.app" \
      --entitlements "$ENTITLEMENTS" \
      "$target"
  fi
}

sign_app "$APP"
if [[ -n "$SIGN_ID" ]]; then
  echo "Signed with: $SIGN_ID"
else
  echo "Signed ad-hoc (sticky Full Disk Access needs the local signing cert)"
fi

# Install the stable copy macOS privacy settings should point at.
rm -rf "$INSTALL_APP"
ditto "$APP" "$INSTALL_APP"
sign_app "$INSTALL_APP"

echo "Built $APP"
echo "Installed $INSTALL_APP"
codesign -dv --verbose=2 "$INSTALL_APP" 2>&1 | grep -E '^(Authority|Identifier|Signature|TeamIdentifier)=' || true
echo "Grant Full Disk Access once to /Applications/PCOptopus.app, then always open that copy."
