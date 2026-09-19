# 009 — macOS Productivity Pro Özellikleri

> Amaç: GlassDo'yu sıradan bir görev listesinden, Mac'te günlük işi yöneten
> bir çalışma kontrol merkezine taşımak. Bu belge, implementasyon için Claude
> Sonnet'e doğrudan verilebilecek teknik görev tanımıdır.
>
> Kapsam: yalnızca macOS, Swift 6 + SwiftUI + AppKit + SwiftData. Mevcut
> mimariyi ve Liquid Glass tasarım sistemini koru. Ağ servisi, kullanıcı hesabı,
> iCloud sync, AI, yeni üçüncü taraf paket ve ücret sistemi bu işin kapsamı
> dışındadır.

## Ürün kararı ve uygulama sırası

Bu beş özellik tek PR'da yapılmamalı. Her aşama derlenebilir, test edilebilir ve
tek başına kullanılabilir olmalı.

1. **Görev yapısı:** alt görevler, tekrar ve doğal dil ile hızlı giriş.
2. **Görev bağlamı:** dosya/klasör/ekran görüntüsü/clipboard girdisini göreve
   iliştirme.
3. **Focus Session:** bir göreve zaman ayırma ve yerel geçmiş.
4. **Bağlama duyarlı Edge Rail:** odaktaki uygulama ile eşleşen görevleri öne
   çıkarma.
5. **Çalışma alanları (workspaces):** yukarıdaki yetenekleri kullanıcı tipi
   veya proje akışına göre hazır düzenlere dönüştürme.

Her aşamadan önce mevcut çalışma ağacını koru; ilgisiz dosyaları yeniden
biçimlendirme. `project.yml` yalnızca gerçekten yeni source dosyası target'a
dahil edilmiyorsa değiştirilsin.

## Ortak teknik kurallar

- Kalıcı domain modelleri `Sources/GlassDoKit/Models` altında `@Model` olarak
  bulunmalı ve `AppStore.makeContainer` şemasına eklenmeli.
- SwiftData'ya yazma sadece `@MainActor` üzerinde yapılmalı. UI, mevcut
  `@Query` + `modelContext` kalıbını sürdürmeli.
- Yeni her kalıcı alanda makul bir varsayılan veya optional değer kullanılmalı;
  eski yerel veriler açıldığında migration/crash olmamalı.
- Kullanıcı seçtiği dosya/klasör dışında disk taraması yapma. Dosya bağlantısı
  yalnızca bookmark ve görüntülenecek metadata tutar; dosyanın kendisini
  kopyalayıp gizlice arşivlemez.
- İzin gerektiren özelliklerde önce sistem izni iste, reddedilince sade ama
  işlevsel fallback göster. İzin reddi uygulamanın normal görev akışını
  bozmasın.
- Tüm yeni kullanıcı metinlerini `L10n` üzerinden Türkçe, İngilizce ve Rusça
  ekle.
- Reduce Motion açıkken yay/scale animasyonlarını kapat veya sade opacity ile
  değiştir. VoiceOver etiketlerini ekle.
- Her aşama sonunda ilgili Swift Testing testlerini ekle/çalıştır; ardından
  `xcodegen generate` ve Debug build yap. Build hatalarını gizleme.

---

## Aşama 1 — Gelişmiş görev yapısı ve hızlı giriş

### Kullanıcı değeri

Kullanıcı bir işi tek satır yerine yönetilebilir parçalara ayırır; periyodik
işleri tekrar yazmaz; hızlı ekleme alanına `Yarın 15:00 faturayı gönder` yazar
ve tarih otomatik çıkarılır. Bu temel olmadan Focus ve context özellikleri
güçlü bir görev sistemine oturmaz.

### V1 kapsamı

1. **Alt görevler**
   - Bir görev en fazla bir üst göreve sahip olur (`parentTask`).
   - Ana görev ayrıntısında alt görev listesi gösterilir; ekle, düzenle,
     sırala, tamamla ve sil desteklenir.
   - Alt görevler ana listeye bağımsız satır olarak düşmez.
   - Ana görev satırında `tamamlanan / toplam` ilerleme bilgisi görünür.
   - Tüm alt görevler tamamlanınca ana görevi otomatik tamamlamak yerine
     kullanıcıya tek tıkla "Ana görevi tamamla" eylemi sun. Bu daha güvenli
     ve geri alınabilir davranıştır.

2. **Tekrarlayan görevler**
   - V1 yalnızca: her gün, her hafta, her ay ve seçilmiş hafta günleri.
   - Bir görevin `recurrenceRule` alanı boş olabilir. Bunun için küçük,
     Codable/Sendable bir değer tipi kullan; RRULE parser veya EventKit
     bağımlılığı ekleme.
   - Tekrarlayan görev tamamlanınca mevcut kaydı geçmiş olarak tamamla ve
     bir sonraki zaman için aynı özelliklerle yeni bir görev oluştur.
   - Geçmişte birden fazla tekrar üretme: uygulama açılışında/foreground'a
     gelince yalnızca gereken **tek** sonraki örneği üret.
   - Tarihi olmayan göreve tekrar ayarı açılamaz; kullanıcı önce başlangıç
     tarihi seçer.

3. **Doğal dil hızlı giriş**
   - Yeni küçük, saf ve test edilebilir bir parser ekle. Parser SwiftUI veya
     SwiftData import etmesin.
   - Türkçe V1 örnekleri: `yarın`, `bugün`, `pazartesi`, `saat 15:00`,
     `15:00`, `#etiket`, `!yüksek` / `!orta` / `!düşük`.
   - İngilizce/Rusça ifadeleri bu aşamada zorunlu değil; mevcut arayüz dili
     Türkçe dışındaysa kullanıcı normal başlık ile ekleme yapabilir.
   - Parser sonucu `title`, opsiyonel `dueDate`, `priority`, `tagNames` olsun.
     Tanınmayan kelimeler başlıkta kalır. Yanlış tahmin yerine hiçbir şeyi
     kaybetmemek önceliktir.
   - Panel Quick Add ve ana pencere Quick Add aynı parser/oluşturma servisini
     kullanmalı.

### Model taslağı

`Task`a geriye uyumlu alanlar ekle:

```swift
public var notes: String = ""
public var dueDate: Date?
public var priorityRaw: String = Priority.none.rawValue
public var recurrenceData: Data?
@Relationship(inverse: \Task.subtasks) public var parentTask: Task?
public var subtasks: [Task]? = []
```

Gerçek implementasyonda `Priority` ve `RecurrenceRule` tipi ayrı dosyalarda
olmalı. Self-referential SwiftData ilişkisinin migration ve inverse davranışını
in-memory testle doğrula.

### Arayüz yerleşimi

- Ana pencere: `TaskRow` kısa ilerleme rozeti gösterir. Satıra çift tıklama
  veya mevcut seçme akışı görev ayrıntı görünümünü açar.
- Edge Rail: ana satır düzenini kalabalıklaştırma; yalnızca alt görev varsa
  küçük bir ilerleme rozeti göster.
- Hızlı eklemede parser ile anlaşılan tarih/öncelik, Enter öncesinde küçük
  düzenlenebilir chip olarak görünür. Bu chip kaldırılırsa alan temizlenir.

### Kabul kriterleri

- Alt görev ekleme/silme/tamamlama yeniden başlatma sonrası korunur.
- Alt görevler aktif görev ana listesinde ayrı görünmez.
- "Her pazartesi" görevi tamamlanınca yalnızca takip eden pazartesi için
  yeni aktif görev oluşur.
- `yarın 15:00 teklif gönder !yüksek` girişi doğru başlık, tarih/saat ve
  yüksek öncelikle kaydedilir; tanınmayan metin kaybolmaz.
- En az parser, recurrence next-date ve parent/child ilişkisinin davranışını
  kanıtlayan unit testler vardır.

### Açıkça kapsam dışı

Takvim event senkronu, karmaşık RRULE, bağımlılıklar, çok seviyeli proje
şablonları, AI tarih anlama ve push notification.

---

## Aşama 2 — Göreve dosya, ekran görüntüsü ve clipboard bağlama

### Kullanıcı değeri

"Vergi beyanı" görevi, ilgili PDF, Finder klasörü, ekran görüntüsü ve
kopyalanmış referans metniyle birlikte yaşar. Kullanıcı işi aramak yerine
görevin içinden bağlamına döner.

### V1 kapsamı

- `TaskAttachment` adlı ayrı SwiftData modeli oluştur. Türler: `file`,
  `folder`, `screenshot`, `clipboardText`.
- Her attachment: UUID, displayName, typeRaw, createdAt, optional bookmark
  data, optional local copied-text değeri, optional thumbnail path tutar.
- Görev detayında "Bağlam" bölümü: Finder'dan sürükle-bırak, dosya seçici,
  Shelf'ten ekle, Clipboard geçmişinden metin ekle, kaldır ve Finder'da aç.
- `file`/`folder` için security-scoped bookmark üret; açılırken resolve et,
  stale bookmark varsa "Dosyayı yeniden seç" eylemi göster.
- Shelf dosyası eklenirken **taşınmaz ve kopyalanmaz**; Shelf'in mevcut
  yönetilen URL'sine bookmark yapılır.
- Clipboard görselini V1'de doğrudan attachment yapma. Kullanıcı önce Shelf'e
  veya dosyaya kaydetsin. Bu, veri yaşam döngüsünü net tutar.
- Bir görevde en fazla 30 attachment; aynı dosyanın aynı göreve ikinci kez
  eklenmesini canonical URL veya bookmark çözümü ile engelle.

### Entegrasyon noktaları

- Mevcut `ManagedStorageService`, `PanelShelfView`, `ClipboardHistoryStore`
  ve `ThumbnailProvider` yeniden kullanılmalı; paralel ikinci bir dosya
  deposu yaratma.
- Attachment listesi ana pencere görev ayrıntısında tam görünür. Edge Rail
  yalnızca ataşman sayısı rozetini ve ilk üçüne hızlı açma menüsünü gösterir.
- Silme, yalnızca ilişkiyi siler; kullanıcının dosyasını veya Shelf dosyasını
  silmez.

### Kabul kriterleri

- Finder'dan bir PDF eklenir, uygulama kapatılıp açıldıktan sonra Finder'da
  tekrar açılabilir.
- Shelf'ten eklenen dosya Shelf'te kalır.
- Stale/erişilemeyen bookmark crash oluşturmaz ve yeniden bağlama yolu sunar.
- Attachment'ı görevden kaldırmak fiziksel dosyayı silmez.

### Açıkça kapsam dışı

Dosya içeriğinde arama, cloud upload, OCR, önizleme editörü, sınırsız medya
arşivi ve paylaşılmış attachment'lar.

---

## Aşama 3 — Focus Session

### Kullanıcı değeri

Kullanıcı bir görevi seçip odak oturumu başlatır; Edge Rail'den kalan süreyi
görür ve gün sonunda neye zaman ayırdığını anlar. Bu bir Pomodoro klonu değil,
göreve bağlı sakin bir çalışma modu olmalı.

### V1 kapsamı

- `FocusSession` modeli: id, task, startedAt, endedAt?, plannedDurationMinutes,
  endedReason (`completed`, `stopped`, `expired`).
- Süre seçenekleri 25, 50 ve 90 dakika; özel süre yok.
- Bir anda yalnızca bir aktif oturum. Uygulama yeniden açıldığında aktif oturum
  `startedAt` üzerinden doğru kalan zamanı hesaplar; arka planda sürekli timer
  saklama.
- Başlatma: görev satırı context menu, görev detayındaki buton ve Edge Rail.
- Aktif oturum görünümü: görev başlığı, kalan süre, durdur, tamamla. Edge
  Rail'in üst kısmında kompakt durum görünür; paneli zorla açma veya uygulamayı
  öne getirme.
- Süre biterse yerel macOS bildirimi için izin iste; izin yoksa uygulama
  içindeki durum bitmiş görünür.
- Basit geçmiş: bugün ve son 7 gün toplam dakika, görev başına toplam. Bu
  veriyi sistem monitörü grafiklerine karıştırma; ayrı Focus sayfası yeterli.

### Kabul kriterleri

- Uygulama kapanıp açıldığında aktif seansın kalan süresi doğru olur.
- İkinci seans başlatmak mevcut oturumu kullanıcı onayı olmadan kapatmaz.
- Seansı bitirmek ilişkilendirilmiş görevi otomatik tamamlamaz; "Görevi de
  tamamla" ayrı ve isteğe bağlı eylemdir.
- Süresi biten seans tek kez tamamlanır ve geçmişte doğru dakika görünür.

### Açıkça kapsam dışı

Web sitesi engelleme, uygulama gizleme, müzik, cross-device timer, takvimde
otomatik blok oluşturma ve hedef/rozet gamification.

---

## Aşama 4 — Bağlama duyarlı Edge Rail

### Kullanıcı değeri

Xcode odaktayken geliştirme görevleri, Figma odaktayken tasarım görevleri
öne çıkar. Kullanıcı manuel liste aramaz; ancak uygulama onun adına görev
tamamlama veya pencere kontrolü yapmaz.

### Gizlilik ve izin kararı

Aktif uygulamanın bundle ID'sini alma için ilk olarak `NSWorkspace` kullan.
Bu yöntem yeterliyse Accessibility izni isteme. Pencere başlığı, URL, yazılan
metin veya ekran içeriği **asla** okunmayacak/kaydedilmeyecek.

### V1 kapsamı

- `AppContextRule` modeli: id, `bundleIdentifier`, displayName?, task veya
  project ilişkisi, isEnabled. Bir kural bir uygulamayı bir göreve **veya**
  projeye bağlar.
- Kullanıcı bir görev/proje için "Bu uygulama açıkken öne çıkar" eylemiyle
  seçili uygulamalarından kural oluşturur. Serbest bundle ID metin alanı
  verme; yüklü/çalışan uygulama listesi ile sınırlı tut.
- `ActiveApplicationMonitor` tek bir merkezi `@MainActor @Observable` servis
  olur. `NSWorkspace.didActivateApplicationNotification` dinler; polling
  yapmaz. Servis yalnızca aktif bundle ID ve uygulama adını bellekte tutar.
- Eşleşme varsa Edge Rail görevler görünümünün en üstünde en fazla 3 öneri
  göster. Aynı görev zaten listede ise iki kez gösterme.
- Birden fazla kural eşleşirse doğrudan göreve bağlı olanlar, proje kuralından
  önce gelir; sonra `sortIndex` kullanılır.
- Kullanıcı ayarlardan özelliği kapatabilir; kapalıyken monitor kaydolmaz ve
  aktif uygulama bilgisi saklanmaz.

### Kabul kriterleri

- Xcode'a geçince Xcode ile eşleşen görevler Edge Rail'de bir sonraki UI
güncellemesinde görünür; başka uygulamaya geçince kaybolur.
- Kural silinince öneri anında kalkar ve görev silinmez.
- Özellik kapalıyken active-app monitor çalışmaz.
- Aktif uygulamanın yalnızca bundle ID/adı tutulduğunu, URL/pencere başlığı
okunmadığını kod yapısı açıkça gösterir.

### Açıkça kapsam dışı

Otomatik görev oluşturma, app usage analytics, website tab algılama, uygulama
başlatma/kapatma, Accessibility API ile pencere manipülasyonu.

---

## Aşama 5 — Hazır çalışma alanları (Workspaces)

### Kullanıcı değeri

Yeni kullanıcı boş listeyle başlamaz: Developer, Freelancer, Student ve
Creator çalışma alanlarından birini seçer; doğru etiketler, projeler ve panel
varsayılanları gelir. Bu, onboarding ve Pro paketinin anlaşılmasını güçlendirir.

### V1 kapsamı

- İlk açılışta ve Ayarlar > Workspaces altında dört yerel şablon göster:
  `Developer`, `Freelancer`, `Student`, `Creator`.
- Şablon veri modeline yazılmaz; uygulama içinde sabit tanım (`WorkspaceTemplate`)
  olarak tutulur. Kullanıcı uyguladığında yalnızca seçtiği varlıklar SwiftData'ya
  kopyalanır.
- Her şablon: 2–4 proje, 4–8 etiket, önerilen Edge Rail başlangıç sekmesi ve
  örnek üç görev içerir. Örnek görevler belirgin şekilde "Örnek — ..." diye
  işaretlenir; kullanıcı isterse onboarding sonunda tek eylemle silebilir.
- Şablon uygulamak mevcut veriyi silmez. Önizlemede eklenecek proje/etiket/
  görev sayısı görünür; kullanıcı onaylar.
- Aynı şablon ikinci kez uygulanırsa aynı adlı proje/etiketi yeniden üretme;
  mevcut olanı kullan, yalnızca eksik örnekleri ekle. Bu davranışı test et.
- "Boş başla" seçeneği her zaman eşit görünürlükte olsun; kullanıcıyı şablona
  zorlayan veya Pro paywall açan bir akış yaratma.

### Kabul kriterleri

- Yeni kullanıcı bir şablonu uygulayıp görev listesini ve Edge Rail'i hemen
  kullanabilir.
- Şablon uygulama mevcut görevleri/projeleri silmez veya yeniden sıralamaz.
- Aynı şablonu iki kez uygulamak duplicate proje/etiket oluşturmaz.
- Onboarding'i atlayan kullanıcı Ayarlar'dan aynı özelliğe erişir.

### Açıkça kapsam dışı

Kullanıcının kendi şablonunu kaydetmesi, şablon marketplace'i, dışa aktarma,
bulut senkronu ve ekip paylaşımlı workspace.

---

## Son doğrulama ve teslim

1. `xcodegen generate` çalıştır.
2. `xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug build` ile derle.
3. İlgili `GlassDoKitTests` testlerini çalıştır.
4. Manuel smoke test: yeni görev → alt görev → tekrar → attachment → focus
   → aktif uygulama önerisi → workspace uygulama akışını sırayla dene.
5. Çalışma ağacındaki bu iş dışı değişiklikleri açıklama veya geri alma.

Teslim cevabında yalnızca değişen dosyalar, test/build sonucu, tasarımda alınan
önemli kararlar ve bilinen eksik/izleyen iş maddeleri listelenmeli.

## Sonnet'e verilecek kısa başlangıç mesajı

```text
plans/009-macos-productivity-pro-features.md dosyasını baştan sona oku ve
uygula. Önce mevcut SwiftData modellerini, AppStore şemasını, TaskListView,
PanelTaskListView, ManagedStorageService ve EdgePanel akışını incele. Aşamaları
sırayla, ayrı ve derlenebilir değişiklikler olarak uygula; her aşamada ilgili
testleri ekle/çalıştır. Dokümandaki kapsam dışı maddeleri ekleme. Mevcut
kullanıcı değişikliklerini koru, ilgisiz dosyaları düzenleme. Bir kararda
belirsizlik varsa en dar, yerel ve geri alınabilir seçeneği al; sonucu raporla.
```
