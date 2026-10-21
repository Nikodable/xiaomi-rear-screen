#!/usr/bin/env bash
# Compile « Ecran arriere.app » (Apple Silicon) : interface Swift + scrcpy/adb embarqués.
# Prérequis : Xcode Command Line Tools (swiftc). Sortie : macos/dist/
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
SRC="$ROOT/third_party/scrcpy-macos-aarch64-v4.1"
APP="dist/Ecran arriere.app"
ZIP="dist/RearScreen-macOS-arm64-v$VERSION.zip"

[[ -x "$SRC/scrcpy" ]] || "$ROOT/scripts/fetch-scrcpy.sh" --mac

rm -rf dist; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos12.0 swift/Strings.swift swift/main.swift -o "$APP/Contents/MacOS/EcranArriere"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
cp "$SRC/scrcpy" "$SRC/adb" "$SRC/scrcpy-server" "$SRC/LICENSE" "$APP/Contents/Resources/"
cp "$ROOT/NOTICE" "$APP/Contents/Resources/NOTICE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Écran arrière</string>
  <key>CFBundleDisplayName</key><string>Écran arrière</string>
  <key>CFBundleIdentifier</key><string>local.ecran-arriere</string>
  <key>CFBundleExecutable</key><string>EcranArriere</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"   # signature ad hoc (pas de certificat développeur)

# archive : l'app + le README (installation + changelog)
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
{ sed 's#\.\./docs/overview\.png#overview.png#' README.md; printf '\n---\n\n'; cat "$ROOT/CHANGELOG.md"; } > "$STAGE/README.md"
cp "$ROOT/docs/overview.png" "$STAGE/overview.png"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --noacl "$STAGE" "$ZIP"
rm -rf "$STAGE"
echo "OK : $APP"
ls -lh "$ZIP"
