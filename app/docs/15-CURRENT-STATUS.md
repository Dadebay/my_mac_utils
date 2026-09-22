# 15 — Güncel Durum: Website, Admin Panel, macOS Uygulaması

> Güncellik: 2026-09-19
>
> Bu belge 00-14 gibi bir *inşa şartnamesi* değil, **şu an repoda gerçekten
> var olanın** anlık görüntüsü. Amaç: her uygulamayı ayrı bir GitHub
> deposuna taşımadan önce hangi parçanın nerede, ne durumda olduğunu tek
> yerden görebilmek.

## Özet tablo

| Uygulama | Klasör | Teknoloji | Durum |
|---|---|---|---|
| macOS app | `Sources/`, `GlassDo.xcodeproj`, `Config/`, `project.yml`, `Tests/` | Swift 6, SwiftUI, SwiftData, XcodeGen | Aktif geliştirme, tek kullanıcı |
| Website (herkese açık) | `website/app/[locale]/`, `website/components/` (admin hariç) | Next.js 16 (App Router), TypeScript, Tailwind v4, Framer Motion | Yayında |
| Admin panel | `website/app/admin/`, `website/components/admin/`, `website/lib/admin*.ts(x)` | Aynı Next.js projesi içinde ayrı bir kök layout (Next'in "multiple root layouts" özelliği) | Yayında, tek parolalı |
| Admin/monetizasyon backend | `functions/` | Firebase Cloud Functions (Node 20, TypeScript, Express) | Yayında |

**Önemli:** Website ve admin panel şu an **aynı Next.js projesi** (`website/`)
içinde iki ayrı kök layout olarak yaşıyor — aynı `package.json`, aynı
`node_modules`, aynı `next build` çıktısı (`website/out`). Fiziksel olarak
ayrı klasörlere/depolara bölünmemiş. Aşağıda "Ayırma notu" başlığı altında
bunun neden şu an yapılmadığı ve nasıl yapılabileceği var.

---

## 1. macOS Uygulaması (GlassDo)

- **Konum:** repo kökü — `Sources/`, `GlassDo.xcodeproj` (XcodeGen ile
  `project.yml`'den üretiliyor, repoya dahil değil), `Config/`, `Tests/`.
- **Ne yapıyor:** Görev yöneticisi + Edge Rail kenar paneli + sistem izleme
  (CPU/RAM/disk/batarya/ağ) + menü çubuğu ölçerleri + WidgetKit widget'ları.
  Detaylı özellik listesi için [04-FEATURES.md](04-FEATURES.md),
  [12-EDGE-RAIL.md](12-EDGE-RAIL.md), [13-WIDGETS-MENUBAR.md](13-WIDGETS-MENUBAR.md).
- **Veri:** SwiftData, tamamen yerel. Firebase şu an yalnızca **anonim,
  opt-in kullanım analitiği** için var (`Sources/macOS/Analytics/DeviceAnalyticsService.swift`)
  — görev/not senkronizasyonu henüz yok.
- **RevenueCat:** `project.yml`'e eklendi (Swift Package). Uygulama içi
  satın alma/abonelik akışının UI tarafı bu dokümanın yazıldığı an itibarıyla
  repoda ayrı bir dosya olarak görünmüyor — muhtemelen devam eden bir iş.
  Plan için [14-SHIPPING-MONETIZATION-REVENUECAT.md](14-SHIPPING-MONETIZATION-REVENUECAT.md).
- **Dağıtım:** App Store dışı, doğrudan DMG/zip indirme. `.github/workflows/release.yml`
  her `main` push'unda imzasız bir build üretip GitHub Releases'e ekliyor.
  Developer ID imzalama/notarization henüz kurulmadı.

## 2. Website (herkese açık pazarlama sitesi)

- **Konum:** `website/app/[locale]/` (ana sayfa, `/destek`, `/gizlilik-politikasi`),
  paylaşılan bileşenler `website/components/` altında (admin'e özel olanlar hariç).
- **Diller:** TR / EN / RU — `website/lib/content/{tr,en,ru}.ts`. Varsayılan
  dil **EN**; `/` isteği Firebase Hosting'de `/en`'e yönleniyor
  (`firebase.json` → `hosting.redirects`).
- **Font:** Gilroy (`website/public/fonts/gilroy/`, `@font-face`).
- **İndirme sistemi:** Sürüm/boyut/mimari `NEXT_PUBLIC_*` ortam
  değişkenlerinden; DMG imzalanmadan "notarize edildi" rozeti
  `NEXT_PUBLIC_IS_NOTARIZED=true` olmadan hiç gösterilmiyor.
- **Barındırma:** Statik export (`output: "export"`) → `website/out` →
  Firebase Hosting. Canlı: **https://mac-utils.web.app**
- **Eksik/yapılacak:** Gerçek ürün ekran görüntüleri henüz placeholder
  (`MockupPlaceholder`); gerçek `NEXT_PUBLIC_DOWNLOAD_URL` ve Firebase Analytics
  anahtarları `.env.local` içinde doldurulmadı (bkz. `website/.env.local.example`).

## 3. Admin Panel

- **Konum (frontend):** `website/app/admin/` — `page.tsx` (giriş), `overview/`,
  `customers/` (+ `customers/detail`), `promocodes/`. Kendi kök layout'u
  (`admin/layout.tsx`) var; `[locale]` altındaki pazarlama sayfalarıyla hiçbir
  üst layout paylaşmıyor (Next.js "multiple root layouts").
- **Oturum:** Firebase Auth / Google girişi **yok**. Tek bir admin parolası,
  backend'de argon2id ile hash'lenmiş şekilde doğrulanıyor
  (`functions/src/admin/session.ts`), başarılı girişte `HttpOnly` bir session
  çerezi veriliyor. Statik frontend herkese açık indirilebilir — gerçek
  koruma tamamen backend'de.
- **Konum (backend):** `functions/src/admin/` — `app.ts` (Express router
  kurulumu), `session.ts`, `middleware.ts` (CORS + same-origin + CSRF),
  `dashboard.ts`, `promoCodes.ts`. Tek bir HTTP Cloud Function olarak
  (`adminApi`) dışa açılıyor, Firebase Hosting'te `/admin-api/**` rewrite'ı
  ile `website/` domaininin altından servis ediliyor (`firebase.json`).
- **Uçlar (route'lar):**
  - `POST /admin-api/session` — giriş
  - `GET /admin-api/session` — oturumu devam ettir
  - `GET /admin-api/dashboard` — özet metrikler
  - `GET /admin-api/customers`, `GET /admin-api/customers/:uid` — müşteri
    listesi/detayı
  - `GET /admin-api/promocodes`, `POST /admin-api/promocodes`,
    `POST /admin-api/promocodes/:id/disable` — promosyon kodu yönetimi
- **RevenueCat entegrasyonu:** `functions/src/webhooks/revenueCat.ts`
  (imza doğrulamalı webhook), `functions/src/callable/redeemPromoCode.ts`
  (uygulamadan çağrılabilir promosyon kodu kullanma fonksiyonu).
- **Sırlar:** `adminPanelPasswordHash`, `adminSessionSigningKey`,
  `promoCodePepper`, `revenueCatSecretApiKey`, `revenueCatProjectId`,
  `revenueCatWebhookSigningSecret`, `adminAllowedOrigin` — Firebase
  Functions `params`/secrets olarak tanımlı (`functions/src/lib/env.ts`),
  gerçek değerleri repoya girmiyor.

---

## Ayırma notu: neden şu an fiziksel olarak bölünmedi

Website ve admin panel aynı Next.js projesini paylaşıyor çünkü admin,
Next'in "aynı `app/` dizininde birden çok kök layout" özelliğiyle kuruldu —
ayrı bir proje açmak yerine mevcut projenin içine, kendi `<html>`'i olan bağımsız
bir dal olarak eklendi. Bunu üç ayrı GitHub deposuna hazır, tamamen bağımsız
klasörlere ayırmak istersen (`macos-app/`, `website/`, `admin-panel/`), şunlar
gerekiyor:

1. **Admin için yeni bir Next.js projesi** — kendi `package.json`, kendi
   `node_modules`, kendi Tailwind/font kurulumu (şu an website ile paylaşılıyor).
   `website/app/admin/`, `website/components/admin/`, `website/lib/adminSession.tsx`,
   `website/lib/adminApi.ts` oraya taşınır.
2. **Firebase Hosting'te iki ayrı site** (Firebase'in "multiple sites"
   özelliği) — her birinin kendi statik export çıktısını ayrı ayrı
   servis etmesi için; şu an tek `hosting.public: website/out` var.
3. **`functions/`'ı taşımak/paylaşmak üzerine bir karar** — mantıken admin
   panelin backend'i, website'in değil; muhtemelen `admin-panel/functions/`
   ya da bağımsız kalabilir.
4. **CI/deploy scriptlerini güncellemek** (`firebase.json`, `.firebaserc`,
   `.claude/launch.json`, `.github/workflows/*`).

Bu, dosya taşımaktan daha büyük bir iş — bu yüzden şu anki oturumda
uygulanmadı, önce onaylanması istendi.
