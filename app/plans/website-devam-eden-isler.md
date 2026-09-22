# Website — Kalan İşler (devam için handoff)

Bu dosya, `plans/website-dagitim-firebase-plani.md` planı üzerinde çalışırken
token limiti nedeniyle yarım kalan işi bir sonraki konuşmaya taşımak için
yazıldı. Yeni bir chat'te bu dosyayı oku, kaldığı yerden devam et.

**GÜNCELLEME:** Kullanıcı ekran görüntülerini kendisi alacak — Claude'un
computer-use ile kullanıcının ekranına dokunması istenmiyor. Kod tarafı
tamamen hazır: `MockupPlaceholder` zaten `src` prop'unu destekliyordu,
`Hero.tsx` ve `[locale]/page.tsx` altı görselin beşine (`hero`, `edge-rail`,
`tasks-notes`, `system-monitoring`, `widgets-menu-bar`) beklenen dosya
yollarını artık veriyor — `privacySync` kasıtlı olarak placeholder kalıyor
(gerçek bir UI karşılığı yok, plandaki 6. madde). `npm run build` temiz
geçti. **Kullanıcı altıdaki dosya adlarıyla PNG'leri
`website/public/screenshots/` altına bırakınca site otomatik gerçek
görselleri gösterecek — ayrıca kod değişikliği gerekmiyor:**

- `hero.png`
- `edge-rail.png`
- `tasks-notes.png`
- `system-monitoring.png`
- `widgets-menu-bar.png`

Aşağıdaki "Alınacak 6 ekran görüntüsü" bölümü hangi ekranın hangi dosyaya
karşılık geldiğini anlatıyor — artık Claude'un değil, kullanıcının kendisinin
izleyeceği bir kılavuz olarak kalsın. Görseller yerine konduktan sonra kalan
tek adım `cd website && npm run build` + repo kökünden
`firebase deploy --only hosting`.

## Şu ana kadar tamamlanan

- `website/` içinde Next.js 16 (App Router, TS, Tailwind v4, Framer Motion,
  Lucide) landing page kuruldu, Firebase Hosting'e deploy edildi:
  **https://mac-utils.web.app**
- TR/EN/RU i18n: `app/[locale]/...` (Next 16 `next/root-params` ile
  `<html lang>` dinamik). Varsayılan dil **EN** (`firebase.json` →
  `hosting.redirects`, `/` → `/en`). Metinler `website/lib/content/{tr,en,ru}.ts`.
- Font: **Gilroy** (`website/public/fonts/gilroy/*.ttf`, `@font-face` in
  `website/app/globals.css`) — kaynak: kullanıcının kendi
  `car_care/toyota_app/assets/fonts` projesinden kopyalandı.
- Apple Design polish: press feedback (`active:scale-95`), FAQ artık spring
  ile açılıp kapanıyor (`bounce:0`), scroll-reveal spring'e çevrildi,
  `prefers-reduced-transparency` desteği eklendi, download panel için
  `.glass-panel-lg` (daha güçlü blur/gölge).
- Hero'daki "Yalnızca macOS 26+ için" eyebrow rozeti kaldırıldı.
- Footer'a geliştirici linki eklendi: `https://github.com/Dadebay`.

## ŞİMDİ YAPILMASI GEREKEN: gerçek ekran görüntüleri

Kullanıcı, Gemini ile üretilen sahte/soyut görsellerin GERÇEK uygulamaya hiç
benzemediğini fark etti (referans: usage.pro — onlar da tamamen gerçek
screenshot kullanıyor, AI üretimi değil). Karar: **AI görsel üretimi yok,
gerçek ekran görüntüsü + kod içinde temiz bir çerçeve/mockup bileşeni.**

Kullanıcı "sen uygulamayı derleyip çalıştır, ekran görüntüsü al" seçeneğini
seçti — yani ekran görüntülerini ben (Claude, computer-use ile) alacağım.

### Uygulama zaten derlendi ve açık

```bash
cd "/Users/dadebay/Developer/apps/projects/macos todo app"
xcodegen generate
xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
  -configuration Debug -derivedDataPath /tmp/glassdo-build \
  CODE_SIGNING_ALLOWED=NO build
open /tmp/glassdo-build/Build/Products/Debug/GlassDo-macOS.app
```

Yeni chat'te tekrar `mcp__computer-use__request_access` ile
`["GlassDo-macOS"]` için izin istemek gerekecek (izinler sohbetler arası
taşınmıyor). Uygulama muhtemelen hâlâ açık olacak (yeniden derlemeye gerek
olmayabilir, önce `open_application` ile kontrol et).

**Not:** İmzasız/CODE_SIGNING_ALLOWED=NO build olduğu için App Group'a bağlı
widget senkronizasyonu çalışmayabilir (README'de de belirtilmiş) — widget
ekran görüntüsü gerekiyorsa bu sınırlamayı göz önünde bulundur.

### Alınacak 6 ekran görüntüsü ve nereye gidecekleri

Şu an hepsi `website/components/MockupPlaceholder.tsx` ile geçici cam-panel
placeholder olarak gösteriliyor. Her biri gerçek screenshot ile
değiştirilecek:

1. **Hero (ana görsel)** — `website/components/Hero.tsx` — Task List +
   Edge Rail (sağdaki dikey ikon şeridi) + sistem metrikleri bir arada
   görünecek bir kompozisyon. Ana pencere + Edge Rail aynı ekranda açıkken
   alınabilir (yukarıdaki screenshot'ta ikisi de görünüyor).
2. **Edge Rail** — `website/app/[locale]/page.tsx` içindeki `edgeRail`
   `FeatureSection` — sağ kenardaki dikey rail'in kendisi, tercihen
   genişletilmiş/expanded haliyle.
3. **Tasks & Notes** — `tasksNotes` `FeatureSection` — Task List görünümü
   (yukarıda zaten yakalandı, sidebar'da "Tasks" seçiliyken).
4. **System Monitoring** — `systemMonitoring` `FeatureSection` — sidebar'da
   "Overview" veya "Processor Load" / "Memory Usage" görünümü.
5. **Widgets & Menu Bar** — `widgetsMenuBar` `FeatureSection` — menü
   çubuğundaki ölçerler (ekranın üstünde zaten görünüyor) + varsa bir
   widget galerisi görünümü (Ayarlar > Widgets).
6. **Privacy & Sync** — bunun gerçek bir UI karşılığı yok (henüz sync
   özelliği yok), bu yüzden bu tek görsel için placeholder kalabilir ya da
   basit bir ikon/illüstrasyon (kod içinde CSS ile, AI üretimi gerekmeden)
   düşünülebilir.

### İş akışı

1. Her görünüm için `computer_batch` ile pencereyi doğru duruma getir
   (sidebar'da doğru öğeye tıkla), `screenshot` al.
2. Screenshot'ı kırp (yalnızca uygulama penceresi + gerekiyorsa Edge Rail —
   masaüstü duvar kağıdı/menü çubuğunun geri kalanı olmadan, ya da bilinçli
   olarak açık bırakılabilir, usage.pro gibi düz koyu arka plan tercih
   edilebilir).
3. Kırpılmış PNG'leri `website/public/screenshots/` altına kaydet (klasör
   henüz yok, oluşturulacak).
4. `website/components/MockupPlaceholder.tsx` kullanan her yeri gerçek
   `<img src="/screenshots/xxx.png" alt="..." />` ile değiştir — ya
   `MockupPlaceholder`'ı image-aware hale getir (bir `src` prop'u ekle,
   verilmişse gerçek img, verilmemişse mevcut placeholder'ı göster) ya da
   `Hero.tsx` / `FeatureSection.tsx` çağrılarını doğrudan güncelle.
5. `cd website && npm run build`, sonra repo kökünden
   `firebase deploy --only hosting`.

### Diğer notlar

- `.claude/launch.json` içinde `website` adında bir dev server config'i var
  (`mcp__Claude_Browser__preview_start` ile kullanılabilir).
- Browser pane bu sohbette zaman zaman "hidden" durumda kalıp
  screenshot'ları boş/siyah döndürdü — `get_page_text` /
  `javascript_tool` ile içerik doğrulaması daha güvenilir oldu, sorun
  sitenin kendisinde değildi.
- Firebase proje: `mac-utils`, CLI zaten login olmuş durumda
  (`dadebayapple@gmail.com`).
