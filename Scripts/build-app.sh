#!/bin/bash
# Builds build/CmdTab.app.
#   --install  copy it to /Applications
#   --run      quit any running copy and launch the new one
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/CmdTab.app"
BUNDLE_ID="${BUNDLE_ID:-com.joelmale.cmdtab}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/CmdTab" "$APP/Contents/MacOS/CmdTab"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CmdTab</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>CmdTab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# An ad-hoc signature changes on every build, and macOS then forgets the
# Accessibility and Screen Recording grants. A real identity keeps them.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

for flag in "$@"; do
    case "$flag" in
        --install)
            rm -rf /Applications/CmdTab.app
            cp -R "$APP" /Applications/CmdTab.app
            APP="/Applications/CmdTab.app"
            echo "Installed $APP"
            ;;
        --run)
            pkill -x CmdTab && while pgrep -x CmdTab >/dev/null; do sleep 0.1; done || true
            open "$APP"
            ;;
        *)
            echo "Unknown option: $flag" >&2
            exit 1
            ;;
    esac
done
