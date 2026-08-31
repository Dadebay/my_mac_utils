# 12 — Edge Rail + Liquid Glass Panel

> **Durum:** Tasarım şartnamesi — uygulanmayı bekliyor (Faz 5'in yerini alır).
> **Hedef:** Ekran kenarına yapışık, ikonlu dikey bir ray; üzerine gelince tek
> parça cam yüzey olarak açılıp görev listesini gösteriyor.
> **Değiştirdiği kod:** Mevcut `Sources/macOS/Panel/` tamamen bu tasarımla değişir.

---

## 1. Referans analizi (kullanıcının gönderdiği görsel)

Görselde Samsung Edge Panel benzeri bir davranış var:

| Gözlem | Bizde karşılığı |
|---|---|
| Sağ kenara **yapışık** dikey ray | ✅ aynen alınacak |
| Ray içinde **ikon sütunu** | ✅ ama uygulama ikonu değil, **aksiyon ikonları** |
| Hover → yanında panel açılıyor | ✅ aynen alınacak |
| Panelde bugünün öğeleri listeleniyor | ✅ görev listesi |
| Seçilince ayrı bir **detay kartı** açılıyor | ❌ **alınmayacak** — aşağıdaki gerekçe |

### Referansın zayıf yanları (bilerek düzeltiyoruz)

**1. Cam üstüne cam.** Görselde panel ve detay kartı iki ayrı yüzen katman.

> **Tasarım Kuralı — Liquid Glass > Best practices:** "Don't use Liquid Glass in
> the content layer. It works best when providing a clear distinction between
> interactive elements and content. Including it in the content layer creates
> unnecessary complexity and confusing visual hierarchy."

→ Bizde **cam sadece kabuk** (ray + panel gövdesi). Görev satırları, detay,
liste içeriği cam **değil** — düz içerik katmanı.

**2. Dinlenme hâlinde hiçbir bilgi yok.** Ray sadece ikon gösteriyor; kaç işin
kaldığını öğrenmek için hover şart.
→ Bizde birincil ikonun üstünde **sayı rozeti** var, bakmak yeterli.

**3. İki ayrı dikdörtgen.** Ray ve panel ayrı kutular — geçiş "açılma" değil
"beliriverme" gibi duruyor.
→ Bizde ray ve panel **tek bir cam yüzey**; ray sola doğru **uzayarak** panele
dönüşür (`GlassEffectContainer` + `glassEffectID` morph). Liquid Glass'ın
"liquid" kısmı tam olarak budur.

**4. Zamanlayıcıyla gizlenme, açık bir alternatif olmadan.**

> **Tasarım Kuralı — Accessibility > Cognitive:** "Minimize use of time-boxed
> interface elements. Views and controls that auto-dismiss on a timer can be
> problematic for people who need longer to process information... Prefer
> dismissing views with an explicit action."

→ Otomatik gizlenme **opsiyonel** (varsayılan kapalı), ve her durumda menü bar
öğesi + global kısayol ile açık bir alternatif var.

### Referansın doğru yaptığı

Hover ile ortaya çıkan kenar kontrolü, masaüstünde **desteklenen** bir kalıp:

> **Tasarım Kuralı — Pointing devices > Best practices:** "Let people use the
> pointer to reveal and hide controls that automatically minimize or fade out."

---

## 2. Anatomi ve ölçüler

### Dinlenme — Rail (varsayılan)

```
                                          ┌────┐
                                          │ ☑ ⑦│  Görevler + rozet
                                          │ ＋ │  Hızlı ekle
                                          │ ✓  │  Tamamlananlar
                                          │ 📌 │  Pinle
                                          │ ⚙  │  Ayarlar
                                          └────┘
                                            52pt   ← ekran kenarına yapışık
```

### Açık — Expanded (hover)

```
   ╭──────────────────────────────┬────╮
   │ Görevler                  7  │ ☑ ⑦│
   │ ───────────────────────────  │ ＋ │
   │ ○ provider kod               │ ✓  │
   │ ○ İş görüşmesi               │ 📌 │
   │ ○ Çek meselesi çözülmeli     │ ⚙  │
   │ ○ Firebase landing page      │    │
   │ ───────────────────────────  │    │
   │ ＋ Hızlı ekle…               │    │
   ╰──────────────────────────────┴────╯
              320pt                 52pt
   ▲ TEK cam yüzey — ray sola uzayarak panele dönüşür
```

### Gizli — Sliver (opsiyonel mod)

```
                                               ┃  6pt tutamak
```

### Ölçü tablosu

| Öğe | Değer | Gerekçe |
|---|---|---|
| Ray genişliği | **52 pt** | 28pt kontrol + 12pt×2 padding |
| Ray ikon hit alanı | **28 × 28 pt** | HIG masaüstü varsayılan kontrol boyu |
| Ray satır yüksekliği | **44 pt** | hit alanları **bitişik** olsun (boşluk yok) |
| Ray glif boyutu | 17 pt | |
| Ray yüksekliği | 16 + (n × 44) + 16 | n = ikon sayısı (5) → 236 pt |
| Panel genişliği | **320 pt** | |
| Panel yüksekliği | clamp(240, içerik, min(560, ekranYüksekliği − 80)) | |
| Sliver genişliği | **6 pt** | |
| Köşe yarıçapı (iç) | **22 pt** | `Layout.panelCornerRadius` |
| Köşe yarıçapı (ekran kenarı) | **0 pt** | kenara yapışık hissi |
| Kenar boşluğu (ekrana) | **0 pt** (flush) | |

> Ekran kenarına bakan köşeler düz, içe bakan köşeler yuvarlak →
> `UnevenRoundedRectangle`. Sağ kenarda: `topLeadingRadius: 22`,
> `bottomLeadingRadius: 22`, diğerleri `0`. Sol kenarda ayna.

---

## 3. Durum makinesi

```
   ┌──────────┐   hover / ⌥Space / menü bar    ┌──────────┐
   │  sliver  │ ──────────────────────────────▶│   rail   │
   │   6pt    │◀────────────────────────────── │   52pt   │
   └──────────┘   2.5 sn boşta (yalnız Sliver modu)  │  ▲
                                                     │  │
                                       hover 120ms   │  │ çıkış 400ms
                                                     ▼  │
                                              ┌──────────────┐
                                              │   expanded   │
                                              │  320+52 pt   │
                                              └──────────────┘
                                                     │  ▲
                                              pin ○──┘  └──○ pin kaldır
                                                     ▼
                                              ┌──────────────┐
                                              │    pinned    │  otomatik geçiş YOK
                                              └──────────────┘
```

### Zamanlamalar

| Geçiş | Gecikme | Animasyon |
|---|---|---|
| rail → expanded | 120 ms | `spring(response: 0.34, dampingFraction: 0.82)` |
| expanded → rail | 400 ms | `spring(response: 0.28, dampingFraction: 0.90)` |
| sliver → rail | 80 ms | `spring(response: 0.22, dampingFraction: 0.90)` |
| rail → sliver | 2500 ms | `spring(response: 0.28, dampingFraction: 0.90)` |

**Çıkış gecikmesi neden 400 ms?** Pencere fare altında küçülürken
`onHover(false)` tetiklenmeyebilir; gecikme bunu maskeler. Ayrıca:

> **Tasarım Kuralı — Motion > Best practices:** "Let people cancel motion. Don't
> make people wait for an animation to complete before they can do anything."

→ Animasyon sırasında tıklama/hover engellenmeyecek; yeni hover mevcut
animasyonu iptal edip yön değiştirebilmeli.

### Modlar (Ayarlar'dan seçilir)

| Mod | Dinlenme hâli | Otomatik gizlenme |
|---|---|---|
| **Rail** (varsayılan) | 52pt ikon rayı | yok |
| **Sliver** | 6pt tutamak | 2.5 sn boşta |
| **Pinned** | panel hep açık | yok |

---

## 4. Liquid Glass uygulaması

### Katman ayrımı (en kritik kural)

```
┌─────────────────────────────────────────┐
│  FONKSİYONEL KATMAN → Liquid Glass      │  ray + panel gövdesi
│  ┌───────────────────────────────────┐  │
│  │  İÇERİK KATMANI → cam DEĞİL       │  │  görev satırları, başlık,
│  │  düz dolgu / vibrancy             │  │  hızlı ekle alanı
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

```swift
// DOĞRU — tek cam kabuk, içerik camsız
GlassEffectContainer(spacing: 0) {
    HStack(spacing: 0) {
        if isExpanded { panelContent }   // düz içerik
        railStrip                        // düz içerik
    }
    .glassEffect(.regular, in: shellShape)
    .glassEffectID("shell", in: namespace)
}

// YANLIŞ — satırlara da cam
ForEach(tasks) { task in
    TaskRow(task).glassEffect(.regular, in: .capsule)  // ❌ cam üstüne cam
}
```

### Varyant seçimi: `.regular`

> **Tasarım Kuralı — Liquid Glass > Two Variants:** "Regular... Use for
> components with significant text (alerts, sidebars, popovers). Most system
> components use this variant."

Panelimiz metin ağırlıklı → `.regular`. `.clear` sadece medya üstünde
yüzen kontroller için; bizde kullanılmayacak.

### Renk kullanımı

> **Tasarım Kuralı — Liquid Glass > Color Rules:** "Apply color sparingly...
> Refrain from adding color to the background of multiple controls. Only one
> primary action per context should get background color emphasis."

- Cam yüzeye **hiç tint yok** — arkadaki içeriğin rengini alsın
- Ray ikonları **monokrom** (`.primary` / `.secondary`)
- Renk **tek yerde**: sayı rozeti (accent renk arka plan)
- Seçili/aktif ray ikonu → **foreground** accent (arka plan değil)
- Sabit hex renk **yok**; sistem semantik renkleri kullan

> **Tasarım Kuralı — Accessibility > Vision:** "Prefer system-defined colors.
> These colors have their own accessible variants that automatically adapt."

### Scroll edge effect

> **Tasarım Kuralı — Liquid Glass > Visual Properties:** "Scroll edge effects:
> Background content is blurred and reduced in opacity at scroll edges to
> enhance legibility."

Görev listesinin üst ve alt kenarında 12pt'lik `LinearGradient` mask →
kaydırılan satırlar cam kenarına girerken solsun.

### Morph (ray → panel)

`@Namespace` + `glassEffectID("shell", in: ns)` ile tek kimlik. Yüzey
genişlerken cam **akarak** uzar, iki ayrı kutu belirmez. Bu, referans
görselden en görünür farkımız.

---

## 5. Teknik mimari

### Dosya yapısı

```
Sources/GlassDoKit/
├── DesignSystem/
│   └── EdgeTokens.swift          YENİ — ölçüler, yarıçaplar, süreler
└── Services/
    ├── EdgeGeometry.swift        YENİ — saf fonksiyonlar (test edilir)
    └── PanelPresentation.swift   YENİ — durum enum + geçiş kuralları (saf)

Sources/macOS/Panel/
├── EdgePanel.swift               YENİ — NSPanel alt sınıfı
├── EdgePanelController.swift     YENİ — @MainActor @Observable, NSWindowDelegate
├── EdgeShellView.swift           YENİ — tek cam kabuk + morph
├── EdgeRailView.swift            YENİ — dikey ikon rayı
├── RailIconButton.swift          YENİ — 28pt hit alanı + hover efekti
├── PanelTaskListView.swift       YENİ — görev listesi (camsız)
└── PanelQuickAddView.swift       YENİ — hızlı ekleme alanı
```

### Silinecek dosyalar

```
Sources/macOS/Panel/FloatingPanel.swift            → EdgePanel.swift
Sources/macOS/Panel/FloatingPanelController.swift  → EdgePanelController.swift
Sources/macOS/Panel/PanelRootView.swift            → EdgeShellView.swift
Sources/macOS/Panel/CollapsedCapsuleView.swift     → EdgeRailView.swift
Sources/macOS/Panel/ExpandedPanelView.swift        → PanelTaskListView.swift
Sources/GlassDoKit/Services/PanelGeometry.swift    → EdgeGeometry.swift
Tests/GlassDoKitTests/PanelGeometryTests.swift     → EdgeGeometryTests.swift
```

`GlassDoApp.swift` içindeki `FloatingPanelController` referansları ve
`MenuBarContentView` güncellenecek.

### Saf geometri fonksiyonları (test edilir)

```swift
public enum ScreenEdge: String, Sendable { case leading, trailing }

public enum EdgeGeometry {
    /// Ray dikdörtgeni — kenara yapışık, dikeyde serbest
    public static func railFrame(
        edge: ScreenEdge, verticalTop: CGFloat, iconCount: Int, visible: NSRect
    ) -> NSRect

    /// Açık hâl — ray + panel tek dikdörtgen, ekran dışına taşmaz
    public static func expandedFrame(
        railFrame: NSRect, edge: ScreenEdge, panelSize: CGSize, visible: NSRect
    ) -> NSRect

    /// Gizli hâl — sadece sliver görünür
    public static func sliverFrame(
        railFrame: NSRect, edge: ScreenEdge, sliverWidth: CGFloat
    ) -> NSRect

    /// Sürükleme bitince hangi kenara yapışacağı
    public static func nearestEdge(point: NSPoint, visible: NSRect) -> ScreenEdge

    /// Dikey pozisyonu görünür alana sıkıştır
    public static func clampedTop(
        _ top: CGFloat, height: CGFloat, visible: NSRect
    ) -> CGFloat
}
```

**Kural:** Bu fonksiyonlar `NSScreen`/`NSWindow` okumaz, sadece parametre alır →
test edilebilir. Controller onları çağırır.

### Tek pencere yaklaşımı

Ray ve panel **ayrı pencere değil**. Tek `NSPanel`, frame'i animasyonla
büyüyüp küçülüyor (52 ↔ 372 pt). İçerik `HStack` ile ray sabit sağda kalacak
şekilde yerleşiyor.

**Neden iki pencere değil?** İki pencerede hover koordinasyonu (fare
birinden diğerine geçerken ikisi de "çıkış" görüyor) çözülmesi zor bir
titreme kaynağı.

### NSPanel ayarları (mevcut koddan korunur)

```swift
styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]
level = .floating
isFloatingPanel = true
hidesOnDeactivate = false
acceptsMouseMovedEvents = true          // hover için ŞART
isReleasedWhenClosed = false
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                      .stationary, .ignoresCycle]
override var canBecomeKey: Bool { true }
override var canBecomeMain: Bool { false }
```

**Mutlak kural:** Gösterirken **sadece** `orderFrontRegardless()`.
`makeKeyAndOrderFront(_:)` ve `NSApp.activate()` **asla** çağrılmayacak —
Xcode'dan odak kaçar. Tek istisna: hızlı ekleme alanına yazarken geçici
`panel.makeKey()`, alandan çıkınca `panel.resignKey()`.

---

## 6. Etkileşim detayları

### Fare

| Eylem | Sonuç |
|---|---|
| Ray üzerine hover | 120 ms sonra panel açılır |
| Panelden fare çıkışı | 400 ms sonra kapanır (pinned değilse) |
| Sliver üzerine hover | 80 ms sonra ray belirir |
| Rayı dikeyde sürükle | Pozisyon değişir, `UserDefaults`'a kaydedilir |
| Rayı yatayda karşı kenara sürükle | Kenar değişir (leading ↔ trailing) |
| Ray ikonuna tık | İlgili aksiyon (panel açık kalır) |
| Görev satırına tık | Satır içi düzenleme açılır |
| Daire ikonuna tık | Tamamla/geri al — **odak kaybı yok** |

### Ray ikonları

| # | İkon | Aksiyon |
|---|---|---|
| 1 | `checklist` + rozet | Görevler listesi (varsayılan görünüm) |
| 2 | `plus` | Hızlı ekle alanına odaklan |
| 3 | `checkmark.circle` | Tamamlananlar görünümü |
| 4 | `pin` / `pin.fill` | Pinned modu aç/kapa |
| 5 | `gear` | Ayarlar penceresi |

> **İleriye dönük:** Proje/kategori kavramı geri gelirse, ray'in 3. ve 4.
> sırası arasına proje ikonları eklenir (referans görseldeki "uygulama
> ikonları" mantığı). Şu an model tek alanlı (sadece `title`) olduğu için
> proje ikonu yok.

### Ray ikonu hover efekti

> **Tasarım Kuralı — Pointing devices > Standard pointers and effects:** "Use
> highlight for a small element that has a transparent background."

→ İkon arkasında 28pt yuvarlak köşeli yarı saydam dolgu belirir (scale/shadow
**yok** — dar alanda scale komşuyu ezer).

> **Tasarım Kuralı — Pointing devices:** "Create contiguous hit regions for
> custom bar buttons. If there's space between the hit regions of adjacent
> buttons in a bar, people may experience a distracting motion."

→ Ray satırları **bitişik** (44pt yükseklik, aralarında boşluk yok).

### Klavye (hover'a alternatif — zorunlu)

> **Tasarım Kuralı — Accessibility > Mobility:** "Offer alternatives to
> gestures. Make sure your UI's core functionality is accessible through more
> than one type of physical interaction."

| Kısayol | Aksiyon |
|---|---|
| ⌥Space | Paneli aç + hızlı ekleme alanına odaklan |
| Esc | Paneli kapat |
| ↑ / ↓ | Görev satırları arasında gez |
| Space | Seçili görevi tamamla/geri al |
| ⌘⌫ | Seçili görevi sil |

---

## 7. Erişilebilirlik (pazarlık konusu değil)

| Gereksinim | Uygulama |
|---|---|
| **Kontrol boyutu** | Ray ikonları 28×28 pt (HIG masaüstü varsayılanı; mutlak alt sınır 20×20) |
| **Kontrast** | 17pt altı metin ≥ 4.5:1 — sistem semantik renkleri kullanıldığı için otomatik |
| **Yazı boyutu** | Gövde 13 pt (masaüstü varsayılanı), ikincil 11 pt, **10 pt altına inme** |
| **Şeffaflığı azalt** | `accessibilityReduceTransparency` → cam yerine opak `.background` yüzey |
| **Hareketi azalt** | `accessibilityReduceMotion` → spring yerine 0.12 s `linear`, blur geçişi yok |
| **VoiceOver** | Her ray ikonuna `.accessibilityLabel`, panele `.accessibilityAddTraits(.isModal)` **verme** (modal değil) |
| **Renk tek başına anlam taşımasın** | Tamamlanan görev: hem üstü çizili **hem** ikon değişiyor — sadece renk değil |
| **Zamanlayıcıya bağımlılık** | Otomatik gizlenme varsayılan **kapalı**, menü bar + kısayol alternatifi hep var |

> **Tasarım Kuralı — Accessibility > Cognitive (Reduce Motion):** "Tightening
> animation springs to reduce bounce effects... Replacing transitions in x-, y-,
> and z-axes with fades to avoid motion... Avoiding animating into and out of
> blurs."

---

## 8. Ayarlar (Faz 6'ya eklenecek)

```
Panel
├─ Dinlenme modu:  ( ) Ray   ( ) Otomatik gizlen   ( ) Hep açık
├─ Kenar:          ( ) Sol   (•) Sağ
├─ Panel yüksekliği:  [────●────]  240 – 560 pt
├─ Otomatik gizlenme süresi: [──●──] 1 – 10 sn   (yalnız "Otomatik gizlen")
├─ ☑ Panelde tamamlananları göster
└─ ☑ Tüm Space'lerde görün
```

---

## 9. Test planı

### Unit testler (Swift Testing) — `EdgeGeometryTests.swift`

```swift
@Test("Sağ kenarda panel sola doğru açılıyor")
@Test("Sol kenarda panel sağa doğru açılıyor")
@Test("Açık panel ekranın üstünden/altından taşmıyor")
@Test("Ekran dışı dikey pozisyon görünür alana çekiliyor")
@Test("Ekranın sağ yarısındaki nokta trailing kenara yapışıyor")
@Test("Sliver frame'i panelin sadece 6pt'sini bırakıyor")
@Test("Ray yüksekliği ikon sayısıyla doğru hesaplanıyor")
@Test("Çözünürlük küçülünce ray görünür alanda kalıyor")
```

`PanelPresentation` (durum makinesi) da saf → geçiş testleri:

```swift
@Test("Pinned modda hover çıkışı paneli kapatmıyor")
@Test("Sliver modu kapalıyken rail'den sliver'a geçilmiyor")
@Test("Expanded → pin → unpin sonrası rail'e dönüyor")
```

### Manuel checklist

- [ ] Ray sağ kenara yapışık açılıyor, köşeler doğru (ekran tarafı düz)
- [ ] Hover → panel akarak açılıyor (iki ayrı kutu belirmiyor)
- [ ] Fare çıkınca kapanıyor, kenarda gezerken **titremiyor**
- [ ] Ray dikeyde sürükleniyor, yeniden başlatınca aynı yerde
- [ ] Karşı kenara sürükleyince kenar değişiyor, açılma yönü de dönüyor
- [ ] Xcode odaktayken panelde tik at → **Xcode odakta kalıyor**
- [ ] Hızlı ekleme alanına yazılabiliyor, yazınca odak geri veriliyor
- [ ] Sliver modunda 2.5 sn sonra gizleniyor, hover'da geri geliyor
- [ ] Pinned modda hiç kapanmıyor
- [ ] Full-screen Safari üstünde görünüyor
- [ ] Başka Space'e geçince geliyor
- [ ] ⌘\` döngüsünde çıkmıyor
- [ ] İkinci monitörde çalışıyor; monitör çıkınca ana ekrana dönüyor
- [ ] Uyku/uyanma sonrası yerinde
- [ ] Açık ve koyu duvar kağıdında **okunuyor**
- [ ] Beyaz Safari sayfası ve video üstünde okunuyor
- [ ] "Şeffaflığı azalt" açıkken opak yüzey
- [ ] "Hareketi azalt" açıkken spring yok
- [ ] VoiceOver ray ikonlarını doğru okuyor
- [ ] Klavye ile tam kullanılabiliyor (⌥Space, Esc, ↑↓, Space, ⌘⌫)
- [ ] 500+ görevle liste akıcı
- [ ] Idle CPU ~%0, bellek < 80 MB

---

## 10. Uygulama sırası

Her adım **derlenen** bir durum bırakır. Adımları tek tek yap.

| Adım | İçerik | Kabul |
|---|---|---|
| **12.1** | `EdgeTokens`, `EdgeGeometry`, `PanelPresentation` (saf kod) + testler | Testler geçiyor, UI değişmiyor |
| **12.2** | `EdgePanel` + `EdgePanelController`, **sadece ray** — kenara yapışık, dikey sürüklenir, pozisyon kalıcı | Ray görünüyor, sürükleniyor, odak çalmıyor |
| **12.3** | Hover → tek cam yüzey olarak açılma + görev listesi | Panel akarak açılıyor, tik atınca odak kalıyor |
| **12.4** | Ray ikonları, sayı rozeti, pin modu, menü bar entegrasyonu | İkonlar çalışıyor, pin kapanmayı engelliyor |
| **12.5** | Sliver modu + otomatik gizlenme + kenar değiştirme | Üç mod da çalışıyor |
| **12.6** | Erişilebilirlik geçişi (reduce motion/transparency, klavye, VoiceOver) | Checklist'in erişilebilirlik maddeleri geçiyor |
| **12.7** | Cila: scroll edge effect, ikon hover efekti, satır içi düzenleme | Görsel tamam |

> **12.3'te takılırsan:** Önce sabit boyutlu, hover'sız bir ray+panel çıkar
> (her zaman açık). Sonra hover'ı ekle. Sonra morph'u ekle. Üçünü aynı anda
> debug etme.

---

## 11. Bilinen tuzaklar

Bunlar bu projede **gerçekten yaşandı** — tekrar yaşama.

| Sorun | Sebep | Çözüm |
|---|---|---|
| `Task` belirsiz | `GlassDoKit.Task` ile Swift concurrency `Task` çakışıyor | Gecikmeler için `_Concurrency.Task { }` yaz |
| `#Predicate` runtime crash | Force-unwrap (`task.dueDate!`) SwiftData'da desteklenmiyor | `.flatMap { $0 < end } ?? true` kullan |
| `#Predicate` derlenmiyor | `?? Date.distantPast` karşılaştırmayla birleşince macro patlıyor | Yine `.flatMap` |
| `codesign: bundle format unrecognized` | XcodeGen 2.46'da target'ta `info:` yok | **Her** target'a `info: path: .../Info.plist` ekle (framework ve test dahil) |
| `Decoding failed at "path"` | `info:` bloğunda `path` eksik | `properties: {}` boş olsa bile `path` yaz |
| Panele tıklayınca Xcode arkaya gidiyor | `makeKeyAndOrderFront` / `NSApp.activate()` | Sadece `orderFrontRegardless()` |
| Hover çalışmıyor | `acceptsMouseMovedEvents = false` | `true` yap |
| Panel full-screen'de kayboluyor | collection behavior eksik | `.fullScreenAuxiliary` ekle |
| Küçülürken hover event kaybı | Fare eski büyük alanda kalıyor | 400 ms çıkış gecikmesi + `NSTrackingArea` (`.activeAlways`, `.mouseEnteredAndExited`, `.inVisibleRect`) |
| Metin alanına yazamıyorum | `canBecomeKey = false` | Override `true`, alan odaklanınca `makeKey()`, çıkınca `resignKey()` |
| Uyku sonrası panel kayboldu | Ekran parametreleri değişti | `NSApplication.didChangeScreenParametersNotification` dinle, yeniden konumlandır |
| Model değişince app açılmıyor | Eski yerel store şemayla uyuşmuyor | `~/Library/Application Support/default.store*` sil |

---

## 12. Kabul kriterleri

Bu tasarım "bitti" sayılır eğer:

- [ ] Ray ekran kenarına yapışık duruyor, dikeyde sürüklenebiliyor, pozisyon kalıcı
- [ ] Rozet kaç görev kaldığını hover gerekmeden gösteriyor
- [ ] Hover'da ray **akarak** panele dönüşüyor (tek cam yüzey, iki kutu değil)
- [ ] Panelde görev tamamlanabiliyor ve eklenebiliyor, **odak hiç kaybolmuyor**
- [ ] Üç mod (Rail / Sliver / Pinned) da çalışıyor ve ayarlardan seçiliyor
- [ ] Cam **sadece** kabukta; satırlarda cam yok
- [ ] Reduce transparency + reduce motion doğru ele alınıyor
- [ ] Klavyeyle hover'sız tam kullanılabiliyor
- [ ] Geometri ve durum makinesi testleri geçiyor
- [ ] Manuel checklist tamam

---

## 13. Sonnet'e verilecek prompt

```
docs/12-EDGE-RAIL.md'yi baştan sona oku ve uygula.

Bu, mevcut Sources/macOS/Panel/ altındaki floating panel tasarımının
YERİNE geçiyor — dosya 5. bölümdeki "Silinecek dosyalar" listesini takip et.

Adım adım git: önce 12.1 (saf geometri + durum makinesi + testler), derle,
testleri çalıştır, sonuçları göster, DUR. Onay alınca 12.2'ye geç.
Hepsini birden yapma.

Mutlak kurallar:
1. Panelden tik atarken NSApp.activate() veya makeKeyAndOrderFront
   ÇAĞRILMAYACAK. Sadece orderFrontRegardless(). Odak kaybı kabul edilemez.
2. Cam SADECE kabukta (ray + panel gövdesi). Görev satırlarına, listeye,
   hızlı ekleme alanına cam UYGULAMA — docs/12 bölüm 4'teki katman kuralı.
3. Ray ve panel tek NSPanel; frame animasyonuyla büyüyüp küçülüyor.
   İki ayrı pencere kullanma.
4. Geometri fonksiyonları saf olacak (NSScreen okumayacak), testleri yazılacak.
5. Hover gecikmeleri: girişte 120ms, çıkışta 400ms, sliver'da 80ms.
6. GlassDoKit.Task ile Swift'in Task'ı çakışır — _Concurrency.Task kullan.
7. Erişilebilirlik 7. bölümdeki tabloya göre — reduceTransparency ve
   reduceMotion atlanmayacak.

Her adımda `xcodebuild test -scheme GlassDo-macOS -destination 'platform=macOS'`
çalıştır ve sonucu raporla. Şartnamede olmayan özellik ekleme.
```

---

## 14. İlgili dokümanlar

- [00-OVERVIEW.md](00-OVERVIEW.md) — kapsam (macOS-only, yerel store)
- [06-LIQUID-GLASS.md](06-LIQUID-GLASS.md) — genel cam tasarım sistemi
- [07-IMPLEMENTATION-PLAN.md](07-IMPLEMENTATION-PLAN.md) — faz planı
- `~/.claude/skills/apple-design/references/hig/liquid-glass.md` — HIG kaynağı
