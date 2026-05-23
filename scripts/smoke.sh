#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/.build/release/dx-light-cli"

cd "$ROOT"

swift build -c release --product dx-light-cli

echo "DX Light smoke test"
echo
echo "Before continuing:"
echo "  - Connect the DX Light bar over USB."
echo "  - Quit the official DX Light app and any other app using the bar."
echo
read -r -p "Press Enter to start..."

"$CLI" list

echo
echo "Turning light on at 50%..."
"$CLI" on 0.5
read -r -p "Did the bar turn on? Press Enter to continue..."

echo "Setting brightness to 25%..."
"$CLI" brightness 0.25
read -r -p "Did brightness change? Press Enter to continue..."

echo "Turning light off..."
"$CLI" off
read -r -p "Did the bar turn off? Press Enter to continue..."

echo
echo "Smoke test commands completed."
echo "Manual reconnect check: unplug/replug the bar, start the app, and confirm the menu shows connected."
