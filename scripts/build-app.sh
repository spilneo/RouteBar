#!/bin/sh
set -eu

# Builds a universal, ad-hoc signed RouteBar.app in the repository root.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/RouteBar.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
xcrun swift build -c release --arch arm64 --arch x86_64
BIN="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN/RouteBar" "$CONTENTS/MacOS/RouteBar"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/RouteBar.icns" "$CONTENTS/Resources/RouteBar.icns"
codesign --force --sign - "$APP"

printf 'Created %s\n' "$APP"
