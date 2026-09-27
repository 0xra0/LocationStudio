#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${1:-"$ROOT/publish"}
exec dotnet publish "$ROOT/cp77wb-wkit-worker.csproj" -c Release -o "$OUT"
