# 010 — Promocode, Admin Panel ve RevenueCat Satış Görünürlüğü

> Amaç: GlassDo Pro için güvenli promocode kullanımı; Firebase Hosting üzerinde
> yayınlanan, yalnızca yöneticiye açık bir panel; Firestore'da minimum gerekli
> kayıt ve RevenueCat satın alma durumunun panelde görünmesi.
>
> Bu belge implementasyon için Claude Sonnet'e verilecek teknik görev tanımıdır.
> Uygulama Swift 6/macOS; site Next.js static export; backend Firebase Cloud
> Functions (2nd gen) + Firestore olacaktır. Firebase Auth yalnızca, Mac
> kullanıcısının promocode erişimini cihazlar arasında geri yüklemek istenirse
> kullanılan ayrı bir kullanıcı-kimliği seçeneğidir; admin panele ait değildir.

---

## İlerleme durumu (bu dosya artık tek kaynak — eski `010-progress-handoff.md` buraya taşındı)

### Önemli bağlam — devam ederken akılda tutulacaklar

- **Başka ajanlar da** ana dizinde eşzamanlı çalışıyor olabilir
  (`Sources/GlassDoKit`, `Sources/macOS` altında task/priority/recurrence
  özellikleri gibi) — bu yüzden `project.yml`, `GlassDoApp.swift`,
  `SettingsView.swift` gibi paylaşılan dosyalara **sadece küçük/hedefli
  edit** at, asla tam `Write` ile üzerine yazma. Devam ederken bu dosyaları
  önce tekrar `Read` et.
- Git worktree ile izolasyon **denendi ve işe yaramadı**: `firebase.json`,
  `firestore.rules`, `website/`, `Config/GoogleService-Info.plist` gibi
  temel dosyalar ana dizinde hâlâ **commit edilmemiş** (`git status`'ta
  `??`). Worktree yalnızca commit edilmiş durumu kopyaladığı için boş bir
  ortam veriyor. Çalışma **doğrudan ana dizinde** yapılıyor.
- Deploy **kasıtlı olarak hiç yapılmadı**: gerçek `mac-utils` Firebase
  projesine (bkz. `.firebaserc`) Functions/Rules deploy etmek, Blaze plan
  onayı ve gerçek RevenueCat/admin secret değerleri olmadan güvenli değil —
  bu, kullanıcının açıkça onaylayacağı ayrı bir adım. `firebase deploy
  --dry-run` bile "hedef projede API etkinleştirebilir" uyarısı taşıdığı
  için çalıştırılmadı. Bu ortamda ayrıca Firestore emulator'ü için gereken
  Java 21 kurulu değil, dolayısıyla `firestore.rules` yalnızca elle/görsel
  doğrulandı (parantez/süslü parantez dengesi script ile kontrol edildi) —
  gerçek bir `firebase emulators:start --only firestore` ya da Console
  rules simulator ile ayrıca doğrulanmalı.

### Tamamlanan — `functions/` (backend bitti, derleme ve lint temiz)

```text
firestore.rules                          — promoCodes/redemptions/customerSummaries/
                                            revenueCatEvents/adminAuditLogs/rateLimits
                                            için deny-all
firebase.json                            — functions config + /admin-api/** hosting rewrite
functions/.env.example                   — ADMIN_ALLOWED_ORIGIN örneği (gizli değil)
functions/.gitignore                     — node_modules, lib, .env* (örnek hariç)
functions/.eslintrc.cjs                  — package.json'daki lint script'i çalışır hâle getirildi
functions/package.json                   — deps: @node-rs/argon2, cookie-parser, cors, express,
                                            firebase-admin, firebase-functions, TS/eslint devDeps
functions/tsconfig.json                  — NodeNext, ES2022, strict
functions/src/lib/env.ts                 — defineSecret x6 + REGION + adminAllowedOrigin (defineString)
functions/src/lib/firebaseAdmin.ts       — tekil initializeApp() + db export
functions/src/lib/crypto.ts              — hmacSha256Hex, constantTimeEqual, randomToken, base64Url(De)codeJSON
functions/src/lib/adminSession.ts        — imzalı stateless session token (payload+HMAC), csrf claim içeride
functions/src/lib/rateLimit.ts           — Firestore transaction tabanlı sabit-pencere rate limit
functions/src/lib/auditLog.ts            — adminAuditLogs'a sabit actor:"owner" ile yazma
functions/src/lib/promoCode.ts           — generatePromoCode, normalizePromoCode, hashPromoCode (HMAC+pepper)
functions/src/lib/revenueCat.ts          — REST v2 istemci: grant/revoke promotional entitlement, getCustomer
                                            ⚠️ dosya başında "deploy öncesi resmi dokümanla doğrula" uyarısı var
functions/src/lib/customerSummary.ts     — [YENİ] upsertCustomerSummary: redeemPromoCode + webhook aynı
                                            hesabı paylaşıyor; accessSource RevenueCat'in kendi alanına değil
                                            yalnızca bizim Firestore kayıtlarımıza (granted redemption var mı,
                                            hiç store purchase event'i gördük mü) bakarak hesaplanıyor
functions/src/admin/middleware.ts        — requireAdminSession, requireCsrf, requireSameOrigin
functions/src/admin/session.ts           — login (argon2 verify + rate limit) + logout handler
functions/src/admin/promoCodes.ts        — create/list/disable + revokeRedemption handler'ları
functions/src/admin/dashboard.ts         — getAdminDashboard, listCustomers, getCustomerDetail
functions/src/admin/app.ts               — Express app, tüm /admin-api/* route'ları bağlıyor
functions/src/callable/redeemPromoCode.ts — [YENİ] deterministik `redemptions/{uid}_{promoId}` id'siyle
                                            atomik rezervasyon transaction'ı + transaction DIŞINDA RevenueCat
                                            çağrısı (transaction retry'ında dış API iki kez çağrılmasın diye);
                                            başarısızlıkta rezervasyon geri alınıyor, idempotent tekrar-gönderim
functions/src/webhooks/revenueCat.ts     — [YENİ] bağımsız onRequest (admin Express app'in dışında);
                                            imza doğrulaması Authorization header karşılaştırması
                                            (⚠️ deploy öncesi resmi dokümanla doğrula — bkz. dosya başı),
                                            event.id ile idempotency, getCustomer ile customerSummaries tazeleme
functions/src/index.ts                   — [YENİ] adminApi/redeemPromoCode/revenueCatWebhook export'ları;
                                            secret `.value()` çağrıları özenle yalnızca handler İÇİNDE,
                                            adminApi'nin Express app'i konteyner başına bir kez cache'leniyor
```

Doğrulama: `npm install` (ilk kez, `@node-rs/argon2` dahil hiçbir paket adı
sorun çıkarmadı), `npm run build` (tsc, hatasız), `npm run lint` (yeni
eklenen `.eslintrc.cjs` ile, hatasız) — hepsi bu ortamda çalıştırıldı ve
geçti.

### Bilinen sınırlamalar / sıradaki iyileştirme fırsatları (backend'de kaldı ama V1'i engellemiyor)

- `admin/promoCodes.ts`'teki `revokeRedemption` handler'ı revoke sonrası
  `customerSummaries`'i tazelemiyor (RevenueCat'ten entitlement kalksa da
  özet bir sonraki webhook event'ine kadar eski görünür). Küçük ama
  ayrı bir düzeltme — bu turda dokunulmadı çünkü dosya önceki oturumdan
  kalma ve konu dışı değişiklik sayılırdı.
- `customerSummary.ts`'teki `accessSource` hesaplaması RevenueCat'in kendi
  "bu entitlement nereden geldi" alanını kullanmıyor (o alan doğrulanmadı);
  yalnızca bizim `redemptions`/olay geçmişimize bakıyor. RevenueCat API'si
  resmi dokümanla doğrulanınca bu daha doğrudan bir alana geçirilebilir.

### Sırada — plandaki numaralandırmaya göre (henüz başlanmadı)

7. **macOS (Faz 1 + 4):** `AccountService` (Firebase Auth Google Sign-In,
   `@MainActor @Observable`), Settings'e Hesap bölümü, `EntitlementService`
   (RevenueCat CustomerInfo), paywall/redeem sheet. `project.yml`'e
   `FirebaseAuth` product eklenmeli — **dikkat: bu dosya diğer ajanların
   da değiştirdiği dosya, önce tekrar oku.**
8. **Next.js admin panel (Faz 5):** `website/app/admin/*` route'ları
   (login, overview, promocodes, customers, customers/[uid]). Statik
   export (`output: "export"`) olduğu için tüm admin sayfaları client
   component, veri `/admin-api/*`'ye `fetch(..., {credentials:"same-origin"})`
   ile çekilir.
9. **Deploy/environment ayrımı (Faz 6):** staging/production Firebase
   proje alias'ları, RevenueCat webhook URL kaydı, secret'ların gerçek
   değerlerle Secret Manager'a girilmesi (ADMIN_PANEL_PASSWORD_HASH için
   önce argon2id ile hash üretilip girilmeli — bu adım manuel, kullanıcı
   yapmalı, gerçek parolayı bana asla söylemesin).

### Kullanıcının benim yapamayacağım, onun yapması gereken adımlar

- Firebase Blaze (pay-as-you-go) planının `mac-utils` projesinde açık
  olduğunu doğrulamak (Cloud Functions için zorunlu).
- RevenueCat hesabı/projesi, `pro` entitlement'ı, gerçek API v2 secret
  key'i.
- Firebase Console'da Google Sign-In provider'ını etkinleştirmek.
- Argon2id ile admin parola hash'i üretip `ADMIN_PANEL_PASSWORD_HASH`
  secret'ına girmek (düz parolayı bana yazma).
- RevenueCat dashboard'da webhook URL + HMAC/Authorization header
  signing secret kurulumu — hangisi olduğu deploy öncesi resmi RevenueCat
  webhook dokümanıyla teyit edilmeli (bkz. `webhooks/revenueCat.ts`
  başındaki not).

### Yeni sohbete verilecek başlangıç mesajı (öneri)

```text
plans/010-promocodes-admin-revenuecat-firebase.md dosyasını baştan sona oku
(özellikle en üstteki "İlerleme durumu" bölümü). functions/ backend'i bitti
ve derleme/lint temiz — sıradaki adım Faz 1: macOS AccountService (Google
Sign-In) + Settings Hesap bölümü + paywall/redeem sheet. project.yml/
GlassDoApp.swift/SettingsView.swift gibi paylaşılan dosyalara dokunmadan
önce mutlaka tekrar oku — başka ajanlar bu dosyaları değiştirmiş olabilir.
Hiçbir deploy komutu çalıştırma; gerçek secret/deploy adımları kullanıcının
onayını gerektiriyor.
```

---

## Önce bilinmesi gerekenler

Mevcut `devices/{deviceID}` Firestore koleksiyonu, analitik izni veren
cihazların **anonim** kullanım istatistiklerini taşır. Firebase Auth yoktur;
bu yüzden bu belgeler gerçek kişi, satın alan kullanıcı veya RevenueCat
müşterisi değildir. Mevcut anonim analitiği bir kullanıcı hesabına bağlama,
e-posta ile zenginleştirme veya admin panelinden herkese açık okuma yapma.

Admin panel ve promocode için yeni, ayrı koleksiyonlar kullanılacak. RevenueCat
gizli API anahtarı, webhook secret'ı, Firebase Admin kimlik bilgileri veya
promo kodların düz metni macOS binary'ye, Next.js istemcisine, `.env` public
değişkenlerine ya da Git'e konmayacak.

Firebase Hosting yalnızca statik `website/out` dosyalarını yayınlar. Promocode
doğrulama, RevenueCat'e entitlement verme, webhook alma ve admin ayrıcalığı
kontrolü **Cloud Functions** içinde yapılmalıdır. Bu iş Firebase Blaze/billing
planı ve Cloud Functions deploy yetkisi gerektirir.

## Ürün ve kimlik kararı

### V1 erişim modeli

- RevenueCat entitlement kimliği: `pro`.
- Normal satın alma: mevcut/planlanan StoreKit veya RevenueCat Web akışı.
- Promocode: bir Cloud Function, kodun sahibine RevenueCat üzerinden zaman
  sınırlı veya lifetime `pro` promotional entitlement verir.
- Uygulama Pro durumunu yalnızca RevenueCat `CustomerInfo` ile belirler.
  Firestore'daki `redemptions` kaydı bir denetim/audit kaydıdır; uygulamanın
  erişim kararının kaynağı değildir.

### Kullanıcı kimliği

Promocode tek cihazlık rastgele RevenueCat anonymous ID ile verilmemeli; bu
durumda kullanıcı Mac değiştirince kodu ve Pro erişimini güvenilir biçimde
geri alamaz. V1 için kullanıcı uygulamada satın alma veya code redeem öncesinde
Firebase Auth ile Google Sign-In yapar. `auth.uid`, RevenueCat `appUserID`
olarak kullanılır:

1. İlk başlatmada RevenueCat anonim ID ile çalışabilir.
2. Kullanıcı "Pro al" veya "Promocode kullan" seçince Google ile oturum açar.
3. Uygulama `Purchases.logIn(auth.uid)` çağırır; anonymous geçmişi RevenueCat
   alias/transfer davranışıyla resmi SDK akışına göre korunur.
4. Bundan sonra entitlement ve Firestore kayıtları aynı `uid` üzerinden
   izlenir. E-posta yalnızca Firebase Auth'tan gelir; uygulamanın kendi
   Firestore verisine e-posta yazılmaz.

> Alternatif olarak Apple Sign In eklenebilir; V1'e dahil edilmesin. Google
> Sign-In yalnız macOS kullanıcısının satın alma/redeem kimliği içindir; admin
> panel bununla giriş yapmaz. Kullanıcı hesabı
> istemiyorsan promocode'u güvenilir şekilde cihazlar arası restore etmek veya
> "kim satın aldı" ekranını sunmak mümkün değildir.

## Mimari görünüm

```text
GlassDo macOS app                 Admin web (/admin)
Firebase Auth (opsiyonel)         Tek parola → HttpOnly admin session
        │                                  │
        ├── callable: redeemPromo ─────────┤── same-origin /admin-api/* HTTP functions
        │                                  │    (create/list/revoke/dashboard)
        ▼
Cloud Functions (2nd gen) ─── RevenueCat REST API v2
        ▲                         (secret yalnız backend'de)
        │
RevenueCat webhook (HMAC doğrulamalı)
        │
Firestore: promoCodes, redemptions, customerSummaries, revenueCatEvents
```

## Uygulama sırası

Bu görevleri ayrı, derlenebilir adımlarda yap. Önce backend güvenliği, sonra
macOS redemption ekranı, en son web paneli. Web arayüzü hiçbir zaman doğrudan
RevenueCat REST API çağrısı yapmasın.

1. Tek parolalı admin session altyapısı.
2. Firestore şeması ve kuralları.
3. Cloud Functions: promocode üretme, kullanma, revoke ve RevenueCat webhook.
4. macOS: sign-in, RevenueCat identity bağlama, code redeem/paywall akışı.
5. Next.js `/admin` paneli.
6. Emulator, sandbox ve production doğrulaması.

---

## 1 — Kullanıcı kimliği (opsiyonel) ve tek parolalı admin erişimi

### Uygulama

- Firebase Console'da Google provider'ı etkinleştir.
- `project.yml`e yalnızca gerekli Firebase iOS SDK ürünlerini ekle:
  `FirebaseAuth` ve Google ile giriş için gereken resmi SDK/konfigürasyon.
  Mevcut FirebaseCore/FirebaseFirestore kullanımını bozma.
- `AccountService` adında `@MainActor @Observable` merkezi servis oluştur.
  Durumları: `signedOut`, `signingIn`, `signedIn(UserIdentity)`, `error`.
- Ayarlar içinde Hesap bölümü: giriş yap, görünen e-posta, çıkış yap.
  Pro satın alma/redeem eylemlerinde giriş yoksa önce giriş sheet'i açılır.
- Çıkış, cihazdaki görevleri veya Pro entitlement'ı silmez. Ancak başka bir
  hesaba geçmeden önce açık entitlement'ın değişeceği net biçimde açıklanır
  ve RevenueCat logout/logIn akışı resmi SDK kurallarına uygun uygulanır.

### Admin

- Admin panel için Firebase Auth, Google hesabı, e-posta allowlist'i ya da
  custom claim kullanma. `/admin` açıldığında yalnızca parola alanı göster.
- `ADMIN_PANEL_PASSWORD_HASH` Secret Manager'da Argon2id hash olarak tutulur.
  Düz parolayı Firebase config'e, client JavaScript'e, Git'e veya Function
  loglarına koyma. Parola değişimi yeni hash secret deploy'u ile yapılır.
- `POST /admin-api/session` HTTP Function'ı parolayı HTTPS üzerinden alır,
  hash'i doğrular ve başarılıysa kısa ömürlü (örn. 8 saat) imzalı admin session
  üretir. Session, `HttpOnly; Secure; SameSite=Strict; Path=/` cookie olarak
  döner; JavaScript cookie'yi okuyamaz.
- Firebase Hosting rewrite ile `/admin-api/**` aynı Hosting origin'inden ilgili
  HTTP Function'a yönlendirilsin. Bu, üçüncü taraf cookie/CORS sorununu önler.
- Tüm admin endpointleri cookie'deki session imzasını ve expiry'yi doğrular;
  geçersizse 401 döner. `POST /admin-api/logout` cookie'yi siler.
- Login denemelerini hem IP hem oturum düzeyinde rate-limit et (örn. 5 yanlış
  denemeden sonra 15 dakika). Başarı/başarısızlıkta parolayı, hash'i veya
  ayrıntılı doğrulama farkını loglama.
- State değiştiren isteklerde yalnız `POST`/`DELETE` kullan, same-origin
  `Origin` kontrolü ve CSRF token uygula. Cookie tabanlı oturumda bu ikisi
  zorunludur.
- `/admin` statik sayfası yine herkese indirilebilir; gerçek koruma yalnız
  backend session denetimidir. Oturum yoksa panel hiç veri istemez ve login
  formu dışındaki admin içeriği çizilmez.

## 2 — Firestore şeması ve güvenlik kuralları

Yeni admin/purchase verisi, mevcut `/devices` analitiğinden tamamen ayrıdır.
Tarih alanları `Timestamp`, para alanları integer smallest unit veya RevenueCat
tarafından verilen değer olarak tutulur; float fiyat hesaplama yapma.

### Koleksiyonlar

#### `promoCodes/{promoId}` — gizli kod değil, kodun yönetim kaydı

```text
codeHash: string                 // normalize edilmiş kodun SHA-256 hash'i
prefix: string                  // örn. GLASS-ABCD; admin listesinde tanıma için
label: string                   // örn. YouTube Eylül kampanyası
entitlementID: "pro"
grantKind: "lifetime" | "untilDate"
expiresAt: Timestamp | null     // kod kullanma son tarihi
grantExpiresAt: Timestamp | null // kullanıcıya verilen erişimin sonu
maxRedemptions: number           // 1..10_000
redemptionCount: number
status: "active" | "disabled" | "exhausted" | "expired"
createdAt: Timestamp
createdByUID: string
disabledAt: Timestamp | null
```

Gerçek code yalnız oluşturulduğu anda Function cevabında bir kez gösterilir.
Firestore'a düz metin code veya e-posta/şifre kaydetme. Code girişinde trim,
upper-case ve boşluk/hyphen normalizasyonu yap; hash'ten önce sabit bir backend
pepper ile HMAC-SHA-256 kullan. Pepper Secret Manager'da tutulur.

#### `redemptions/{redemptionId}` — değişmez denetim kaydı

```text
promoId: string
promoPrefix: string
uid: string
revenueCatCustomerID: string
redeemedAt: Timestamp
grantKind: "lifetime" | "untilDate"
grantExpiresAt: Timestamp | null
status: "granted" | "revoked" | "failed"
revenueCatGrantReference: string | null
revokedAt: Timestamp | null
revokedByUID: string | null
```

Bir kullanıcı aynı `promoId`yi yalnız bir kez kullanabilir. Bunu yalnız
istemci kontrolüyle değil, transaction içinde `redemptions` sorgusu ve sayaç
artırma ile zorunlu kıl.

#### `customerSummaries/{uid}` — admin panel için RevenueCat projeksiyonu

```text
uid: string
email: string | null            // yalnız Firebase Auth / kullanıcı onayıyla
displayName: string | null
revenueCatCustomerID: string
activeEntitlements: [string]
accessSource: "store" | "promo" | "mixed" | "none"
productID: string | null
store: string | null
firstPurchaseAt: Timestamp | null
lastEventAt: Timestamp
environment: "production" | "sandbox" | null
```

Bu özet webhook/Function tarafından yazılır. Firestore doğrudan RevenueCat
yerine geçmez; panelde düşük gecikmeli listeler için cache/projeksiyondur.

#### `revenueCatEvents/{eventID}` — idempotent ham denetim olayı

```text
eventID: string                  // RevenueCat webhook event.id; document id de budur
type: string
uid: string | null
appUserID: string
productID: string | null
entitlementIDs: [string]
eventTimestamp: Timestamp
environment: string
receivedAt: Timestamp
```

Gereksiz transaction ID, IP, raw webhook body ya da ödeme kart bilgisi
tutma. Gerekirse hata teşhisi için Cloud Logging kullan; kalıcı PII loglama.

### Firestore Rules

- Mevcut `/devices/{deviceID}` kurallarını davranış olarak koru: anonim
  analiz yazılabilir, client tarafında okunamaz.
- `promoCodes`, `redemptions`, `customerSummaries`, `revenueCatEvents`
  için normal client read/write varsayılanı **false** olsun.
- Admin panelin listeleri için V1 tercih: panel yalnız session korumalı HTTP
  Functions kullanır; bu koleksiyonlarda Firestore
  client read/write hiçbir kullanıcıya açılmaz. Böylece pagination/filter
  mantığı ve alan redaction'ı backend'de kalır.

Server Admin SDK Firestore Rules'ı bypass eder; Cloud Functions IAM ve tüm
function giriş kontrolleri bu yüzden ayrı bir güvenlik sınırıdır.

---

## 3 — Cloud Functions (2nd gen)

Kök dizinde standart `functions/` TypeScript Firebase Functions projesi ekle.
Node sürümünü Firebase desteklediği güncel LTS ile sabitle. Fonksiyonlar için
tek bölge (ör. `europe-west1`) seç; web ve macOS istemcilerinde aynı bölgeyi
kullan. Secret'ları Firebase Secret Manager'a koy ve deploy sırasında bağla.

### Gerekli secret/config

```text
REVENUECAT_V2_SECRET_API_KEY
REVENUECAT_PROJECT_ID
REVENUECAT_WEBHOOK_SIGNING_SECRET
PROMO_CODE_PEPPER
ADMIN_PANEL_PASSWORD_HASH
ADMIN_SESSION_SIGNING_KEY
```

Hiçbiri `NEXT_PUBLIC_*`, `.xcconfig`, `GoogleService-Info.plist`, Firebase web
config'i veya log mesajı değildir.

### Uygulama için callable Function

#### `redeemPromoCode`

Girdi: `{ code: string }`. `request.auth` zorunlu.

1. Code'u normalize et, rate limit kontrolü yap (uid + IP/origin bilgisi
   uygunsa; en az uid başına 10 deneme/saat). Ham code'u loglama.
2. HMAC hash ile `promoCodes` kaydını bul; aktiflik, code expiry, max kullanım
   ve kullanıcının daha önce kullanımını denetle.
3. Firestore transaction ile geçici `reserving` redemption kaydı/sayaç
   rezervasyonu oluştur. Böylece aynı kod eşzamanlı iki kez kullanılamaz.
4. Backend, RevenueCat REST API v2 ile `pro` entitlement'ını `auth.uid`
   müşterisine verir. Lifetime için teknik olarak uzak tarih (örn. 2099-12-31)
   kullanmak yerine RevenueCat'in o tarih/sürümde önerdiği kalıcı grant
   yaklaşımını resmi endpoint dokümantasyonuyla doğrula ve kodda açıklama
   yaz. `untilDate` için açık `expires_at` gönder.
5. Başarılıysa redemption'ı `granted`, promo sayacını kesinleştir, customer
   summary'yi yenile; macOS'a `{ success: true }` dön.
6. RevenueCat isteği başarısızsa reservation'ı transaction ile geri al veya
   `failed` audit kaydına çevir; kullanıcıya tekrar denemesini söyle. Kullanım
   sayısı boşa harcanmamalı.
7. İşlem idempotent olmalı: aynı uid/promo tekrar gönderilirse yeni grant
   yaratmak yerine önceki başarılı sonucu dön.

#### `createPromoCode`, `listPromoCodes`, `disablePromoCode`, `revokePromoRedemption`

Bu işlemler callable değildir; `/admin-api/*` altındaki HTTP Function endpointleri
olarak uygulanır ve her biri geçerli admin session cookie + CSRF denetimi ister.

- `create`: label, redemption limit, code expiry, grant tipini doğrular;
  cryptographically secure rastgele code üretir (`GLASS-XXXX-XXXX`);
  düz code'u yalnız bu response'ta verir.
- `list`: arama, status filtresi, cursor pagination; düz code değil prefix ve
  metrikleri döndürür.
- `disable`: yeni kullanımları durdurur, geçmişte verilen Pro'yu otomatik
  kaldırmaz.
- `revokePromoRedemption`: yalnız hedef promotional grant'i RevenueCat'ten
  revoke eder, ilgili redemption audit kaydını günceller. Aynı müşterinin
  mağaza satın alımını asla kaldırmaz.
- Her admin mutasyonu için `adminAuditLogs`a sabit actor değeri `owner`, action,
  target id, timestamp ve zararsız metadata yaz. Firebase kullanıcı UID'si
  yazma; bu panelde kullanıcı hesabı yoktur.

#### `getAdminDashboard`, `listCustomers`, `getCustomerDetail`

Her biri geçerli admin session ister. Sadece panelin ihtiyacı olan alanları döndür:
özet sayaçlar, kullanıcılar, Pro durumu, source, ürün, purchase date,
promo redemption geçmişi ve RevenueCat dashboard'a giden müşteri arama/link
metadatası. Kod, secret, raw event veya tüm analitik cihaz verisini döndürme.

### RevenueCat webhook HTTP function

`revenueCatWebhook` HTTP endpoint'i sadece RevenueCat dashboard'a kaydedilir.

- Raw request body üzerinde RevenueCat HMAC imzasını constant-time compare ile
  doğrula; timestamp için makul replay toleransı uygula.
- İmza geçersizse 401/403 dön ve hiçbir Firestore yazısı yapma.
- `event.id` ile idempotency sağla. Aynı event tekrar gelirse 200 dön ama
  ikinci kez durum değiştirme.
- İlgili kullanıcı için RevenueCat Customer API'den güncel customer bilgisini
  çekip `customerSummaries`i güncelle. Event türlerinden farklı alanlar
  gelebileceği için final erişim durumunu tek event payload'ından tahmin etme.
- `INITIAL_PURCHASE`, `RENEWAL`, `NON_RENEWING_PURCHASE`, `CANCELLATION`,
  `EXPIRATION`, `BILLING_ISSUE`, `PRODUCT_CHANGE` ve promo grant/revoke
  etkilerini görünür audit olayına dönüştür.
- Hızlı 2xx cevap ver; idempotent işlem başarısız olursa RevenueCat retry
  davranışını destekleyecek hata kodu dön. Webhook auth/secretları loglama.

RevenueCat webhookları planının/hesabının desteklediğini release öncesi tekrar
doğrula. Yoksa V1 fallback olarak admin panelde "RevenueCat'ten yenile"
butonu yalnız admin Function ile API'den müşteri durumunu çeker; bunu toplu ve
sık polling'e dönüştürme.

---

## 4 — macOS: satın alma ve promocode arayüzü

Mevcut/planlanan `EntitlementService` tek Pro erişim sahibi olmaya devam eder.
`AccountService` ile onu ayrı tut: Auth kimlik sağlar, EntitlementService
RevenueCat CustomerInfo'yu sağlar.

### Paywall / Settings Pro ekranı

- Normal ürünleri RevenueCat Offering'den göster; fiyatı hard-code etme.
- "Promocode kullan" secondary butonu ekle.
- Butona basınca kullanıcı giriş yapmamışsa Google sign-in akışına yönlendir.
- Sheet: code text field, açık hata metni, `Kullan` butonu, loading state.
- Başarı: `Purchases.logIn(uid)` doğrula → `refreshCustomerInfo()` çağır →
  Pro durumunu CustomerInfo'dan güncelle → başarı mesajı göster.
- Hata sınıfları: geçersiz, süresi dolmuş, limit dolmuş, daha önce bu hesapta
  kullanılmış, ağ/servis sorunu. Detaylı backend bilgisi veya code hash
  gösterme.
- "Satın almayı geri yükle" ayrı görünür eylem olarak kalmalı.

### Gizlilik

- Ayarlar/Hesap ekranında: Google hesabının yalnız satın alma, promocode ve
  Pro restore için kullanıldığını; görevlerin ve dosya attachment'larının
  Firebase'e upload edilmediğini açıkla.
- Analytics izni, hesap/purchase kimliğinden bağımsız kalır. İzin vermeyen
  bir kullanıcının promo kullanımı/satın alması engellenmez.

---

## 5 — Firebase Hosting üzerindeki Next.js admin panel

Mevcut site `output: "export"` kullandığı için `website/app/admin/page.tsx`
client component olarak çalışır. Statik dosyada admin verisi bulunmaz; girişten
sonra `fetch(..., { credentials: "same-origin" })` ile yalnız `/admin-api/*`
endpointlerine çağrı yapar. Firebase web Auth SDK'sı admin alanında kullanılmaz.

### Rotalar

```text
/admin                 Giriş / yetkisiz ekranı
/admin/overview        Satış ve code özetleri
/admin/promocodes      Code listesi, oluşturma, devre dışı bırakma
/admin/customers       Satın alanlar/Pro kullanıcılar listesi
/admin/customers/[uid] Kullanıcı, entitlement ve redemption detayları
/admin/events          Son RevenueCat olayları (opsiyonel, V1 sonu)
```

`/admin` yolu güvenlik sınırı değildir: statik HTML herkes tarafından
indirilebilir. Veri ve mutasyon güvenliği yalnız HttpOnly admin session +
session doğrulayan HTTP Function içinde yapılır.

### Görünümler

#### Overview

- Toplam Pro erişimli kullanıcı, store kaynaklı Pro, promo kaynaklı Pro,
  son 7/30 gün satın alma ve son 7/30 gün redemption kartları.
- "Webhook son alındı" sağlık göstergesi ve sandbox/production ayrımı.
- Gelir toplamını yalnız RevenueCat API/planı güvenilir bir değer veriyorsa
  göster; yoksa sahte hesaplama yapma. İlk V1 odak: satın alma sayısı ve Pro
  entitlement durumu.

#### Promocodes

- Oluştur formu: label, maksimum kullanım, code kullanım son günü, grant
  (lifetime veya belirli tarih), opsiyonel internal campaign notu.
- Başarılı oluşturma sonrası code bir kez görünür; kopyala butonu var. Sayfa
  yenilendiğinde tekrar gösterilemez.
- Tablo: prefix, label, status, `redemptionCount / maxRedemptions`, code
  expiry, grant tipi, created at, created by. Arama ve cursor pagination.
- Satır action: disable; yalnız promo grant için revoke, ek onay diyaloğu ve
  işlem etkisini açıkça belirt.

#### Customers

- Kimlik/e-posta (varsa), UID kısaltması, Pro aktif mi, source, product,
  first purchase, son olay, environment. Tarih/sıralama/source filtreleri.
- Detay: RevenueCat customer id, aktif entitlementlar, promo redemption
  geçmişi, sınırlı event timeline ve RevenueCat dashboard'da müşteriyi açma
  bağlantısı (güvenli URL oluşturulabiliyorsa).
- Cihaz analitiğini müşteri sayfasına koyma; bunlar ilişkili değildir.

### Tasarım ve UX

- Mevcut landing sayfasının cam estetiğini kullan ama admin okunabilirliğini
  önceliklendir: tablolar, durum rozetleri, belirgin destructive confirm.
- Mobil panel V1'de desteklenir fakat masaüstü kullanımına optimize edilir.
- Erişilebilir tablo başlıkları, klavye odağı, loading/empty/error states ve
  Türkçe/İngilizce/Rusça metinler ekle.

---

## 6 — Deploy ve environment ayrımı

### Firebase yapılandırması

- `firebase.json`a Functions tanımını ekle; mevcut Hosting redirectlerini
  ve `website/out` public ayarını bozma.
- Firebase CLI'da iki proje/alias kullan: `staging` ve `production`. Sandbox
  RevenueCat events yalnız staging Firestore'a, production events yalnız
  production'a düşmeli.
- Firebase Auth kullanılıyorsa authorized domains listesine production Hosting
  domainini ve local geliştirme domainini ekle; bu ayar admin parolası için
  gerekli değildir.
- Hosting deploy komutu admin panel static exportu da içerir:

```bash
cd website && npm run build && cd ..
firebase deploy --only hosting,functions,firestore:rules
```

Deploy komutundan önce Secret Manager değerlerini yalnız Firebase CLI ile
gir; terminal çıktısına secret yazdırma. `.env.local` yalnız `NEXT_PUBLIC_`
Firebase web config değerlerini içerir ve Git'e girmez.

### RevenueCat dashboard ayarları

1. `pro` entitlement'ını ve ürün eşlemelerini doğrula.
2. Firebase HTTP function webhook URL'sini ekle.
3. HMAC signing secret ve/veya özel Authorization header kur; aynı değeri
   Firebase secret olarak ekle.
4. Önce sandbox eventleri staging endpoint'e yönlendir; sonra production'ı
   ayrı endpoint'e bağla.
5. RevenueCat customer API key'ine yalnız gerekli customer-information
   read/write yetkisini ver; geniş owner key kullanma.

## Kabul kriterleri

- Parola bilinmeden `/admin`e giren kişi satış, code veya cihaz verisi göremez;
  session cookie olmadan tüm `/admin-api/*` çağrıları 401 döner.
- Parola veya session cookie client bundle, Firestore, URL, log ya da ekran
  görüntüsünde yer almaz; yanlış girişler rate-limit edilir.
- Admin bir code üretir, code ekranda yalnız bir kez düz metin görünür;
  Firestore/admin listesinde yalnız prefix/hash bulunur.
- Giriş yapmış Mac kullanıcısı geçerli code'u kullanınca tek seferlik Pro
  entitlement alır ve uygulama CustomerInfo yenilendikten sonra Pro olur.
- Aynı user + aynı code ikinci kez kullanım sayısını veya entitlement'ı tekrar
  artırmaz; eş zamanlı iki redemption max kullanım limitini geçemez.
- Geçersiz/süresi geçmiş/devre dışı/limit dolmuş code, Pro açmaz ve ham code
  loglanmaz.
- RevenueCat purchase webhook'u customer summary'yi günceller; aynı webhook
  tekrar gelince duplicate event veya yanlış sayaç oluşmaz.
- Admin panelde promo kullanım durumu ve satın alan/pro erişimli kullanıcı
  doğru source/product/tarih ile görünür.
- Promo revoke, yalnız promotional grant'i kaldırır; gerçek App Store/Web
  satın alma entitlement'ını kaldırmaz.
- Firestore Rules testleri; Functions unit/integration testleri; web lint/build;
  macOS Debug build ve sandbox purchase/redeem smoke testleri başarılıdır.

## Açıkça kapsam dışı

- Kullanıcı görevleri, notları, dosyaları veya clipboard geçmişini buluta
  senkronlama ya da admin panelde gösterme.
- Kredi kartı, fatura adresi, ödeme belgesi veya gereksiz PII saklama.
- Referral/affiliate ödeme sistemi, public coupon landing page, çoklu para
  birimi gelir muhasebesi, ekip rolleri ve self-service refund.
- Promocode'u App Store ödeme mekanizmasının yerine kullanma. App Store
  dağıtımındaki kampanya/offer kuralları Apple ile ayrıca doğrulanmalı.

## Sonnet'e verilecek başlangıç mesajı

```text
plans/010-promocodes-admin-revenuecat-firebase.md dosyasını baştan sona oku ve
uygula. Önce mevcut firebase.json, firestore.rules, website/ static-export
yapısı, Firebase analytics kodu ve RevenueCat planını incele. Backend secret,
promocode doğrulama veya RevenueCat REST çağrısını hiçbir koşulda istemciye
taşıma. Aşamaları sırayla ve ayrı derlenebilir değişiklikler olarak yap; mevcut
anonim /devices analytics kurallarını koru. Firestore Rules, Functions,
Next.js admin panel ve macOS redemption akışını test et. İlgisiz değişikliklere
dokunma; test/build sonuçları ve gerekli Firebase/RevenueCat console adımlarını
teslimde net listele.
```

## Resmi referanslar

- [RevenueCat entitlement grant API](https://www.revenuecat.com/docs/api-v2/customer)
- [RevenueCat webhooks ve HMAC doğrulama](https://www.revenuecat.com/docs/integrations/webhooks)
- [Firebase callable functions](https://firebase.google.com/docs/functions/callable)
- [Firestore custom-claim security](https://firebase.google.com/docs/rules/basics)
