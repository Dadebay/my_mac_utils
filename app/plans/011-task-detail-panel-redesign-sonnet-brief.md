# 011 — Task detail panelini sakin ve yerel hissettirecek şekilde yeniden tasarla

- **Durum**: Sonnet 5'e verilmeye hazır uygulama brief'i
- **Referans commit**: `51ab82c`
- **Kapsam**: `Sources/macOS/MainWindow/TaskDetailView.swift`; yalnızca gerçekten gerekirse, bu ekranın kullandığı `Sources/macOS/DesignSystem/FormCard.swift`
- **Görsel referans**: Kullanıcının eklediği `Screenshot 2026-09-02 at 14.48.21.png`

## Sonnet 5 için komut

```text
Bu görevi kıdemli bir macOS SwiftUI tasarım mühendisi olarak uygula. Önce
`apple-design` ve `improve-animations` becerilerinin yönergelerini oku; sonra
yalnızca aşağıdaki kapsamda kod değiştir, derle ve test et.

## Ürün ve bağlam

GlassDo, macOS 26 için yerel bir görev yöneticisi. Ana pencerenin yanında
Liquid Glass kullanan dar bir Edge Rail paneli var. `TaskDetailView`, bu
panelde `.panelInline` olarak açılabiliyor; aynı view ana pencerede sheet olarak
da açılıyor. Ekteki ekran görüntüsü panel içindeki task-detail görünümünü
gösteriyor. Şu an işlevler mevcut fakat görünüm “birkaç rastgele form kartı ve
tek başına mavi Start düğmesi” gibi hissediyor: hiyerarşi zayıf, boş notes alanı
gereğinden fazla yer kaplıyor, kontrollerin ağırlığı dengeli değil ve küçük
yardımcı eylemler yeterince kasıtlı görünmüyor.

Amaç, Apple Reminders / System Settings kadar sakin, okunaklı ve güven veren
bir görev ayrıntı yüzeyi yapmak. Bu bir web dashboard'u veya neon/cyberpunk
tasarım değildir. Mevcut gerçek Liquid Glass panelinin üstüne sahte blur,
gradient, glow ya da her elemana ayrı cam kart ekleme.

## İncelenecek mevcut kod

- `Sources/macOS/MainWindow/TaskDetailView.swift`
  - panel/sheet başlığı: yaklaşık satır 121
  - başlık ve notes: yaklaşık satır 202
  - Details, Due date, Priority, Repeat: yaklaşık satır 241
  - Focus Session: yaklaşık satır 366
  - Subtasks: yaklaşık satır 450
  - Context ekleme menüsü: yaklaşık satır 566
- `Sources/macOS/DesignSystem/FormCard.swift`
- `Sources/GlassDoKit/DesignSystem/Tokens.swift`
- Sağlam icon-only Menu örneği: `Sources/macOS/Panel/PanelFolderShelfView.swift`

`TaskDetailView`deki bağlar, importer/sheet'ler, SwiftData kayıtları ve
localization anahtarları çalışıyor. Bunları yeniden yazma veya yeni bağımlılık
ekleme.

## Tasarım yönü — uygulanacak kararlar

1. **Tek, açık hiyerarşi kur.**
   - Başlık editörü sayfanın tek belirgin başlığı olsun; panel genişliğinde
     doğal biçimde 1–3 satırda akabilsin. Büyük başlık için yaklaşık 21–23 pt,
     bold, sıkı leading/tracking kullan; body ve meta yazılarını bununla
     yarışacak kadar büyük/koyu yapma.
   - Header yalnızca yön bulma ve görev durumuna hizmet etsin: geri düğmesi,
     tamamlanma dairesi, kısaltılmış görev adı. Header'da ikinci bir “hero”
     yaratma.
   - `Notes` alanı boşken sessiz bir düzenleme daveti olsun; boş bir gri blok
     gibi sayfayı yutmasın. Minimum yüksekliği yaklaşık 52–56 pt tut, odak
     alınca veya içerik büyüyünce rahatça genişlesin. Placeholder tıklamayı
     engellemesin; `TextEditor` hâlâ gerçek erişilebilir editör olsun.

2. **Kartları grup için kullan, dekorasyon için değil.**
   - Details, Focus Session, Subtasks ve Context ayrı iş grupları olarak
     kalsın. Her satıra yeni rounded rectangle, ağır shadow veya ikinci bir
     blur verme.
   - Panelin kendisi zaten cam katmanıdır; kartların yüzeyi hafif, tek katmanlı
     ve okunur olmalı. Mevcut `FormCard` dili temel alınabilir. Bir iyileştirme
     gerekiyorsa sadece opt-in bir Task Detail varyantı ekle; Settings ve diğer
     ekranların görünümünü kazara değiştirecek global restyle yapma.
   - Kart içi yatay hizayı tutarlı yap: leading icon + başlık solda, değer veya
     control trailing'de; row yüksekliği ve divider'lar eşit ritim taşısın.
     Sekmelerin büyük, havada duran bileşenler gibi görünmesine izin verme.

3. **Details alanını taranabilir bir ayar grubu yap.**
   - Due date ve Repeat gerçek macOS switch olarak kalmalı:
     `.toggleStyle(.switch)` ve `.controlSize(.small)` korunmalı. Bunları
     checkbox'a veya boş kare görünümüne geri döndürme.
   - Switch için label solda, switch trailing'de; açıldığında tarih seçiciyi
     doğrudan ilgili row'un altında, hafif insetli ve görsel olarak bağlı
     göster. Due date kapatılınca recurrence'ın temizlenmesi korunmalı.
   - Priority satırında flag, label ve seçilmiş değer arasında net bir ilişki
     kur. Mevcut menu picker kalabilir; seçilmiş değer en az ~116 pt okunur bir
     hit area içinde trailing'e hizalansın. Kullanılabiliyorsa priority'nin
     semantik rengi yalnızca küçük bir nokta/flag accent'i olarak kullan;
     tüm satırı renkli bir pill yapma.
   - Weekly weekday seçiminde 7 küçük kontrol aynı ölçü ve basılabilir alana
     sahip olsun. Seçili durum accent color ile açıkça ayırt edilsin; seçili
     olmayanlar panel zemininden bir kademe ayrışsın.

4. **Focus Session'ı birincil eylem olarak toparla.**
   - Süre segmented control'ü kart genişliğini dengeli kullansın; 25m/50m/90m
     seçenekleri eşit ve 44 pt civarı rahat bir kontrol bandı gibi okunsun.
   - `Start` düğmesi controlün altına, kartın tam genişliğinde ve açıkça
     birincil eylem olarak yerleşsin. Ekran görüntüsündeki küçük, ortada tek
     başına duran mavi düğme görünümünü kaldır.
   - Aktif oturumdaki timer en güçlü bilgi, Stop ikincil, Complete birincil
     eylem olmalı. Mevcut iş mantığını ve “complete task too” seçeneğini
     koru; sadece hiyerarşi/hizalamayı düzelt.

5. **Subtasks ve Context'i boş durumlarıyla birlikte tasarla.**
   - “Add subtask…” satırını gerçek bir ekleme alanı gibi hissettir: plus
     ikonu, placeholder ve text field aynı hizalı, tam satırda rahatça
     tıklanabilir olsun. Enter ile ekleme, mevcut sıralama, tamamla/sil
     davranışları korunmalı.
   - Context boş durumunda kısa, sakin bir açıklama ve header'daki ekleme
     eylemi yeterli; yeni CTA kartı veya büyük empty-state illüstrasyonu ekleme.
   - Context `+` menüsü kritik: yalnızca icon görünmeli, ekstra chevron
     görünmemeli ve tıklama alanı küçük SF Symbol'e daralmamalı. Label içinde
     açık bir `frame(width: 28, height: 28)` + `contentShape(Rectangle())`,
     dışta aynı sabit frame, `.menuStyle(.borderlessButton)` ve
     `.menuIndicator(.hidden)` kullan. Tooltip/accessibility label ekle.
     Ekrandaki önceki hit-testing düzeltmesini bozma.

6. **Tipografi, boşluk ve erişilebilirlik.**
   - Sistem fontu kullan. Section başlıkları yaklaşık 11 pt semibold ve hafif
     pozitif tracking ile meta bilgi olarak kalmalı; başlık/body için sabit
     `kerning` kopyalama.
   - İçerik ritmi: section'lar arası yaklaşık 20–24 pt, kart satırları 36–44
     pt hissi, card içi yatay padding 12–14 pt. Değerleri körü körüne uygula
     deme; panelde optik olarak eşit görünmelerini hedefle.
   - Dynamic Type, VoiceOver label'ları, klavye ile tab/focus ve düşük
     kontrastta okunurluk bozulmamalı. Sadece renge dayalı anlam verme.

## Motion kuralları

- Motion dekorasyon değil, state değişimini açıklamak içindir. Zaten mevcut
  `Motion` tokenlarını (`Sources/GlassDoKit/DesignSystem/Tokens.swift`) önce
  tercih et; neredeyse aynı yeni easing/duration tokenları icat etme.
- Due date/Repeat açıldığında bağlı alan `opacity + scale(0.97, anchor: .top)`
  ile yaklaşık 180–220 ms içinde, overshoot olmadan ortaya çıksın. Kapanış aynı
  mekânsal yolu tersine izlesin. `ease-in` kullanma.
- Focus idle ↔ active, subtask/attachment ekleme ve silme: yalnızca opacity ve
  transform/scale animate et; `frame`, `width`, `height`, padding veya
  `transition: all` benzeri layout animasyonları kullanma.
- Sık yapılan checkbox, gün ve küçük icon-button eylemleri anında basılma
  geri bildirimi alsın: mevcut `PressScaleButtonStyle` benzeri 100–160 ms,
  yaklaşık `scale(0.97)` yeterli. Büyük bounce, stagger, sürekli animasyon,
  confetti veya zamanlayıcıyla akan dekoratif efekt ekleme.
- `accessibilityReduceMotion` true iken positional/scale hareketini kaldır;
  kısa opacity ve renk feedback'i kalsın. Kullanıcı hareket sürerken input'u
  kilitleme.

## Kesin sınırlar

- Sadece task-detail deneyimini iyileştir. Edge Panel chrome, app arka planı,
  modeller, servisler, importer akışı, menü seçenekleri, persistence ve
  localization anahtarları kapsam dışıdır.
- Yeni paket, custom AppKit control, network çağrısı veya sahte glass/blur
  implementasyonu ekleme.
- Ekranı daha “tasarlanmış” göstermek için gereksiz border, shadow, pill,
  gradient veya mavi accent çoğaltma. Accent yalnızca gerçek selection ve
  primary action için kullanılmalı.
- Belirsizlik varsa geniş çaplı refactor yapma; küçük, yerel SwiftUI
  bileşenleri/modifier'ları tercih et.

## Teslim ve doğrulama

1. Değişiklikten önce ve sonra `git diff` ile yalnızca gerekli dosyaların
   değiştiğini kontrol et.
2. Derle ve test et:
   `xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug build`
   `xcodebuild test -project GlassDo.xcodeproj -scheme GlassDo-macOS -destination 'platform=macOS'`
3. Uygulamayı açıp hem `.panelInline` hem sheet görünümünde şu göz kontrolünü
   yap:
   - Uzun başlık taşmadan veya header'ı bozmadan okunuyor.
   - Due date/Repeat switch'leri gerçek switch, tarih ve recurrence alanları
     bağlı şekilde açılıp kapanıyor.
   - Start düğmesi kart genişliğinde net primary action.
   - Context `+` ikonunun tamamı kolay tıklanıyor; chevron görünmüyor;
     dört mevcut menu eylemi açılıyor.
   - Subtask ekleme/silme, attachment ekleme/silme ve active focus session
     davranışları korunuyor.
   - Reduce Motion açıkken ilgili alanlar kaymadan fade ile değişiyor.
4. Son yanıtta: değişen dosyaları, tasarım kararlarını, build/test sonucunu ve
   manuel göz kontrolünde doğrulayamadığın bir şey varsa bunu dürüstçe yaz.
```

## Neden bu brief bu kadar yönlendirici?

Ekran görüntüsünde sorun yeni özellik eksikliği değil, görsel önceliklerin aynı
anda bağırması: Notes yüzeyi, form kartları, segmented control ve küçük Start
düğmesi birbirinden kopuk görünüyor. Brief, macOS'un yerleşik control
alışkanlıklarını koruyup yalnızca grup, ritim, hit target ve hareketi
iyileştirmeyi şart koşar. Böylece Sonnet'in “daha güzel” diye gereksiz cam,
blur, gradient veya geniş kapsamlı refactor eklemesini engeller.
