#!/bin/bash
set -euo pipefail
APP_NAME="Mac Disk Imager"
VERSION="1.0.0"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
STAGE="$ROOT/dist/dmg"
RW="$ROOT/dist/Mac_Disk_Imager_${VERSION}_rw.dmg"
FINAL="$ROOT/dist/Mac_Disk_Imager_${VERSION}.dmg"

[[ -d "$APP" ]] || { echo "Brak aplikacji. Uruchom ./build_app.sh"; exit 1; }
rm -rf "$STAGE"; rm -f "$RW" "$FINAL"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL" >/dev/null
rm -f "$RW"; rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$FINAL"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$FINAL"
  xcrun stapler validate "$FINAL"
fi

echo "Gotowe DMG: $FINAL"
