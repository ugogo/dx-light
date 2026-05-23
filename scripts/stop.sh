#!/bin/bash
set -euo pipefail

if ! pgrep -x "DX Light" >/dev/null 2>&1; then
  echo "DX Light is not running."
  exit 0
fi

osascript -e 'tell application "DX Light" to quit' >/dev/null 2>&1 || true
pkill -x "DX Light" >/dev/null 2>&1 || true

for _ in {1..20}; do
  if ! pgrep -x "DX Light" >/dev/null 2>&1; then
    echo "Stopped DX Light."
    exit 0
  fi
  sleep 0.1
done

echo "Failed to stop DX Light." >&2
exit 1
