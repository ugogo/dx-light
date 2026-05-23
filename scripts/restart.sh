#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$ROOT/scripts/stop.sh"
sleep 0.3
bash "$ROOT/scripts/start.sh"
