#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/dist/DX Light.app"

bash "$ROOT/scripts/build-app.sh"

if pgrep -x "DX Light" >/dev/null 2>&1; then
  echo "DX Light is already running. Restart to use the rebuilt app."
else
  open "$APP_PATH"
  echo "Started DX Light."
fi
