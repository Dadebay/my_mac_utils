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

# macOS'un /bin/bash'i 3.2 (2007). Betik ona uyumlu kalmalı: Linux'taki
# bash 5'te geçen bir yapı (ör. `$( … )` içinde `case`) orada sözdizimi
# hatası verebiliyor. Değişiklikten sonra 3.2 ile `bash -n` denetlenmeli.

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

# Aynı paket kimliğine sahip başka bir kopya (ör. kurulum paketinin
# /Applications'a koyduğu GlassDo.app) varsa macOS ikisini tek uygulama
# sayıyor ve karıştırıyor:
#  - İzinler imzaya bağlı. Kurulan kopya "Developer ID", bu derleme
#    "Apple Development" ile imzalı; birine verilen izin ötekinde yok.
#  - Ekran Kaydı izni sonrası "Çık ve Yeniden Aç", Dock, bildirimler ve
#    oturum açılışı uygulamayı dosya yolundan değil kimlikten buluyor ve
#    çoğu zaman /Applications'takini açıyor. Kullanıcı bu derlemeye izin
#    verip "yeniden aç" diyor, karşısına izinsiz öteki kopya çıkıyor.
# Betik bunu çözemez ama sessiz de kalmamalı.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
if [ -n "$BUNDLE_ID" ]; then
  BUILT_REAL=$(cd "$APP_PATH" && pwd -P)
  OTHERS=$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null \
    | while IFS= read -r copy; do
        [ -d "$copy" ] || continue
        real=$(cd "$copy" && pwd -P)
        [ "$real" = "$BUILT_REAL" ] && continue
        # Derleme ara çıktıları (Xcode'un kendi DerivedData'sı, kurulum
        # paketinin Release derlemesi) her derlemede yeniden oluşuyor;
        # onları saymak uyarıyı anlamsız kılardı.
        #
        # `case` değil `if`: macOS'un /bin/bash'i 3.2 ve `$( … )` içindeki
        # bir `case` deseninin `)`'ini komut yerine koymanın kapanışı
        # sanıyor ("syntax error near unexpected token `;;'").
        # Çöp Kutusu'ndaki kopya da sayılmıyor: kullanıcı zaten uyarının
        # istediğini yapmış.
        if [[ "$real" == */DerivedData/* || "$real" == */build-release/* || "$real" == */.Trash/* ]]; then
          continue
        fi
        echo "$real"
      done)
  if [ -n "$OTHERS" ]; then
    echo
    echo "UYARI: Bu Mac'te GlassDo'nun başka bir kopyası daha var:"
    echo "$OTHERS" | sed 's/^/    /'
    echo "  macOS ikisini aynı uygulama sayıyor: izinler birine verilip"
    echo "  ötekisi açılıyor, \"Çık ve Yeniden Aç\" kurulu kopyayı başlatıyor."
    echo "  Geliştirirken o kopyayı Çöp Kutusu'na at, sonra izinleri sıfırla:"
    echo "    tccutil reset Accessibility $BUNDLE_ID"
    echo "    tccutil reset ScreenCapture $BUNDLE_ID"
  fi
fi

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
