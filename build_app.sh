#!/bin/bash
set -euo pipefail
APP_NAME="Mac Disk Imager"
VERSION="1.0.0"
BUILD_NUMBER="10"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

rm -rf "$ROOT/.build" "$ROOT/dist"
swift package reset >/dev/null 2>&1 || true

build_arch() {
  local arch="$1"
  swift build -c release --arch "$arch"
  mkdir -p "$ROOT/.artifacts/$arch"
  cp "$ROOT/.build/$arch-apple-macosx/release/MacDiskImager" "$ROOT/.artifacts/$arch/"
  cp "$ROOT/.build/$arch-apple-macosx/release/MacDiskImagerHelper" "$ROOT/.artifacts/$arch/"
}

rm -rf "$ROOT/.artifacts"
HOST_ARCH="$(uname -m)"
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  build_arch x86_64
  build_arch arm64
else
  build_arch "$HOST_ARCH"
fi

APP="$ROOT/dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  lipo -create "$ROOT/.artifacts/x86_64/MacDiskImager" "$ROOT/.artifacts/arm64/MacDiskImager" -output "$APP/Contents/MacOS/MacDiskImager"
  lipo -create "$ROOT/.artifacts/x86_64/MacDiskImagerHelper" "$ROOT/.artifacts/arm64/MacDiskImagerHelper" -output "$APP/Contents/Resources/MacDiskImagerHelper"
else
  cp "$ROOT/.artifacts/$HOST_ARCH/MacDiskImager" "$APP/Contents/MacOS/MacDiskImager"
  cp "$ROOT/.artifacts/$HOST_ARCH/MacDiskImagerHelper" "$APP/Contents/Resources/MacDiskImagerHelper"
fi

cp "$ROOT/MyIcon.icns" "$APP/Contents/Resources/MyIcon.icns"
chmod +x "$APP/Contents/MacOS/MacDiskImager" "$APP/Contents/Resources/MacDiskImagerHelper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacDiskImager</string>
<key>CFBundleIdentifier</key><string>pl.madejak.MacDiskImager</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>MyIcon</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemovableVolumesUsageDescription</key><string>Dostęp do obrazów oraz zewnętrznych nośników USB, SD i eMMC.</string>
</dict></plist>
PLIST

IDENTITY="${DEVELOPER_ID_APP:-}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/MacDiskImagerHelper"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP/Contents/Resources/MacDiskImagerHelper"
  codesign --force --deep --sign - "$APP"
  echo "UWAGA: podpis ad-hoc. Do publicznej dystrybucji ustaw DEVELOPER_ID_APP."
fi

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Gotowe: $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  "$ROOT/create_dmg.sh"
fi
