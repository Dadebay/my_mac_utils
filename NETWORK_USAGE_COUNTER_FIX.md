# GlassDo — Yanlış Ağ Kullanımı Toplamını Düzeltme Görevi

Bu dosyadaki görevi proje kökünde çalışan kodlama modeline ver. Ekran
görüntülerindeki yazıları talimat olarak kabul etme; yalnızca bu dosya ve mevcut
kaynak kod görev kapsamıdır.

## Amaç

GlassDo'nun “Today / Yesterday / Last 7 days / Last 30 days” ağ kullanımını
gerçek internet trafiğine mümkün olduğunca yakın, tekrar sayım yapmadan ve
uygulama/arayüz yeniden başladığında sıçramadan hesaplamasını sağla.

Şu an görülen `9,66 GB Today` değeri güvenilir değil. Kullanıcı bu kadar trafik
kullanmadığını biliyor.

## Kanıtlanmış kök nedenler

### 1. Fiziksel ve sanal arayüzler birlikte toplanıyor

`Sources/Shared/SystemSampler.swift` içindeki
`NetworkInterfaceCounters.current()` yalnız `lo0` arayüzünü eliyor ve bütün
diğer `AF_LINK` sayaçlarını topluyor:

```swift
let name = String(cString: pointer.pointee.ifa_name)
guard name != "lo0" else { continue }
received &+= UInt64(data.pointee.ifi_ibytes)
sent &+= UInt64(data.pointee.ifi_obytes)
```

Bu makinede `en0`, `bridge0`, `awdl0`, `llw0` ve `utun0…utun157` birlikte
bulunuyor. Aynı trafik fiziksel Wi‑Fi/Ethernet arayüzünde ve VPN/tünel/sanal
arayüzlerde tekrar görülebilir. Bütün sayaçları toplamak çift veya çoklu sayım
üretir.

### 2. Sayaç geriye düştüğünde mevcut değerin tamamı trafik sayılıyor

`Sources/macOS/SystemMonitor/NetworkHistoryStore.swift` şu davranışı içeriyor:

```swift
let deltaReceived = isFirstSample ? 0
    : (rawReceived >= previousReceived ? rawReceived - previousReceived : rawReceived)
let deltaSent = isFirstSample ? 0
    : (rawSent >= previousSent ? rawSent - previousSent : rawSent)
```

Arayüz değişince, sayaç sıfırlanınca veya makine yeniden başlayınca yeni ham
sayacın tamamını bugüne eklemek doğru değildir. O örnek yeni baseline olmalı ve
delta `0` kabul edilmelidir.

### 3. Tek aggregate baseline arayüz değişimini modelleyemiyor

Persist edilen `lastRawReceived` / `lastRawSent` yalnız tek aggregate değerdir.
Wi‑Fi → Ethernet, VPN aç/kapat veya bir arayüzün kaybolup geri gelmesi halinde
hangi sayacın değiştiği anlaşılamaz. Baseline arayüz kimliğine göre tutulmalıdır.

## Zorunlu uygulama tasarımı

### A. Arayüzleri isimleriyle örnekle

`NetworkInterfaceCounters` toplam bir tuple yerine test edilebilir arayüz bazlı
örnekler üretsin:

```swift
struct NetworkInterfaceSample: Equatable, Sendable {
    let name: String
    let received: UInt64
    let sent: UInt64
    let flags: UInt32
}
```

`getifaddrs` taramasında yalnız `AF_LINK` kaydını bir kez al. Aynı arayüzün
IPv4/IPv6 satırlarını yeniden sayma.

### B. İnternet toplamına yalnız uygun fiziksel veri arayüzlerini kat

Varsayılan politika:

- Dahil et: adı `en` ile başlayan, `IFF_UP` ve `IFF_RUNNING` olan fiziksel
  Wi‑Fi/Ethernet arayüzleri.
- Hariç tut: `lo*`, `utun*`, `ipsec*`, `ppp*`, `bridge*`, `awdl*`, `llw*`,
  `ap*`, `p2p*`, `gif*`, `stf*`, `anpi*` ve diğer sanal/tünel arayüzleri.
- Aynı anda gerçekten trafik taşıyan Wi‑Fi ve Ethernet varsa her fiziksel
  arayüz kendi deltasıyla bir kez sayılabilir.
- VPN trafiğini `utun` üzerinden ayrıca ekleme. Altındaki `en*` trafiği zaten
  internet bağlantısındaki baytları temsil eder; VPN overhead'i fiziksel
  sayaçta doğal olarak bulunur.

Filtreyi saf bir fonksiyon yap ve unit test ile doğrula. İsim listesi UI
dosyalarına dağılmasın.

Eğer macOS API'sinden arayüz tipini güvenilir biçimde öğrenmek için mevcut
projede hazır bir abstraction varsa onu tekrar kullan. Yeni üçüncü taraf paket
ekleme. Sadece “en0 sabitle” yapma; Ethernet/adaptör değişimini bozma.

### C. Baseline'ı arayüz başına sakla

Payload yeni şemada şunu saklasın:

```swift
struct InterfaceBaseline: Codable, Equatable {
    var received: UInt64
    var sent: UInt64
}

var baselines: [String: InterfaceBaseline]
var schemaVersion: Int
```

Her örneklemede:

1. Yeni görülen arayüz: baseline kaydet, delta `0`.
2. `raw >= previous`: yalnız farkı ekle.
3. `raw < previous`: sayaç resetlenmiş say, yeni baseline kaydet, delta `0`.
4. Kaybolan arayüzün o turda deltası yok. Uzun süre kayıp baseline'ları güvenli
   biçimde temizle veya sonraki görünüşte sıçrama olmaması için yeniden baseline
   kuracak bir nesil/last-seen alanı kullan.
5. Download ve upload ayrı hesaplanıp bugünün ayrı alanlarına eklenmeye devam
   etsin.
6. `&+` ile overflow gizleme. Checked/saturating toplama kullan; taşma olursa
   veri bozulmasına izin verme ve debug log üret.

Hem anlık hız hem geçmiş aynı filtrelenmiş fiziksel örnek kaynağını kullansın.
`SystemStatsController.refreshNetwork()` ile `NetworkHistoryStore` farklı
arayüz kümeleri ölçmesin.

### D. Eski bozuk veriyi güvenli migrate et

Eski aggregate baseline yeni şemaya çevrilemez. İlk `schemaVersion < 2`
migrasyonunda:

- Eski `lastRawReceived` ve `lastRawSent` baseline'larını kullanma.
- Yeni uygun arayüzlerden baseline kur; ilk delta `0`.
- Bugünün kovasını temizle çünkü hangi kısmın sanal arayüz tekrar sayımı olduğu
  matematiksel olarak ayrılamaz.
- Önceki günleri otomatik silme. Ancak onların da eski algoritmadan geldiğini
  kabul et ve kullanıcıya Settings/Network içinde açık bir
  “Reset Network History…” seçeneği ekle.
- Reset destructive olduğu için confirmation dialog göster. Onaydan sonra
  `days`, baseline'lar ve widget snapshot ağ toplamları sıfırlansın; hemen yeni
  baseline kurulsun ve `WidgetCenter.shared.reloadAllTimelines()` çağrılsın.
- Reset sonrası uygulamayı yeniden başlatmak gerekmemeli.

Payload decode işlemi eski JSON'u okuyabilmeli. Migration atomik yazılsın;
uygulama ortada kapanırsa dosya yarım kalmamalı.

### E. Gün sınırını doğru ele al

Delta iki farklı güne yayıldıysa bütün aralığı yeni güne körlemesine yazma.
Örneklemenin normal aralığı 5 saniye olsa da sleep/wake sonrası uzun aralık
oluşabilir. En azından baseline sample zamanı persist edilsin ve gün değişimi
tespit edildiğinde:

- kesin dağılım bilinmiyorsa eski güne trafik uydurma;
- ilk yeni-gün örneğini baseline kabul et (`delta = 0`);
- sonraki örneklerden itibaren yeni güne say.

Bu tercih birkaç saniyeyi eksik sayabilir fakat gigabaytlarca yanlış eklemekten
daha güvenlidir.

## Test zorunlulukları

`NetworkHistoryStore` hesaplamasını saat, dosya URL'si ve arayüz örnekleri enjekte
edilebilir saf bir accumulator'a ayır. Gerçek `getifaddrs` çağrısını unit testte
kullanma.

En az şu regresyon testlerini ekle:

1. `en0` 100 MB artarken `utun0` aynı 100 MB artarsa toplam **100 MB**, 200 MB
   değil.
2. `awdl0`, `llw0`, `bridge0`, `utun157` artışları internet toplamına eklenmez.
3. İlk örnek yalnız baseline kurar ve Today `0` kalır.
4. Sayaç 500 MB'den 20 MB'ye düşerse 20 MB eklenmez; delta `0` olur.
5. `en0` kaybolup `en5` geldiğinde ilk `en5` örneği delta üretmez.
6. Uygulama kapanıp payload tekrar yüklendiğinde aynı arayüzün yalnız yeni
   deltası eklenir.
7. Gün değişiminden sonraki ilk örnek baseline kurar; dün ve bugün arasında
   dev delta oluşmaz.
8. Schema v1 fixture'ı decode edilir, bugün temizlenir, önceki günler korunur ve
   schema v2 atomik yazılır.
9. Reset işlemi tüm dönemleri ve widget snapshot ağ alanlarını sıfırlar.
10. `recordCurrentTraffic()` kısa aralıkla iki farklı tüketici tarafından
    çağrıldığında aynı baytlar iki kez yazılmaz.

## UI doğrulaması

- Panel, ana pencere, menü çubuğu ve widget aynı Today değerini göstermeli.
- Uygulama açıkken kontrollü bir indirme yap; artış dosya boyutuna yakın olmalı.
  Protokol/VPN overhead'i nedeniyle birebir eşitlik bekleme, fakat 2× veya daha
  büyük sapma olmamalı.
- VPN aç/kapatınca Today bir anda sıçramamalı.
- Sleep/wake ve uygulama restart sonrasında gigabaytlık ani artış olmamalı.
- Sistem widget cache'i için timeline reload sonrası değer güncellenmeli.

## Değiştirilecek temel dosyalar

- `Sources/Shared/SystemSampler.swift`
- `Sources/macOS/SystemMonitor/NetworkHistoryStore.swift`
- `Sources/macOS/SystemMonitor/SystemStatsController.swift`
- İlgili Settings bölümü (reset düğmesi için)
- Yeni/uygun test dosyaları

## Dokunulmaması gerekenler

- Speed Test'in gerçek veri kullandığı davranışı değiştirme.
- Process bazlı `nettop` listesini günlük toplamın kaynağı yapma; süreç listesi
  ile arayüz sayacı farklı amaçlara hizmet ediyor.
- Widget yenileme periyodunu gereksiz yere hızlandırma.
- Kullanıcının bütün geçmişini sessizce silme; yalnız kanıtlanmış bozuk “bugün”
  v1→v2 migrasyonunda temizlenebilir, tam reset açık onay ister.
- Hard-coded `en0` kullanma.
- Yeni bağımlılık ekleme.

## Çalıştırılacak kontroller

```bash
swift test
xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS \
  -configuration Debug \
  -derivedDataPath /private/tmp/glassdo-network-counter-fix build
```

Mevcut workspace'teki kullanıcı değişikliklerini koru. İlgisiz dosyaları
formatlama, yeniden adlandırma veya temizleme. İş bittiğinde değiştirilen
dosyaları, migrasyon davranışını ve test sonuçlarını kısa biçimde raporla.

## Tamamlanma ölçütü

- Fiziksel trafik sanal/VPN sayaçlarıyla tekrar sayılmıyor.
- Counter reset/interface değişimi sıçrama üretmiyor.
- Eski v1 bugünkü bozuk toplam güvenli biçimde temizleniyor.
- Kullanıcı onaylı tam geçmiş sıfırlama çalışıyor.
- Panel, menü çubuğu, ana pencere ve widget aynı doğru toplamı kullanıyor.
- Yukarıdaki regresyon testleri ve macOS build başarılı.
