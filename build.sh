#!/bin/bash
# Offline macOS build. Only Apple Command Line Tools and system frameworks are used.
set -euo pipefail
cd "$(dirname "$0")"
install_app=false
case "${1:-}" in
  "") ;;
  --install) install_app=true ;;
  --help|-h) echo 'Usage: ./build.sh [--install]'; echo 'Build, test and sign; optionally install in ~/Applications.'; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then echo 'Too many arguments.' >&2; exit 2; fi
if [[ "$(uname -s)" != Darwin ]]; then echo 'macOS is required.' >&2; exit 1; fi
for tool in xcrun sips iconutil codesign plutil; do
  command -v "$tool" >/dev/null || { echo "Missing Apple tool: $tool" >&2; exit 1; }
done
xcrun --find swiftc >/dev/null
app="$PWD/build/SpaceKeys.app"
iconset="$PWD/build/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

echo 'Creating macOS icon…'
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon.png "$app/Contents/Resources/AppIcon.png"
cp Licenses/* "$app/Contents/Resources/"
cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"

echo 'Compiling…'
xcrun clang -std=c11 -fblocks -Wall -Wextra -Werror -O2 -c Sources/Bridge.c -o build/Bridge.o
xcrun swiftc -swift-version 5 -warnings-as-errors -module-cache-path "$CLANG_MODULE_CACHE_PATH" -O \
  -import-objc-header Sources/Bridge.h Sources/Core.swift Sources/StatusWindow.swift Sources/main.swift build/Bridge.o \
  -framework AppKit -framework Carbon -framework ServiceManagement \
  -F /System/Library/PrivateFrameworks -framework SkyLight \
  -o "$app/Contents/MacOS/SpaceKeys"

echo 'Running core tests (no desktop changes)…'
xcrun swiftc -swift-version 5 -warnings-as-errors -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/Core.swift Tests/main.swift -framework AppKit -o build/core-tests
build/core-tests

echo 'Signing and verifying…'
# Set CODESIGN_IDENTITY to an existing developer identity for a stable signing identity.
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier local.mw4rf.SpaceKeys "$app"
codesign --verify --strict "$app"
echo "Built and verified: $app"
if $install_app; then
  destination="$HOME/Applications/SpaceKeys.app"
  if pgrep -f "^$destination/Contents/MacOS/SpaceKeys$" >/dev/null; then
    echo 'Quit SpaceKeys before installing the new build.' >&2
    exit 1
  fi
  mkdir -p "$HOME/Applications"
  ditto "$app" "$destination"
  codesign --verify --strict "$destination"
  echo "Installed: $destination"
fi
