#!/bin/sh
set -u
OUT=${1:?output path required}
DELAY=${2:-0.45}
ERR="$OUT.error"
DIR=$(dirname "$OUT")
mkdir -p "$DIR"
rm -f "$ERR"
TMP="$DIR/.locationstudio_capture_$$.png"
RAW="$DIR/.locationstudio_raw_$$.png"
cleanup() { rm -f "$TMP" "$RAW"; }
fail() { printf '%s\n' "$1" > "$ERR"; cleanup; exit "${2:-1}"; }
trap cleanup EXIT INT TERM
sleep "$DELAY"

capture_ok=0
if command -v grim >/dev/null 2>&1; then grim "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
if [ "$capture_ok" -eq 0 ] && command -v maim >/dev/null 2>&1; then maim "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
if [ "$capture_ok" -eq 0 ] && command -v scrot >/dev/null 2>&1; then scrot -o "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
if [ "$capture_ok" -eq 0 ] && command -v import >/dev/null 2>&1; then import -window root "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
if [ "$capture_ok" -eq 0 ] && command -v gnome-screenshot >/dev/null 2>&1; then gnome-screenshot -f "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
if [ "$capture_ok" -eq 0 ] && command -v spectacle >/dev/null 2>&1; then spectacle -b -n -o "$RAW" >/dev/null 2>&1 && capture_ok=1 || true; fi
[ "$capture_ok" -eq 1 ] || fail 'No supported screenshot tool succeeded. Install/use grim, maim, scrot, ImageMagick import, gnome-screenshot, or spectacle.' 4
[ -s "$RAW" ] || fail 'Screenshot command ran but produced no image.' 5

# Crop the center of the real game frame where the aim preview is displayed.
if command -v magick >/dev/null 2>&1; then
  magick "$RAW" -gravity center -crop '62%x72%+0+0' +repage -resize '512x512^' -gravity center -extent 512x512 "$TMP" >/dev/null 2>&1 || fail 'ImageMagick failed while cropping the thumbnail.' 6
elif command -v convert >/dev/null 2>&1; then
  convert "$RAW" -gravity center -crop '62%x72%+0+0' +repage -resize '512x512^' -gravity center -extent 512x512 "$TMP" >/dev/null 2>&1 || fail 'ImageMagick convert failed while cropping the thumbnail.' 6
else
  cp "$RAW" "$TMP" || fail 'Could not copy captured screenshot into thumbnail cache.' 6
fi
mv -f "$TMP" "$OUT" || fail 'Could not write thumbnail PNG.' 7
rm -f "$ERR"
exit 0
