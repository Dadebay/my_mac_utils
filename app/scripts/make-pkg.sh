#!/bin/bash
#
# GlassDo'yu Release olarak derler ve çift tıklanabilir bir .pkg kurulum
# sihirbazı üretir. DMG'den farkı: müşteri hiçbir şey sürüklemiyor,
# kurulum bitince uygulama kendiliğinden açılıyor (bkz. pkg-scripts/postinstall).
#
# İmzalama: uygulama "Developer ID Application", paketin kendisi ise
# "Developer ID Installer" sertifikası istiyor — ikisi ayrı sertifika.
# İkincisi yoksa paket imzasız üretilir ve uyarı verilir; imzasız paket
# noterlenemez ve müşterinin makinesinde açılmaz.
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="GlassDo-macOS"
APP_NAME="GlassDo"
BUNDLE_ID="com.dadebay.GlassDo-macOS"
BUILD_DIR="build-release"
APP_PATH="$BUILD_DIR/Build/Products/Release/$SCHEME.app"

echo "==> Release derlemesi"
xcodebuild -project GlassDo.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  build >/dev/null

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")}"
PKG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.pkg"

# Uygulamanın imzası: DMG betiğiyle aynı kurallar (içten dışa, hardened
# runtime, güvenli zaman damgası).
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

if [ -n "$DEV_ID" ]; then
  echo "==> Uygulama imzalanıyor: $DEV_ID"

  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 \
    \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null)

  while IFS= read -r -d '' item; do
    entitlements=""
    case "$(basename "$item")" in
      GlassDoWidgets.appex) entitlements="Config/GlassDoWidgets.entitlements" ;;
    esac
    if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
      codesign --force --options runtime --timestamp \
        --entitlements "$entitlements" --sign "$DEV_ID" "$item"
    else
      codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item"
    fi
  done < <(find "$APP_PATH/Contents" \( -name "*.appex" -o -name "*.xpc" \) -print0 2>/dev/null)

  while IFS= read -r -d '' item; do
    name="$(basename "$item")"
    [ "$name" = "$SCHEME" ] && continue
    case "$name" in
      GlassDoNetworkAgent*)
        codesign --force --options runtime --timestamp \
          --entitlements "Config/GlassDoNetworkAgent.entitlements" --sign "$DEV_ID" "$item" ;;
      *)
        codesign --force --options runtime --timestamp --sign "$DEV_ID" "$item" ;;
    esac
  done < <(find "$APP_PATH/Contents/MacOS" -type f -perm +111 -print0 2>/dev/null)

  codesign --force --options runtime --timestamp \
    --entitlements "Config/GlassDo.entitlements" --sign "$DEV_ID" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
  echo "==> İmza doğrulandı"
else
  echo "==> UYARI: Developer ID Application sertifikası yok, uygulama imzasız."
fi

echo "==> Paket hazırlanıyor"
STAGING="$BUILD_DIR/pkg-root"
rm -rf "$STAGING" "$BUILD_DIR/component.pkg" "$PKG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/$APP_NAME.app"

pkgbuild --root "$STAGING" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location "/Applications" \
  --scripts scripts/pkg-scripts \
  "$BUILD_DIR/component.pkg" >/dev/null

# Sihirbazın metinleri ve başlığı. `--synthesize` yerine elle yazılıyor:
# karşılama ve kapanış sayfaları ancak burada bağlanabiliyor.
cat > "$BUILD_DIR/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$APP_NAME $VERSION</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <!-- Uygulama macOS 14 ve üstünü hedefliyor; eski sürümlerde kurulum
         yarıda başarısız olmaktansa baştan engelleniyor. -->
    <volume-check>
        <allowed-os-versions><os-version min="26.0"/></allowed-os-versions>
    </volume-check>
    <pkg-ref id="$BUNDLE_ID"/>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="$APP_NAME"><pkg-ref id="$BUNDLE_ID"/></choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

INSTALLER_ID=$(security find-identity -v 2>/dev/null \
  | grep "Developer ID Installer" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

if [ -n "$INSTALLER_ID" ]; then
  productbuild --distribution "$BUILD_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" --resources Resources/pkg \
    --sign "$INSTALLER_ID" "$PKG_PATH" >/dev/null
  echo "==> Paket imzalandı: $INSTALLER_ID"
else
  productbuild --distribution "$BUILD_DIR/distribution.xml" \
    --package-path "$BUILD_DIR" --resources Resources/pkg "$PKG_PATH" >/dev/null
  echo "==> UYARI: 'Developer ID Installer' sertifikası yok, paket imzasız."
  echo "    Xcode > Settings > Accounts > Manage Certificates > + ile oluşturun."
fi

rm -rf "$STAGING" "$BUILD_DIR/component.pkg" "$BUILD_DIR/distribution.xml"

if [ -n "$INSTALLER_ID" ] && xcrun notarytool history --keychain-profile "notary" >/dev/null 2>&1; then
  echo "==> Noterleme (birkaç dakika sürebilir)"
  xcrun notarytool submit "$PKG_PATH" --keychain-profile "notary" --wait
  xcrun stapler staple "$PKG_PATH"
  echo "==> Damgalandı"
else
  echo "==> UYARI: paket noterlenmedi."
fi

echo
echo "Hazır: $PKG_PATH"
echo "Boyut: $(du -h "$PKG_PATH" | cut -f1)"
