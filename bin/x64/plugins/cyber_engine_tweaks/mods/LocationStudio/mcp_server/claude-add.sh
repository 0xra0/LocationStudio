#!/usr/bin/env bash
set -euo pipefail
MOD="${LOCATION_STUDIO_MOD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PYTHON="${PYTHON:-/usr/bin/python3}"
exec claude mcp add location-studio \
  --transport stdio \
  --scope project \
  -e "LOCATION_STUDIO_MOD_DIR=$MOD" \
  -- \
  "$PYTHON" \
  "$MOD/mcp_server/server.py"
