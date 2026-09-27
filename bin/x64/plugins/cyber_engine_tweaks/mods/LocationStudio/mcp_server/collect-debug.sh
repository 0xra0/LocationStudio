#!/usr/bin/env sh
set -eu

MOD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT="$MOD_DIR/logs/LocationStudio-debug-$STAMP.zip"

cd "$MOD_DIR"
set -- logs/locationstudio.log logs/locationstudio.log.1 logs/locationstudio-diagnostics.json logs/LocationStudio-v0.24.0-support.txt logs/LocationStudio-support.txt bridge/status.json bridge/response.json data/config.json
FOUND=""
for ITEM in "$@"; do
    if [ -f "$ITEM" ]; then FOUND="$FOUND $ITEM"; fi
done
if [ -z "$FOUND" ]; then
    echo "No LocationStudio diagnostic files exist yet. Start the game and open CET once." >&2
    exit 1
fi
# shellcheck disable=SC2086
zip -q "$OUTPUT" $FOUND
printf '%s\n' "$OUTPUT"
