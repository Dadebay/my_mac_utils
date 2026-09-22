# 14 — GlassDo'yu Satışa Hazırlama, Monetizasyon ve RevenueCat

> Güncellik: 2026-08-29  
> Kapsam: Mevcut native SwiftUI **macOS** uygulaması. Bu belge hukuki veya
> vergi danışmanlığı değildir; ülkeye göre bir uzmana danışılması gerekebilir.

## Kısa cevap

GlassDo yalnızca macOS uygulaması olarak yayınlanıp satılabilir. iPhone,
iPad veya Android sürümü yapmak zorunlu değildir. RevenueCat'in Apple SDK'sı
macOS'u destekler; Mac App Store içi satın almaları ve abonelikleri StoreKit
üzerinden yönetebilir. iOS eklenirse Apple universal purchase ile aynı satın
almanın Apple platformlarında paylaşılması da mümkün olabilir.

Bu proje için ilk tercih:

1. **Tam özellikli doğrudan macOS dağıtımı:** Developer ID ile imzalanmış,
   notarize edilmiş DMG; ödeme için RevenueCat Web + Paddle/Stripe/RevenueCat
   Billing. Mevcut güçlü sistem özelliklerini korumak daha kolaydır.
2. Daha sonra istenirse **ayrı Mac App Store flavor'ı:** App Sandbox açık,
   sandbox'ta çalışmayan özellikler kapalı veya yeniden tasarlanmış; StoreKit +
   RevenueCat Apple SDK.

Tek platform ve yalnız bir lifetime ürünle başlanacaksa RevenueCat zorunlu
değildir; StoreKit 2 de yeterlidir. Fakat uzaktan değiştirilebilir offerings,
paywall, entitlement yönetimi, analitik ve ileride web/iOS/Android ortak erişimi
isteniyorsa RevenueCat anlamlıdır.

## Projenin bugünkü dağıtım denetimi

29 Ağustos 2026'da repoda görülen durum:

- Yalnızca `GlassDo-macOS`, `GlassDoWidgets` ve test target'ı var; iOS/Android
  target'ı yok. Bu bir eksik değil, ürün kapsamı kararıdır.
- Minimum sistem `macOS 26.0`. Bu, Liquid Glass API'lerini kolaylaştırır fakat
  potansiyel müşteri kitlesini yalnız macOS 26 kullananlarla sınırlar. Lansmandan
  önce gerçek pazar hedefiyle bilinçli olarak onaylanmalı.
- Hardened Runtime açık.
- Widget extension sandbox'lı; ana uygulamanın
  `Config/GlassDo.entitlements` dosyasında App Sandbox açık değil.
- Ana uygulama `/usr/bin/nettop` çalıştırıyor, başka uygulamaları sonlandırıyor,
  Accessibility/CGWindow ile pencere yönetiyor ve disk klasörlerini tarıyor.
  Bunların Mac App Store sandbox sürümünde tek tek kanıtlanması gerekir.
- App Group mevcut: `V793RH49BX.group.com.dadebay.glassdo`.
- Bundle kimlikleri satış öncesi kesinleştirilmemiş görünüyor. Dokümanlarda
  `com.dadebay.glassdo`, target üretiminde ise isimden türeyen farklı bir kimlik
  oluşma ihtimali var. App Store kaydı ve RevenueCat ürünü açılmadan önce tek
  değer seçilmeli.
- `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`.
- `NSHumanReadableCopyright` boş.
- Repoda RevenueCat entegrasyonu ve uygulamaya ait `PrivacyInfo.xcprivacy`
  bulunamadı.

## 1. Önce dağıtım kanalını seç

### Seçenek A — Mac App Store

Avantajlar:

- Kullanıcının güvendiği App Store ödeme ve güncelleme akışı.
- StoreKit satın alma/restore yönetimi.
- Apple'ın ülke, para birimi ve çoğu vergi akışını yönetmesi.
- RevenueCat Apple SDK ile daha düz entegrasyon.

Zorunluluklar ve riskler:

- Mac App Store uygulamalarında App Sandbox zorunludur.
- Dijital özellik açmak için App Store In-App Purchase kullanılmalıdır.
- Mevcut `nettop`, tüm diski tarama, başka uygulamaları kapatma ve Accessibility
  tabanlı pencere değiştirme özellikleri sandbox/review açısından test edilmeden
  “çalışır” kabul edilmemeli.
- Kullanıcı tarafından seçilen klasörler için security-scoped bookmark ve
  `com.apple.security.files.user-selected.read-write` gerekir.
- İlk IAP/abonelik ilgili app sürümüyle birlikte incelemeye gönderilir.

### Seçenek B — Doğrudan satış

Avantajlar:

- Sistem utility özellikleri için daha uygun yetki modeli.
- Fiyat, deneme, lifetime lisans ve kampanyalarda daha fazla esneklik.
- Mac App Store sandbox kısıtları yok; ancak kullanıcı izni ve güvenlik kuralları
  yine geçerlidir.

Zorunluluklar:

- Apple Developer Program üyeliği.
- Developer ID ile imza, Hardened Runtime, notarization ve stapling.
- DMG/ZIP dağıtımı.
- Güncelleme için tercihen Sparkle 2 ve imzalı appcast.
- Ödeme, fatura, iade, satış vergisi/KDV ve müşteri portalı. Merchant of record
  kullanan Paddle gibi bir çözüm operasyon yükünü azaltabilir.
- RevenueCat Web kullanılıyorsa satın almayı doğru kullanıcı kimliğiyle
  entitlement'a bağlayan bir hesap/kimlik akışı gerekir.

### Seçenek C — İki kanal

Uzun vadede yapılabilir fakat ilk lansman için en karmaşık yoldur:

- `GlassDo-Direct`: tam özellik, Developer ID, web ödeme.
- `GlassDo-MAS`: sandbox'lı, StoreKit ödeme, gerekirse bazı sistem özellikleri
  sınırlı.
- Ortak kaynak kodu, ayrı build configuration, entitlements ve RevenueCat app
  kaydı kullanılır.
- Aynı “pro” erişimi farklı store ürünlerine bağlanabilir; platformlar arası
  erişim istenirse kullanıcı hesabı ve aynı RevenueCat App User ID gerekir.

## 2. GlassDo için önerilen iş modeli

GlassDo bugün çoğunlukla cihaz üzerinde çalışan bir utility. Sürekli sunucu
maliyeti veya her ay yeni içerik yokken yalnız abonelik sunmak kullanıcıya zayıf
değer hissi verebilir.

### Önerilen v1 modeli

- Uygulama ücretsiz indirilebilir.
- Temel görev yönetimi ücretsiz kalır.
- `GlassDo Pro Lifetime` adlı **non-consumable** ürün bütün Pro özelliklerini
  kalıcı açar.
- İleride gerçekten sürekli değer geldiğinde (iCloud/cross-platform sync,
  encrypted backup, AI, ekip özellikleri gibi) aylık/yıllık abonelik eklenir.

Test edilecek ilk fiyat hipotezi — kesin fiyat değil:

- Lifetime: USD 29.99–49.99
- Yıllık plan ancak devam eden hizmet gelirse: USD 19.99–29.99/yıl
- Aylık plan gerekiyorsa: USD 2.99–4.99/ay

Fiyatı maliyet + rakip + kullanıcı görüşmeleriyle doğrula. İlk sürümde lifetime
ürün, uygulamanın bugünkü yerel utility değerine daha iyi oturur.

### Free / Pro önerisi

Free:

- Tasks ve Completed.
- Temel edge rail.
- Overview'da temel anlık değerler.
- Bir managed folder.
- Sınırlı widget/menü çubuğu seçimi.
- Satın alma ekranını değerlendirmeye yetecek gerçek kullanım.

Pro:

- Memory, Network, Battery, Disk ve Processor detay sayfaları.
- Per-core CPU grafiği ve uzun network geçmişi.
- Network kullanan uygulamalar ve gelişmiş speed test.
- Disk alan analizörü.
- Sınırsız managed folder ve gelişmiş dosya işlemleri.
- Window Switcher.
- Bütün desktop widgets ve menu bar ölçerleri.
- Rail görünürlük, boyut, konum ve tema özelleştirmeleri.

Güvenlik veya veri kurtarma özellikleri ücret duvarının arkasına konulmamalı.
Kullanıcı kendi verisini dışa aktarabilmeli; satın alma geri yükleme her zaman
erişilebilir olmalı. Dosya silme ve uygulama kapatma gibi tehlikeli işlemler Pro
olsa bile confirmation akışını korumalı.

## 3. RevenueCat katalog modeli

RevenueCat'te isimler:

- **Product:** App Store Connect/Web ödeme sağlayıcısındaki gerçek ürün.
- **Entitlement:** Uygulamadaki erişim hakkı; burada `pro`.
- **Package:** Platformlar arası eşdeğer ürünleri temsil eder.
- **Offering:** Paywall'da o anda sunulan package grubu; burada `default`.

Önerilen kimlikler:

```text
Entitlement: pro
Offering: default

Mac App Store non-consumable:
com.dadebay.glassdo.pro.lifetime

Gelecekte abonelik eklenirse:
com.dadebay.glassdo.pro.monthly
com.dadebay.glassdo.pro.annual
```

Product ID'ler oluşturulduktan sonra değiştirilmesi zor olduğundan önce bundle
ID ve isim stratejisini kesinleştir.

## 4. Mac App Store + RevenueCat kurulumu

### App Store Connect

1. Apple Developer Program'a katıl.
2. App Store Connect'te Paid Apps Agreement'ı kabul et.
3. Vergi ve banka bilgilerini tamamla.
4. Uygulama kaydını kesin bundle ID ile oluştur.
5. Lifetime için Non-Consumable IAP oluştur veya abonelik için önce Subscription
   Group oluştur.
6. Ürün adı, açıklama, fiyat, ülkeler, review screenshot ve review note ekle.
7. Restore Purchases ve Manage Subscription erişimini uygulamada görünür yap.
8. İlk IAP/aboneliği yeni app version ile birlikte review'a ekle.

### RevenueCat Dashboard

1. RevenueCat project oluştur.
2. Apple App Store app/provider ekle.
3. App Store Connect API credentials ve In-App Purchase key'i resmi RevenueCat
   kurulumuna göre bağla.
4. Ürünleri import et.
5. `pro` entitlement oluştur ve bütün ücretli ürünleri buna bağla.
6. `default` offering oluştur; lifetime/monthly/annual package'larını bağla.
7. Paywall oluştur veya uygulama içindeki native paywall'a offering verisini
   bağla.
8. Debug için Test Store key, Release için Apple platform production public SDK
   key kullan. Secret key'i uygulama içine koyma.

### Xcode/SPM

RevenueCat resmi Swift Package:

```text
https://github.com/RevenueCat/purchases-ios-spm.git
```

Uygulama target'ına `RevenueCat` ekle. Hazır RevenueCat Paywalls macOS
tasarımında yeterince doğal görünmüyorsa `RevenueCatUI` yerine kendi SwiftUI
paywall'unu kullan; ürün/fiyat verisini yine Offering'den al. Fiyatı string olarak
hard-code etme.

## 5. Kod mimarisi

Tek bir merkezi satın alma servisi oluştur:

```swift
@MainActor
@Observable
final class EntitlementService {
    enum AccessState {
        case loading
        case free
        case pro
    }

    private(set) var state: AccessState = .loading
    private(set) var offering: Offering?

    var hasPro: Bool { state == .pro }

    func configure() async
    func refreshCustomerInfo() async
    func purchase(_ package: Package) async throws
    func restorePurchases() async throws
}
```

Kurallar:

- `Purchases.configure` uygulama yaşam döngüsünde yalnız bir kez çağrılsın.
- Pro kontrolü her view içine dağılmasın. Tek `Feature` enum'u ve merkezi
  `FeatureAccess` kullan.
- Paywall, ücretli işlemi seçen kullanıcıya bağlam içinde açılsın. Uygulama her
  açıldığında zorla tam ekran paywall gösterme.
- Ağ hatasını “satın almadın” diye yorumlama. RevenueCat cache'indeki son geçerli
  CustomerInfo ile offline kullanım korunmalı.
- Refund, expiration, billing issue ve entitlement değişiklikleri uygulama aktif
  olduğunda refresh edilmeli.
- Restore Purchases Settings ve paywall'da her zaman görünür olmalı.
- Satın alma sırasında buton loading/disabled durumu göstermeli; double purchase
  engellenmeli.
- Kullanıcı cancel ederse hata alert'i gösterme.

### Kimlik kararı

Yalnız Mac App Store ve hesapsız kullanım:

- RevenueCat anonymous App User ID ile başlanabilir.
- Yeni kurulum/başka Mac için açık Restore Purchases gerekir.

Doğrudan web ödeme veya gelecekte platformlar arası erişim:

- Kalıcı kullanıcı hesabı gerekir.
- RevenueCat App User ID olarak rastgele, değişmeyen uygulama kullanıcı UUID'si
  kullan; e-posta adresini doğrudan ID yapmak yerine hesap kaydına bağla.
- Uygulama ve web checkout aynı App User ID'yi kullanmalı.
- Login/logout ve alias/transfer davranışı release öncesi test edilmeli.

### Widget extension

Widget içinde satın alma akışı başlatma. Ana uygulama RevenueCat entitlement
sonucunu App Group'a küçük bir snapshot olarak yazsın:

```text
isPro: Bool
checkedAt: Date
schemaVersion: Int
```

Widget bu snapshot'a göre Pro widget içeriğini veya “Open GlassDo to unlock”
durumunu gösterir. Ana uygulama satın alma/restore sonrası
`WidgetCenter.shared.reloadAllTimelines()` çağırır. Ağ geçici olarak kesildiğinde
aktif Pro widget'ı hemen kilitleme.

## 6. Direct satış + RevenueCat Web

Mac App Store dışında dağıtılan build StoreKit ürünü satmak zorunda değildir.
RevenueCat Web; RevenueCat Billing, Stripe Billing veya Paddle Billing ile web
checkout oluşturabilir.

Önerilen akış:

1. Kullanıcı uygulama içinde Pro'yu seçer.
2. Uygulama güvenli tarayıcıda RevenueCat Web Purchase Link açar.
3. Link aynı kalıcı App User ID'yi içerir.
4. Ödeme tamamlandığında uygulama aktif olur ve CustomerInfo refresh eder.
5. `pro` entitlement aktifse özellikler açılır.
6. Settings'te “Manage billing”, “Restore/Refresh purchases” ve destek bağlantısı
   bulunur.

Doğrudan satışta merchant-of-record seçmek global KDV/sales tax, fatura ve bazı
iade operasyonlarını kolaylaştırabilir. Stripe kullanılırsa vergi ve yasal
yükümlülüklerin hangi kısmının satıcıda kaldığı ayrıca değerlendirilmelidir.

Mac App Store build'inde dış ödeme linki gösterme kuralları storefront ve bölgeye
göre değişebilir. Tek bir global davranış hard-code etme; güncel App Review
Guideline 3.1'i release tarihinde yeniden kontrol et.

## 7. Mac App Store sandbox çalışması

Mac App Store hedefi yapılacaksa:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

App Group korunur. Ayrıca:

- Folder erişimleri security-scoped bookmark olarak saklanmalı.
- `startAccessingSecurityScopedResource()` dengeli şekilde kapatılmalı.
- Sandbox içinden `/usr/bin/nettop` çalıştırma kanıtlanmadan network-process
  özelliği MAS build'ine dahil edilmemeli.
- Tüm disk taraması yerine yalnız kullanıcı seçimiyle erişilen konumlar taranmalı.
- Başka uygulamaları terminate etme ve Accessibility pencere kontrolü temiz bir
  sandbox Release build'de denenmeli.
- Çalışmayan özellikler derleme bayrağıyla MAS flavor'ından çıkarılmalı ve App
  Store açıklamasında vaat edilmemeli.

Önerilen build ayrımı:

```text
Debug
Release-Direct
Release-MAS
```

API key, entitlements, update mekanizması ve ödeme sağlayıcısı configuration
üzerinden ayrılmalı; `#if` blokları minimum tutulmalı.

## 8. Privacy, hukuk ve müşteri desteği

Lansmandan önce herkese açık HTTPS sayfaları:

- Privacy Policy
- Terms of Use / EULA
- Support sayfası
- Support e-postası
- Refund/cancellation açıklaması (satış kanalına uygun)

App Store Connect privacy cevapları yalnız kendi kodunu değil RevenueCat ve tüm
üçüncü taraf SDK'ları da kapsamalı. Xcode Privacy Report üretip
`PrivacyInfo.xcprivacy` dosyasını hem uygulama hem ilgili extension target'larına
ekle. RevenueCat'in güncel privacy manifest ve data disclosure dokümanını release
sürümüyle birlikte kontrol et.

Abonelik varsa paywall ve metadata şunları açıkça göstermeli:

- Ürün adı ve dönem.
- Yerelleştirilmiş gerçek fiyat.
- Otomatik yenilenme bilgisi.
- Trial süresi ve trial sonrası fiyat.
- Terms ve Privacy bağlantıları.
- Restore Purchases.
- Aboneliği yönetme yolu.

## 9. App Store metadata paketi

- Uygulama adı ve subtitle.
- Kategori: Productivity veya Utilities; ana değere göre biri seçilmeli.
- Açıklama ve keyword'ler.
- 1024×1024 App Store icon; macOS icon set'in bütün boyutları.
- Gerçek macOS ekran görüntüleri; ücret gerektiren özellikler açıkça belirtilmeli.
- App preview opsiyonel.
- Privacy Policy URL.
- Support URL ve çalışan iletişim adresi.
- Copyright.
- Yaş derecelendirmesi.
- Export compliance cevapları.
- Review notes: Accessibility izni, folder erişimi, window switcher, process
  quit, disk delete ve Pro satın alma adımlarını açıkça anlat.
- Review için bütün premium özellikleri açabilecek sandbox hesabı/ürünü veya demo
  yolu sun.

## 10. Teknik release checklist

Kimlik ve signing:

- [ ] Final app adı kesin.
- [ ] Final bundle ID kesin ve bütün config/doclarda aynı.
- [ ] Widget bundle ID final app ID'nin altında.
- [ ] App Group Developer Portal'da oluşturulmuş ve iki target'a bağlı.
- [ ] Development Team doğru.
- [ ] Release-Direct ve/veya Release-MAS profile'ları hazır.
- [ ] Version ve build numarası CI/release sürecinde artırılıyor.
- [ ] Copyright dolu.

Satın alma:

- [ ] `pro` entitlement tek kaynak.
- [ ] Offering ve package'lar doğru ürüne bağlı.
- [ ] Debug Test Store key, Release production platform key kullanıyor.
- [ ] Secret RevenueCat key binary içinde yok.
- [ ] Paywall gerçek StoreKit/Offering fiyatını gösteriyor.
- [ ] Purchase, cancel, pending, failure, refund ve expiration test edildi.
- [ ] Restore Purchases çalışıyor.
- [ ] Offline Pro erişimi beklenen şekilde çalışıyor.
- [ ] Widget entitlement snapshot ve timeline reload çalışıyor.
- [ ] Web ödeme varsa App User ID iki tarafta birebir aynı.

Kalite:

- [ ] Unit ve UI testleri geçiyor.
- [ ] Release configuration archive ediliyor.
- [ ] Temiz bir macOS kullanıcı hesabında ilk açılış test edildi.
- [ ] İzin reddi durumları test edildi.
- [ ] Accessibility izni sonradan verilince/geri alınınca uygulama toparlanıyor.
- [ ] Klasör bookmark'ları uygulama yeniden açıldıktan sonra çalışıyor.
- [ ] Disk silme Trash'e gönderiyor ve açık confirmation gösteriyor.
- [ ] Process quit yanlış uygulamayı kapatmıyor.
- [ ] Ağ yokken görevler ve satın alınmış özellikler kullanılabiliyor.
- [ ] Türkçe, İngilizce ve Rusça satın alma ekranları taşmıyor.
- [ ] VoiceOver, keyboard navigation, Increase Contrast ve Reduce Motion test edildi.
- [ ] Crash/hang ve memory leak kontrolü yapıldı.

Privacy ve operasyon:

- [ ] Privacy manifest uygulama ve widget bundle'ında mevcut.
- [ ] App Store privacy label üçüncü taraf SDK'larla uyumlu.
- [ ] Privacy, Terms ve Support URL'leri canlı.
- [ ] Paid Apps Agreement, vergi ve banka bilgileri tamam.
- [ ] Uygunsa App Store Small Business Program başvurusu yapıldı.
- [ ] RevenueCat dashboard production uyarısı yok.
- [ ] Destek ve refund cevap şablonları hazır.
- [ ] RevenueCat fiyat/limitleri release tarihinde tekrar kontrol edildi.

Direct dağıtım:

- [ ] Developer ID imzası doğrulandı.
- [ ] Hardened Runtime açık.
- [ ] Archive notarize edildi ve ticket staple edildi.
- [ ] `spctl` kabul ediyor.
- [ ] DMG temiz bir Mac'te açılıyor.
- [ ] Sparkle update imzası ve downgrade koruması test edildi.
- [ ] Eski sürümden yeni sürüme veri migration'ı test edildi.

Mac App Store:

- [ ] Ana target App Sandbox açık.
- [ ] MAS build hiçbir sandbox violation üretmiyor.
- [ ] IAP sandbox gerçek App Store ürünleriyle uçtan uca test edildi.
- [ ] İlk IAP app version ile review'a ekli.
- [ ] Review notes bütün özel izinleri açıklıyor.
- [ ] Manuel/phased release stratejisi seçildi.

## 11. Önerilen uygulama sırası

1. Dağıtım kanalını seç: önce Direct önerilir.
2. App adı, bundle ID ve App Group'u dondur.
3. Free/Pro özellik tablosunu ürün kararı olarak kesinleştir.
4. Privacy, Terms, Support web sayfalarını hazırla.
5. RevenueCat project, `pro` entitlement ve `default` offering oluştur.
6. `EntitlementService` ve merkezi feature gate katmanını yaz.
7. Native macOS paywall, restore ve manage billing ekranını ekle.
8. Widget entitlement snapshot'ını bağla.
9. Test Store ile state/error testleri yap.
10. Seçilen gerçek ödeme kanalının sandbox/test ortamıyla uçtan uca test yap.
11. Direct ise notarized beta; MAS ise sandbox beta/archive hazırla.
12. 10–30 gerçek beta kullanıcıyla onboarding, değer ve fiyat görüşmeleri yap.
13. Crash/feedback düzeltmelerinden sonra küçük veya manuel release yap.
14. Conversion, refund, churn ve en çok kullanılan Pro özellikleri aylık izle.

## 12. Maliyet çerçevesi

- Apple Developer Program: USD 99/yıl (bölgesel fiyat değişebilir).
- Apple komisyonu: programa ve koşullara göre değişir. Uygun küçük geliştiriciler
  App Store Small Business Program'da paid app/IAP için %15 oranından
  yararlanabilir; güncel uygunluk ve bölgesel şartlar release tarihinde kontrol
  edilmeli.
- RevenueCat Pro: güncel resmi fiyatlandırmada aylık USD 2,500 tracked revenue'a
  kadar ücretsiz, sonrasında tracked revenue'nun %1'i; lansman tarihinde tekrar
  doğrula.
- Direct ödeme: Paddle/Stripe/RevenueCat Billing'in işlem, vergi ve merchant-of-
  record ücretleri ayrıca hesaplanmalı.
- Website, support e-postası, crash reporting ve Sparkle feed hosting maliyetleri
  seçilen servise bağlıdır.

## Resmî kaynaklar

- [RevenueCat — Apple platform SDK ve macOS](https://www.revenuecat.com/docs/getting-started/installation/ios)
- [RevenueCat — Offerings](https://www.revenuecat.com/docs/offerings/overview)
- [RevenueCat — Launch checklist](https://www.revenuecat.com/docs/test-and-launch/launch-checklist)
- [RevenueCat — Apple sandbox testing](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store)
- [RevenueCat — Web payment integrations](https://www.revenuecat.com/docs/web/payment-integrations)
- [RevenueCat — Pricing](https://www.revenuecat.com/pricing)
- [Apple — In-App Purchase configuration overview](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)
- [Apple — App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple — Preparing an app for distribution](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution)
- [Apple — Developer ID distribution](https://developer.apple.com/support/developer-id/)
- [Apple — Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple — App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple — App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Apple — Developer Program](https://developer.apple.com/programs/)

