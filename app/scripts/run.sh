#!/bin/bash
#
# GlassDo'yu Xcode açmadan derler ve çalıştırır.
#
# Kullanımı:
#   scripts/run.sh            derle ve çalıştır
#   scripts/run.sh --log      derle, çalıştır ve çıktıyı terminale bas
#   scripts/run.sh --build    yalnızca derle, çalıştırma
#
# Gereken tek şey Xcode komut satırı araçları ve xcodegen:
#   brew install xcodegen
#
# İlk çalıştırma uzun sürüyor: Firebase ve RevenueCat paketleri indiriliyor.
# Sonraki çalıştırmalar hem paketleri hem derleme çıktısını yeniden
# kullanıyor.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="GlassDo-macOS"
BUILD_DIR="build-debug"
PROJECT="GlassDo.xcodeproj"
APP_PATH="$BUILD_DIR/Build/Products/Debug/$SCHEME.app"

MODE="run"
case "${1:-}" in
  --log) MODE="log" ;;
  --build) MODE="build" ;;
  "") ;;
  *) echo "Bilinmeyen seçenek: $1"; exit 2 ;;
esac

# Proje dosyası `project.yml`'den üretiliyor ve depoya konmuyor. Yeni bir
# kaynak dosyası eklendiğinde yeniden üretilmezse derleme onu görmez —
# o yüzden `project.yml` projeden yeniyse kendiliğinden yenileniyor.
if [ ! -d "$PROJECT" ] || [ project.yml -nt "$PROJECT" ]; then
  command -v xcodegen >/dev/null || {
    echo "xcodegen yok. Kurmak için: brew install xcodegen"; exit 1;
  }
  echo "==> Proje üretiliyor"
  xcodegen generate
fi

# Paketler (Firebase, RevenueCat) buraya bir kez klonlanıyor ve bütün
# derlemeler onu paylaşıyor. Derleme klasörünün içine klonlansalardı
# `build-debug` her silindiğinde yüzlerce megabayt yeniden inerdi —
# firebase-ios-sdk küçük bir depo değil.
PACKAGES_DIR="$HOME/Library/Caches/GlassDo/SourcePackages"
mkdir -p "$PACKAGES_DIR"

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Debug
  -derivedDataPath "$BUILD_DIR"
  -clonedSourcePackagesDirPath "$PACKAGES_DIR"
)

# Paket çözümü ayrı bir adım: derlemenin içinde yapılınca ilk çalıştırmada
# dakikalarca hiçbir çıktı vermeden bekliyor ve donmuş gibi görünüyor.
# Burada kendi satırını yazıyor, ne beklendiği belli oluyor.
if [ ! -d "$PACKAGES_DIR/checkouts" ]; then
  echo "==> Paketler indiriliyor (ilk çalıştırma, birkaç dakika sürebilir)"
else
  echo "==> Paketler denetleniyor"
fi
xcodebuild "${COMMON_ARGS[@]}" -resolvePackageDependencies

echo "==> Derleniyor (Debug)"
# Çıktı bastırılmıyor: sessiz bir derlemede ilerleme olup olmadığı
# anlaşılmıyor. `xcbeautify`/`xcpretty` varsa okunur hâle getiriyor
# (brew install xcbeautify), yoksa ham çıktı akıyor.
if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "${COMMON_ARGS[@]}" build | xcbeautify
elif command -v xcpretty >/dev/null 2>&1; then
  xcodebuild "${COMMON_ARGS[@]}" build | xcpretty
else
  xcodebuild "${COMMON_ARGS[@]}" build
fi

[ -d "$APP_PATH" ] || { echo "Uygulama bulunamadı: $APP_PATH"; exit 1; }

if [ "$MODE" = "build" ]; then
  echo "Hazır: $APP_PATH"
  exit 0
fi

# ⌘Q ve Dock'taki "Çık" uygulamayı kapatmıyor, arka plana alıyor (bkz.
# `AppQuit`) — menü çubuğu ölçerleri ve kenar paneli yaşamaya devam etsin
# diye. Yani çalışan eski kopya kendiliğinden gitmiyor; yeni derlemeyi
# çalıştırmadan önce elle sonlandırılması gerekiyor, yoksa ekranda hâlâ
# eski sürüm duruyor.
if pgrep -x "$SCHEME" >/dev/null; then
  echo "==> Çalışan kopya kapatılıyor"
  killall "$SCHEME" 2>/dev/null || true
  # Kenar paneli ve menü çubuğu öğelerinin kaybolması bir an sürüyor.
  for _ in $(seq 20); do
    pgrep -x "$SCHEME" >/dev/null || break
    sleep 0.1
  done
fi

if [ "$MODE" = "log" ]; then
  echo "==> Çalışıyor (çıkmak için Ctrl-C)"
  # Doğrudan çalıştırınca `print` ve `NSLog` çıktısı terminalde kalıyor;
  # `open` ile başlatılan uygulamanınki Console.app'e gidiyor.
  exec "$APP_PATH/Contents/MacOS/$SCHEME"
fi

echo "==> Açılıyor"
open "$APP_PATH"
