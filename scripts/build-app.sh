#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product DXLight
swift build -c release --product dx-light-cli

APP_NAME="DX Light"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/DXLight" "$MACOS/$APP_NAME"
cp "$ROOT/DXLight/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/DXLight.entitlements" "$CONTENTS/entitlements.plist"

chmod +x "$MACOS/$APP_NAME"

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built $APP_DIR"
echo "CLI: $BUILD_DIR/dx-light-cli"
