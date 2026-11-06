#!/bin/bash
# Builds a universal (Apple silicon + Intel) Corners.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Corners.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "build/obj/Corners-$arch"
done
lipo -create build/obj/Corners-* -output "$APP/Contents/MacOS/Corners"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O Sources/Artwork.swift tools/make_icon/main.swift -o build/obj/make_icon
build/obj/make_icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" build/Corners.zip
echo "Built $APP and build/Corners.zip"
