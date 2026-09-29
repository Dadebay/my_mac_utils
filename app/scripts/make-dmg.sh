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

  # `Contents/MacOS` içindeki yardımcı çalıştırılabilirler: ağ ajanı ve
  # gömülü `adb`. Her biri kendi imzasını almadan uygulama imzalanamıyor
  # ("code object is not signed at all") ve noterleme de reddediyor.
  # Uygulamanın kendi çalıştırılabiliri hariç — o en sonda, paketin
  # tamamıyla birlikte imzalanıyor.
  while IFS= read -r -d '' item; do
    name="$(basename "$item")"
    [ "$name" = "$SCHEME" ] && continue

    case "$name" in
      GlassDoNetworkAgent*)
        codesign --force --options runtime --timestamp \
          --entitlements "Config/GlassDoNetworkAgent.entitlements" --sign "$DEV_ID" "$item"
        ;;
      *)
        codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item"
        ;;
    esac
  done < <(find "$APP_PATH/Contents/MacOS" -type f -perm +111 -print0 2>/dev/null)

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

# Arka plan görseli ve simge yerleşimi, pencere açılır açılmaz "neyi
# nereye sürükleyeceğim" sorusunu cevaplasın diye. Görünüm ayarları
# yalnızca yazılabilir bir imajda yapılabiliyor: önce UDRW üretiliyor,
# Finder'da düzenleniyor, sonra sıkıştırılmış UDZO'ya çevriliyor.
VOLNAME="$APP_NAME $VERSION"
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"
MOUNT_POINT="/Volumes/$VOLNAME"
BACKGROUND="Resources/dmg/background.tiff"

rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
  -ov -format UDRW "$RW_DMG" >/dev/null
rm -rf "$STAGING"

osascript -e "tell application \"Finder\" to close (every window whose name is \"$VOLNAME\")" >/dev/null 2>&1 || true
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
sleep 1
hdiutil attach "$RW_DMG" -nobrowse -quiet
sleep 1

if [ -f "$BACKGROUND" ]; then
  mkdir -p "$MOUNT_POINT/.background"
  cp "$BACKGROUND" "$MOUNT_POINT/.background/background.tiff"
fi

# Finder'ı sürmek otomasyon izni istiyor; verilmezse pencere düzensiz
# kalır ama DMG yine de çalışır — bu yüzden hata betiği durdurmuyor.
osascript <<OSA >/dev/null 2>&1 || echo "==> UYARI: Finder düzeni ayarlanamadı (otomasyon izni?)"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {240, 140, 880, 540}
    delay 1
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set label position of opts to bottom
    try
      set background picture of opts to file ".background:background.tiff"
    end try
    set position of item "$APP_NAME.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 3
  end tell
end tell
OSA

# Pencere AppleScript'in İÇİNDE kapatılmıyor: o sırada kapatınca Finder
# görünüm ayarlarını `.DS_Store`a yazmadan çıkıyor ve imaj eski
# pencere boyutuyla açılıyordu. Dışarıdan kapatıp yazmasını bekliyoruz.
osascript -e "tell application \"Finder\" to close (every window whose name is \"$VOLNAME\")" >/dev/null 2>&1 || true
sleep 2
sync
hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force -quiet

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG"

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
