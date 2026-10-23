#!/bin/sh
# Рендерит макеты в ../screens/*.png (1920×1080) и лист компонентов через headless Chrome.
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
OUT=../screens
mkdir -p "$OUT"
NAMES=$(sed -n "s/^SCREENS\['\([^']*\)'\].*/\1/p" mockups.js | grep -v 00-components)
for n in $NAMES; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1920,1080 --virtual-time-budget=4000 \
    --screenshot="$OUT/$n.png" "file://$PWD/mockups.html#$n" 2>/dev/null
  echo "$OUT/$n.png"
done
H=$("$CHROME" --headless=new --disable-gpu --window-size=1920,1080 --virtual-time-budget=4000 --dump-dom \
  "file://$PWD/mockups.html#00-components" 2>/dev/null | sed -n 's/.*data-h="\([0-9]*\)".*/\1/p' | head -1)
H=${H:-9000}
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1920,$H --virtual-time-budget=4000 \
  --screenshot="$OUT/00-components.png" "file://$PWD/mockups.html#00-components" 2>/dev/null
echo "$OUT/00-components.png"
