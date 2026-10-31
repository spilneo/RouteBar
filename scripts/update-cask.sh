#!/bin/sh
set -eu

# Writes the Homebrew cask for a published RouteBar release.
# Usage: ./scripts/update-cask.sh <tag> <output.rb>
# The asset is downloaded and hashed, so the cask always matches the real file.

TAG="${1:?usage: update-cask.sh <tag> <output.rb>}"
OUT="${2:?usage: update-cask.sh <tag> <output.rb>}"
REPOSITORY="${ROUTEBAR_REPOSITORY:-spilneo/RouteBar}"
VERSION="${TAG#v}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL --retry 3 -o "$WORK/RouteBar.zip" \
    "https://github.com/$REPOSITORY/releases/download/$TAG/RouteBar.zip"
SHA256="$(shasum -a 256 "$WORK/RouteBar.zip" | awk '{print $1}')"

mkdir -p "$(dirname -- "$OUT")"
cat > "$OUT" <<RUBY
# frozen_string_literal: true

cask "routebar" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/RouteBar.zip"
  name "RouteBar"
  desc "Menu bar endpoint, usage and model picker for OmniRoute"
  homepage "https://github.com/$REPOSITORY"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on formula: "node"
  depends_on macos: :sonoma

  app "RouteBar.app"

  # RouteBar is ad-hoc signed, not notarized. Clearing the quarantine flag lets
  # it open on first launch without a Gatekeeper prompt.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/RouteBar.app"],
        must_succeed: false
  end

  uninstall quit: "com.spilneo.RouteBar"

  zap trash: [
    "~/Library/Logs/RouteBar",
    "~/Library/Preferences/com.spilneo.RouteBar.plist",
  ]
end
RUBY

printf 'Wrote %s for %s (%s)\n' "$OUT" "$VERSION" "$SHA256"
