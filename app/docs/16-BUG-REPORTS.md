# 16 — Hata Bildirimi: Toplama, Belge Biçimi ve Çözüm Akışı

> Güncellik: 2026-09-21
>
> Menü çubuğundaki **Hata Bildir…** maddesinin ne topladığı, Firestore'da
> nasıl durduğu ve gelen bir raporu çözmek için izlenen yol.

## Kod

| Dosya | Görev |
|---|---|
| `Sources/macOS/Support/BugReport.swift` | `BugArea`, `BugSeverity`, `BugDiagnostics` (tanılama toplama) |
| `Sources/macOS/Support/BugReportService.swift` | Firestore `user_bugs` yazımı, belge biçimi |
| `Sources/macOS/Support/BugReportView.swift` | Form penceresi |
| `Sources/macOS/App/GlassDoApp.swift` | Menü maddesi + `id: "bug-report"` pencere sahnesi |

Firestore SDK'sı uygulamada zaten bağlı (`DeviceAnalyticsService`), yeni bir
bağımlılık eklenmedi.

Pencere kasıtlı olarak dialog: sabit 460 pt genişlik, kaydırma yok, dört
alan (nerede · ne kadar kötü · ne oldu · nasıl tekrarlanıyor) + isteğe
bağlı e-posta. Tek satırlık özet ayrıca sorulmuyor — açıklamanın ilk satırı
`summary` olarak kaydediliyor. Önem seçimi için renkli rozetler denendi ve
geri alındı: sabit genişlikte etiketler iki satıra kırılıyor, seçili rozet
de dialogdaki tek doygun renk olarak gözü asıl alandan çekiyordu; sistemin
kendi açılır menüsü kırpılmıyor ve sessiz kalıyor.

## Belge biçimi — `user_bugs/{reportID}`

`devices` koleksiyonu cihaz başına **tek** ve üzerine yazılan bir belge;
hata raporu ise olay başına bir kayıt ve asla ezilmemeli. Bu yüzden ayrı
koleksiyon. `deviceID` alanı ikisini bağlıyor: bir raporu açıp o cihazın
kullanım geçmişine geçebiliyoruz.

```
user_bugs/{autoID}
  reportID            "oW3…"      belge kendi kimliğini de taşıyor (dışa aktarımda kaybolmasın)
  schemaVersion       1           biçim değişince artar; panel eski raporları tanıyabilsin
  deviceID            UUID        DeviceAnalyticsService ile aynı anonim kimlik

  # Kullanıcının anlattığı kısım
  area                "panel"     BugArea raw
  areaTitle           "Kenar Paneli / Ray"
  sourceHint          "Sources/macOS/Panel"    ilk bakılacak klasör
  severity            "crash" | "blocking" | "annoying" | "cosmetic"
  summary             açıklamanın ilk satırı (liste görünümünde başlık; ayrıca sorulmuyor)
  details             zorunlu — boşsa gönderilmiyor
  steps               tekrarlama adımları (boş olabilir)
  contact             kullanıcı yazdıysa (boş olabilir)

  # Zaman — iki biçimde
  createdAt           serverTimestamp   sıralamanın tek güvenilir kaynağı
  reportedAtLocal     ISO8601           "sabah 9'da oldu" ifadesini doğrulamak için
  timeZone            "Europe/Istanbul"

  # İş akışı (varsayılanları istemci yazıyor, panel eksik alanla uğraşmasın)
  status              "new"
  triage              { priority, assignee, notes, resolution, duplicateOf }

  # Tanılama (kullanıcı anahtarı kapatırsa yalnızca app.version/build gider)
  diagnosticsIncluded true|false
  app                 { version, build, sandboxed, isPro }
  system              { osVersion, deviceModel, architecture, cpuCores, memoryGB,
                        locale, language, region, screens[], uptimeHours }
  state               { panelMode, panelEdge, panelVisible, analyticsConsent }
  usageToday          { "tasks": 12, "clipboard": 3, … }
```

**Neden bu alanlar:** her biri daha önce gerçekten ayırt edici olmuş bir
şey. `sandboxed` — pencere kapatma hatası yalnızca Release/sandbox
yapısında çıkıyordu (bkz. `13bc0aa`). `panelEdge` + `screens` — kenar
paneli hatalarının çoğu belirli bir kenar/ölçek birleşiminde. `usageToday`
— hatanın hangi akışın içinde doğduğunu daraltıyor. `isPro` — Pro'ya kapalı
bir yolun yanlış davranması.

**Toplanmayan:** görev başlığı, dosya adı, pano içeriği, not metni, IP,
isim, konum. Tanılama anahtarı kapatılırsa sürüm/yapı dışında hiçbir teknik
alan gitmiyor ve `diagnosticsIncluded: false` yazılıyor — gizlilik notu
dürüst kalsın.

Tanılama **pencere açılırken** bir kez toplanıyor, gönderme anında değil:
kullanıcı formu doldururken paneli kapatmışsa hatanın görüldüğü durumu
değil, sonrasını kaydetmiş olurduk.

## Firestore güvenlik kuralı

Rapor yazmak herkese açık, okumak yalnızca yönetim tarafına. Kurallar
repoda tutulmuyor (konsoldan yönetiliyor); eklenmesi gereken blok:

```
match /user_bugs/{reportID} {
  // İstemci yalnızca yeni rapor oluşturur: güncelleme/silme yok,
  // böylece gönderilmiş bir rapor sonradan değiştirilemez.
  allow create: if request.resource.data.details is string
                && request.resource.data.details.size() > 0
                && request.resource.data.details.size() < 5000
                && request.resource.data.status == 'new';
  allow read, update, delete: if false;   // yönetim paneli Admin SDK ile okur
}
```

`update`'in kapalı olması `triage` alanlarının konsoldan/Admin SDK'dan
değiştirilmesini engellemiyor — Admin SDK kuralları atlar.

## Gelen bir raporu çözme akışı

1. **Sırala.** `severity == "crash"` olanlar önce; sonra aynı `area` +
   yakın `app.version` altında kümelen. Aynı hatayı bildiren cihaz sayısı
   (`deviceID` tekilleri) önceliği belirliyor — tek cihazda görülen bir
   görsel kusur, üç cihazda görülen bir çökmenin önüne geçmiyor.
2. **Tekrarla.** `steps` + `state` + `system`'i aynen kur: aynı panel
   kenarı, aynı mod, `sandboxed: true` ise **Release** yapısıyla dene —
   Debug'da sandbox kapalı olduğu için hatanın yarısı Debug'da hiç
   görünmüyor.
3. **Daralt.** `sourceHint` ilk bakılacak klasörü veriyor. `usageToday`
   hangi akışın sıcak olduğunu söylüyor.
4. **Testle sabitle.** Davranış `Sources/Shared`, `Sources/macOS/Usage`
   ya da `Sources/macOS/Storage` altındaysa `Tests/GlassDoKitTests`'e
   önce başarısız olan bir test yaz; UI katmanındaysa düzeltmeyi elle
   doğrula ve sebebi kodun yanına yorum olarak yaz.
5. **Kapat.** `triage.resolution`'a düzeltmenin girdiği sürümü, kopya
   raporlara `triage.duplicateOf`'a asıl raporun kimliğini yaz,
   `status`'ü `fixed` / `wontfix` / `cannotReproduce` yap.
6. **Haber ver.** `contact` doluysa yalnızca o hata hakkında yaz. Boşsa
   kullanıcı sürüm notundan görecek; rapor kimliği kendisinde duruyor
   (pencere gönderimden sonra kopyalanabilir biçimde gösteriyor).

## Sonraki adımlar (henüz yapılmadı)

- **Yönetim paneli listesi.** `website/app/admin/` içinde `user_bugs`
  görünümü: alan/önem/sürüm süzgeçleri, cihaz sayısına göre kümeleme.
  Şimdilik raporlar Firebase konsolundan okunuyor.
- **Kendiliğinden kopya tespiti.** `area` + normalize edilmiş `summary`
  üzerinden benzerlik; şimdilik elle.
- **Çökme izi.** Gerçek bir çökmeden *sonra* açılışta iz eklemek için
  ayrı bir çökme yakalayıcı gerekiyor; bu form yalnızca kullanıcının
  elle bildirdiğini taşıyor.
- **Ekran görüntüsü.** Firebase Storage eklenmesi gerekiyor (şu an
  bağımlılıkta yok) — görsel kusurlarda en çok işe yarayacak eklenti.
