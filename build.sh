#!/bin/sh
# Compile en release et assemble Verto.app (app de barre de menus, sans icône Dock).
# Appelle swiftc directement plutôt que `swift build` : pas de dépendance, et ça fonctionne
# même quand SwiftPM est cassé (Command Line Tools partiellement mis à jour).
set -e
cd "$(dirname "$0")"
BIN=.build/manual/Verto
mkdir -p "$(dirname "$BIN")"
swiftc -O -swift-version 5 -module-name Verto \
    -target "$(uname -m)-apple-macos14.0" \
    Sources/Verto/*.swift -o "$BIN"
APP=Verto.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Verto"
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Verto</string>
    <key>CFBundleIdentifier</key><string>io.github.ghigt.verto</string>
    <key>CFBundleName</key><string>Verto</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "OK → $(pwd)/$APP"
