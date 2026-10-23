#!/bin/sh
# Экспорт PNG из src/*.svg через headless Chrome (Manrope грузится с Google Fonts для баннера).
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP=$(mktemp -d)
mkdir -p png/legacy png/adaptive png/banner
render() { # svg w h out
  { echo '<!doctype html><html><head><meta charset="utf-8"><link href="https://fonts.googleapis.com/css2?family=Manrope:wght@800&display=swap" rel="stylesheet">'
    echo "<style>html,body{margin:0;background:transparent}svg{display:block;width:${2}px;height:${3}px}</style></head><body>"
    cat "src/$1"; echo '</body></html>'; } > "$TMP/p.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$2,$3" --virtual-time-budget=4000 \
    --screenshot="$4" "file://$TMP/p.html" 2>/dev/null
  echo "$4"
}
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render ic_launcher_legacy.svg ${d#*:} ${d#*:} "png/legacy/ic_launcher-${d%%:*}-${d#*:}.png"
done
for l in foreground background monochrome; do
  render ic_launcher_$l.svg 432 432 "png/adaptive/ic_launcher_$l-432.png"
done
for s in 320x180:xhdpi 480x270:xxhdpi 640x360:xxxhdpi; do
  wh=${s%%:*}; render tv_banner.svg ${wh%x*} ${wh#*x} "png/banner/tv_banner-${s#*:}-$wh.png"
done
rm -rf "$TMP"
