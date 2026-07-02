#!/usr/bin/env bash
# Renders the Android launcher-icon and splash PNGs from the SVG masters in
# this directory into android/app/src/main/res/. Run after editing a master.
#
# Requires rsvg-convert (brew install librsvg / apt install librsvg2-bin).
#
# Outputs:
#   mipmap-<dpi>/ic_launcher_{foreground,background,monochrome}.png  (108dp base)
#   mipmap-<dpi>/ic_launcher.png   legacy pre-API-26 icon (48dp base), composited
#                                  from the adaptive layers by ic_launcher_legacy.svg
#   drawable-<dpi>/ic_splash.png   splash mark (288dp base, Android-12 mask safe)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$HERE/../../android/app/src/main/res"

render() { # svg base-dp out-subpath
  local svg="$1" base="$2" out="$3"
  local scales=(mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4)
  for pair in "${scales[@]}"; do
    local dpi="${pair%%:*}" scale="${pair##*:}"
    local px; px=$(awk "BEGIN{printf \"%d\", $base*$scale}")
    local dir; dir="$RES/$(dirname "$out" | sed "s/DPI/$dpi/")"
    mkdir -p "$dir"
    rsvg-convert -w "$px" -h "$px" "$HERE/$svg" -o "$dir/$(basename "$out")"
  done
}

for layer in foreground background monochrome; do
  render "ic_launcher_$layer.svg" 108 "mipmap-DPI/ic_launcher_$layer.png"
done
render ic_launcher_legacy.svg 48 mipmap-DPI/ic_launcher.png
render ic_launcher_foreground.svg 288 drawable-DPI/ic_splash.png

echo "rendered into $RES"
