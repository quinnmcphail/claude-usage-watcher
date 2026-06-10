#!/usr/bin/env bash
set -euo pipefail

# Assemble a distributable .app bundle from the Swift package.
# Run from anywhere: we cd to the package root (macos/) first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

APP_VERSION="${APP_VERSION:-0.0.0-dev}"
APP_NAME="ClaudeUsageWatcher"
BUNDLE_ID="io.github.deltaecho801.ClaudeUsageWatcher"

# Prefer a universal release build; fall back to a plain release build on older
# toolchains that don't support the double --arch form.
echo "Building release binary..."
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "Universal build unavailable; falling back to plain release build."
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)"
fi

BINARY="$BIN_PATH/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    echo "error: built binary not found at $BINARY" >&2
    exit 1
fi

APP_DIR="dist/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage Watcher</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets the app run locally.
echo "Code-signing (ad-hoc)..."
codesign --force --sign - "$APP_DIR"

echo "Built: $(cd "$(dirname "$APP_DIR")" && pwd)/$(basename "$APP_DIR")"
