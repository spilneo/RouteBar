#!/bin/sh
set -eu

# Builds a universal, ad-hoc signed RouteBar.app in the repository root.
#
# Each architecture is built for an explicit triple carrying the minimum macOS
# version from Info.plist. A plain `--arch` build targets the SDK's macOS
# version, which warns that x86_64 is deprecated there even though RouteBar
# still supports Intel Macs on older macOS releases.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/RouteBar.app"
CONTENTS="$APP/Contents"
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/Resources/Info.plist")"

cd "$ROOT"
build() {
    TRIPLE="$1-apple-macosx$MIN_MACOS"
    SCRATCH="$ROOT/.build/release-$1"
    xcrun swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" >&2
    printf '%s/RouteBar' "$(xcrun swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)"
}
ARM64_BIN="$(build arm64)"
X86_64_BIN="$(build x86_64)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
xcrun lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$CONTENTS/MacOS/RouteBar"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/RouteBar.icns" "$CONTENTS/Resources/RouteBar.icns"
codesign --force --sign - "$APP"

printf 'Created %s\n' "$APP"
