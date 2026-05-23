#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/dist/DX Light.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not built. Run: npm run build" >&2
  exit 1
fi

if pgrep -x "DX Light" >/dev/null 2>&1; then
  echo "DX Light is already running."
  exit 0
fi

open "$APP_PATH"
echo "Started DX Light."
