#!/bin/bash
# Installs the latest Corners release into /Applications.
# Downloading with curl (rather than a browser) means macOS doesn't flag the
# app as "downloaded from the internet", so there's no Gatekeeper prompt.
set -euo pipefail
URL="https://github.com/Fox-IV/Corners/releases/latest/download/Corners.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading Corners…"
curl -fsSL "$URL" -o "$TMP/Corners.zip"
ditto -x -k "$TMP/Corners.zip" "$TMP"
pkill -x Corners 2>/dev/null || true
rm -rf /Applications/Corners.app
mv "$TMP/Corners.app" /Applications/
echo "Installed to /Applications/Corners.app"
open /Applications/Corners.app
