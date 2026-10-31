#!/bin/sh
set -eu

# Regenerates Resources/RouteBar.icns from logo.svg. Needs rsvg-convert (brew install librsvg).
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/RouteBar.iconset"
trap 'rm -rf "$WORK"' EXIT

command -v rsvg-convert >/dev/null 2>&1 || { echo "rsvg-convert is required: brew install librsvg" >&2; exit 1; }

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$ROOT/logo.svg" -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ROOT/logo.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/RouteBar.icns"
echo "Created $ROOT/Resources/RouteBar.icns"
