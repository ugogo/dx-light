#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/dist/DX Light.app"

bash "$ROOT/scripts/stop.sh"
sleep 0.3
bash "$ROOT/scripts/build-app.sh"
open "$APP_PATH"
echo "Restarted DX Light."
