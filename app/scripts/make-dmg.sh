#!/bin/bash
#
# GlassDo'yu Release olarak derler ve dağıtılabilir bir .dmg üretir.
#
# Kullanımı:
#   scripts/make-dmg.sh [sürüm]
#
# Sürüm verilmezse Info.plist'teki CFBundleShortVersionString kullanılır.
#
# İmzalama: makinede "Developer ID Application" sertifikası varsa uygulama
# onunla imzalanır; ayrıca `notary` adlı bir notarytool profili varsa DMG
# noterleme için Apple'a gönderilip damgalanır. İkisi de yoksa betik
# çalışmaya devam eder ama üretilen DMG **imzasızdır**: başka Mac'lerde
# Gatekeeper uyarı verir (aşağıdaki nota bakın).

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="GlassDo-macOS"
BUILD_DIR="build-release"
APP_NAME="GlassDo"
STAGING="$BUILD_DIR/dmg-staging"

echo "==> Release derlemesi"
xcodebuild -project GlassDo.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build | tail -3

APP_PATH="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
[ -d "$APP_PATH" ] || { echo "Uygulama bulunamadı: $APP_PATH"; exit 1; }

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")}"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Dağıtım imzası: varsa Developer ID, yoksa derlemeden gelen imza korunur.
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

if [ -n "$DEV_ID" ]; then
  echo "==> Developer ID ile imzalanıyor: $DEV_ID"

  # İçten dışa imzalama. `--deep` Apple tarafından önerilmiyor: iç
  # bileşenlerin kendi yetkilendirmelerini (entitlements) ezip noterlemede
  # reddedilmeye yol açıyor. Bu yüzden önce çerçeveler ve gömülü
  # çalıştırılabilirler, en son uygulamanın kendisi imzalanıyor.
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 \
    \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null)

  while IFS= read -r -d '' item; do
    entitlements=""
    case "$(basename "$item")" in
      GlassDoWidgets.appex) entitlements="Config/GlassDoWidgets.entitlements" ;;
      GlassDoNetworkAgent*) entitlements="Config/GlassDoNetworkAgent.entitlements" ;;
    esac

    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
      codesign --force --options runtime --timestamp \
        --entitlements "$entitlements" --sign "$DEV_ID" "$item"
    else
      codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item"
    fi
  done < <(find "$APP_PATH/Contents" \( -name "*.appex" -o -name "*.xpc" \) -print0 2>/dev/null)

  # Ağ ajanı uygulamanın içinde ayrı bir çalıştırılabilir olarak duruyor.
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp \
      --entitlements "Config/GlassDoNetworkAgent.entitlements" --sign "$DEV_ID" "$item"
  done < <(find "$APP_PATH/Contents/Library" -type f -perm +111 -print0 2>/dev/null)

  codesign --force --options runtime --timestamp \
    --entitlements "Config/GlassDo.entitlements" --sign "$DEV_ID" "$APP_PATH"

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  echo "==> İmza doğrulandı"
else
  echo "==> UYARI: Developer ID sertifikası yok, uygulama dağıtım için imzalanmadı."
fi

echo "==> DMG hazırlanıyor"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/$APP_NAME.app"
# Kullanıcı sürükleyip bıraksın diye Uygulamalar kısayolu.
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

if [ -n "$DEV_ID" ]; then
  codesign --force --sign "$DEV_ID" "$DMG_PATH"

  if xcrun notarytool history --keychain-profile "notary" >/dev/null 2>&1; then
    echo "==> Noterleme (birkaç dakika sürebilir)"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "notary" --wait
    xcrun stapler staple "$DMG_PATH"
    echo "==> Damgalandı"
  else
    echo "==> UYARI: 'notary' profili yok, DMG noterlenmedi."
  fi
fi

echo
echo "Hazır: $DMG_PATH"
du -h "$DMG_PATH" | cut -f1 | sed 's/^/Boyut: /'
