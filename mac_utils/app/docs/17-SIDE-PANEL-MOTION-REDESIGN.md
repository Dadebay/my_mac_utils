# Side Panel Açılma/Kapanma Animasyonu — İyileştirme Planı

Bu doküman, ekran görüntüsündeki sağ kenara bağlı görev panelinin (`EdgePanel`) açılma ve kapanma hareketini düzeltmek için hazırlanmıştır. Hedef yeni bir görsel efekt eklemek değil; paneli daha hızlı, sakin, mekânsal olarak tutarlı ve her an tersine çevrilebilir hissettirmektir.

## Kısa karar

Panel ekran kenarından çıkan tek bir yüzey gibi davranmalı:

- Sağdaki ikon rayı yerinde kalmalı.
- Panel gövdesi rayın altından sola doğru açılmalı; sol kenardaysa bunun aynası uygulanmalı.
- İçerik açılma boyunca gerçek genişliğinde kalmalı. Metinler animasyon sırasında yeniden satırlanmamalı.
- Pencere büyümesi ve içerik görünürlüğü tek zaman çizelgesinde ilerlemeli.
- Aç/kapat hareketinde bounce kullanılmamalı. Ekran kenarı fiziksel bir çapa olduğu için taşma, paneli kenardan kopmuş gibi gösterir.
- Kullanıcı animasyon bitmeden tekrar tıklarsa hareket mevcut görsel konumdan tersine dönebilmeli.

Önerilen ilk ayarlar:

| Parça | Açılma | Kapanma |
|---|---:|---:|
| Pencere çerçevesi | 0.28 sn | 0.22 sn |
| Eğri | `(0.22, 0.78, 0.20, 1.00)` | `(0.22, 0.78, 0.20, 1.00)` |
| İçerik opacity | 0.16 sn, 0.035 sn gecikme | 0.09 sn, gecikmesiz |
| İçerik translate/scale | Yok | Yok |

Bu değerler başlangıç noktasıdır. Önce hareketin yapısı düzeltilmeli; sonrasında süreler gerçek uygulamada 0.02 sn adımlarla ayarlanabilir.

## Ekran görüntüsünden okunan mekânsal yapı

Panel iki parçadan oluşuyor:

1. Sağ kenarda sürekli görünen dar ikon rayı.
2. Rayın solunda açılan görev içeriği.

Bu nedenle animasyonun kaynağı sağ kenardaki raydır. İçerik ortadan belirmemeli, ölçeklenmemeli veya aşağıdan gelmemeli. Açılış ve kapanış aynı yatay yolu ters yönlerde kullanmalıdır.

Panel modal değil; arka planı karartan bir scrim eklenmemeli. Cam yüzey yalnızca derinliği anlatmalı, hareketin kendisi içerikten rol çalmamalıdır.

## Mevcut uygulamadaki temel sorunlar

### 1. AppKit ve SwiftUI iki bağımsız animasyon çalıştırıyor

`EdgePanelController.setVisualState` pencerenin `frame` değerini `NSAnimationContext` ile değiştiriyor. Aynı anda `EdgeShellView`, `visualState` değiştiği için panel içeriğini ayrı bir SwiftUI opacity transition'ı ile ekliyor veya kaldırıyor.

Bu iki sistem aynı intent ile başlasa da aynı transaction'a ait değil. Sonuç olarak bazı karelerde pencere ve içerik farklı fazlarda kalabilir:

- pencere büyürken içerik geç gelebilir,
- kapanırken içerik çok erken yok olabilir,
- hızlı aç-kapat işleminde pencere ve içerik farklı hızlarda yön değiştirebilir.

### 2. İçerik genişliği açılma boyunca sabitlenmemiş

`EdgeShellView.panelContentHost` şu anda `maxWidth: .infinity` kullanıyor. Pencerenin genişliği her kare değiştiği için SwiftUI içeriği tekrar tekrar dar bir alana yerleştirebilir. Özellikle iki satıra izin verilen görev başlıklarında bu durum görünür bir “ezilme / yeniden sarılma” üretir.

Animasyon sırasında içerik yerleşimi değişmemeli. Panel içeriği baştan itibaren son genişliği olan `PanelSettings.panelWidth` ile ölçülmeli; pencerenin büyüyen sınırı yalnızca onu kademeli olarak göstermelidir.

### 3. İçerik kapanışta hemen view tree'den çıkıyor

`controller.visualState == .expanded` koşulu false olduğu anda içerik kaldırılıyor. Opacity removal transition kısa olsa bile pencere frame animasyonu sürerken içerik ömrü doğrudan hedef state'e bağlı kalıyor. Görsel state ile içerik mount state'i ayrılmadığı için sakin bir kapanış kurmak zorlaşıyor.

### 4. Motion token'ları gerçek uygulamayla uyuşmuyor

`Motion.expand` ve `Motion.collapse` spring olarak tanımlı; fakat panel penceresi gerçekte `EdgeTokens.panelExpandDuration`, `panelCollapseDuration` ve bir `CAMediaTimingFunction` kullanıyor. Aynı hareket için iki ayrı kaynak olması ayarların zamanla ayrışmasına neden oluyor.

### 5. Mevcut curve gereğinden sert başlıyor

`(0.32, 0.72, 0, 1)` eğrisi ilk bölümde çok agresif hissedebilir. Panel geniş ve metin ağırlıklı bir yüzey olduğu için ilk karede tepki vermeli, fakat “fırlayıp frenleyen” bir hareket yerine kontrollü biçimde hızlanıp yumuşak yerleşmelidir.

## Önerilen hareket modeli

Tek başına `expanded / rail` hedef durumu yeterli değildir. Görsel geçiş fazı da tutulmalıdır:

```swift
enum PanelMotionPhase: Equatable {
    case collapsed
    case opening
    case open
    case closing
}
```

Bu fazın amacı iş kurallarını değiştirmek değildir. `visualState` yine panelin hedef durumunu belirtir. `motionPhase` yalnızca içeriğin ne zaman mount edileceğini ve ne zaman görünür olacağını yönetir.

Beklenen sıra:

```text
Açılış
collapsed
  → içerik görünmez olarak mount edilir
  → opening + pencere frame animasyonu başlar
  → 35 ms sonra içerik opacity 1 olur
  → frame tamamlanınca open

Kapanış
open
  → closing + içerik opacity 0 olur
  → pencere frame animasyonu aynı anda başlar
  → frame tamamlanınca içerik unmount edilir
  → collapsed
```

Bu yapı sayesinde kapanış sırasında panel boş bir siyah yüzeye dönüşmez ve ağır içerik gereksiz yere sürekli mount edilmiş kalmaz.

## Uygulama adımları

### Adım 1 — İçerik yerleşimini sabitle

İlk ve en yüksek getirili değişiklik `EdgeShellView.panelContentHost` genişliğini sabitlemektir:

```swift
private var panelContentHost: some View {
    ZStack(alignment: .topLeading) {
        panelContent
            .id(controller.content)
            .transition(contentSwapTransition)
    }
    .frame(
        width: PanelSettings.panelWidth,
        height: PanelSettings.effectivePanelHeight,
        alignment: .topLeading
    )
    .clipped()
    .animation(contentSwapAnimation, value: controller.content)
}
```

Önemli nokta: içerik kendi son boyutunda düzenlenir; AppKit penceresinin animasyonlu sınırı doğal bir reveal maskesi gibi çalışır. Task metinleri açılış sırasında tekrar satırlanmaz.

İçeriğe ayrıca `offset`, `move`, `scaleEffect` veya blur transition eklenmemelidir. Pencerenin yatay hareketi zaten ana hareketi üretir; ikinci bir slide “çift animasyon” hissi verir.

### Adım 2 — Mount ile görünürlüğü ayır

`EdgePanelController` içine aşağıdaki gözlemlenebilir durumlar eklenmelidir:

```swift
private(set) var motionPhase: PanelMotionPhase = .collapsed
private(set) var isPanelContentMounted = false
private(set) var isPanelContentVisible = false
private var motionRevision = 0
```

`motionRevision`, hızlı aç-kapat-aç akışında eski completion handler'ın en yeni state'i bozmasını engeller. Her yeni geçişte artırılır; gecikmeli iş ve completion yalnızca kendi revision'ı hâlâ güncelse state yazar.

`EdgeShellView.panelLayout` içindeki koşul şu anlama gelmelidir:

```swift
if controller.isPanelContentMounted {
    panelContentHost
        .opacity(controller.isPanelContentVisible ? 1 : 0)
        .allowsHitTesting(controller.motionPhase == .open)
        .animation(contentVisibilityAnimation, value: controller.isPanelContentVisible)
}
```

Sağ ve sol kenar dallarında aynı koşul kullanılmalıdır. İçerik `closing` boyunca mount edilmiş kalır ama opacity sıfıra gider. Hit testing kapanış başlar başlamaz kapanır; görünmez hâle yaklaşan denetimler yanlışlıkla tıklanamaz.

İçerik görünürlük animasyonu:

```swift
private var contentVisibilityAnimation: Animation? {
    guard !reduceMotion else { return .easeOut(duration: 0.08) }

    return controller.isPanelContentVisible
        ? .timingCurve(0.22, 0.78, 0.20, 1, duration: 0.16).delay(0.035)
        : .easeOut(duration: 0.09)
}
```

### Adım 3 — Tek geçiş koordinatörü oluştur

`setVisualState` aşağıdaki sorumlulukları tek yerde yürütmelidir:

1. Önce önceki geçişin revision'ını geçersiz kıl.
2. Açılıyorsa içeriği görünmez şekilde mount et.
3. `visualState` ve `motionPhase` hedeflerini yaz.
4. Pencere frame animasyonunu başlat.
5. Açılışta bir sonraki run loop'ta içeriği görünür yap.
6. Completion'da revision kontrolü yap.
7. Kapanış gerçekten bittiyse içeriği unmount et.

İskelet:

```swift
private func setVisualState(_ newState: PanelVisualState) {
    guard let panel, let screen = panel.screen ?? Self.primaryScreen else { return }
    guard newState != visualState else { return }

    motionRevision += 1
    let revision = motionRevision
    let opening = newState == .expanded
    let target = targetFrame(for: newState, on: screen)

    if opening {
        isPanelContentMounted = true
        isPanelContentVisible = false
        motionPhase = .opening
    } else if visualState == .expanded {
        isPanelContentVisible = false
        motionPhase = .closing
    }

    visualState = newState
    syncOutsideClickMonitor()

    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        panel.setFrame(target, display: true)
        settleMotion(opening: opening, revision: revision)
        return
    }

    if opening {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.motionRevision == revision else { return }
            self.isPanelContentVisible = true
        }
    }

    let duration = opening ? PanelMotion.expandDuration : PanelMotion.collapseDuration

    NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.allowsImplicitAnimation = true
        context.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.22, 0.78, 0.20, 1.00
        )
        panel.animator().setFrame(target, display: true)
    } completionHandler: { [weak self] in
        MainActor.assumeIsolated {
            self?.settleMotion(opening: opening, revision: revision)
        }
    }
}
```

`settleMotion` eski completion'ları reddetmelidir:

```swift
private func settleMotion(opening: Bool, revision: Int) {
    guard motionRevision == revision else { return }

    if opening {
        isPanelContentVisible = true
        motionPhase = .open
    } else {
        isPanelContentVisible = false
        isPanelContentMounted = false
        motionPhase = .collapsed
    }
}
```

Not: Bu örnek uygulanırken `.sliver` geçişi ayrı ele alınmalıdır. Sliver ↔ rail geçişinde panel içeriği mount edilmez; yalnız pencere çerçevesi hareket eder.

### Adım 4 — Motion değerlerini tek kaynağa indir

Panel hareketine ait değerler `Motion.expand`, `Motion.collapse` ve `EdgeTokens` arasında bölünmemelidir. Örneğin:

```swift
public enum PanelMotion {
    public static let expandDuration = 0.28
    public static let collapseDuration = 0.22
    public static let contentDelay = 0.035
    public static let contentFadeInDuration = 0.16
    public static let contentFadeOutDuration = 0.09

    public static let curve: (Float, Float, Float, Float) =
        (0.22, 0.78, 0.20, 1.00)
}
```

Hem AppKit hem SwiftUI aynı sayıları kullanmalıdır. Eski `Motion.expand` ve `Motion.collapse` gerçekten başka yerde kullanılmıyorsa kaldırılmalıdır. Böylece dokümantasyon “spring”, gerçek davranış “cubic” şeklinde ayrışmaz.

### Adım 5 — Rail'i tamamen durağan tut

`EdgeShellView` içindeki ayrı `ZStack` katmanı doğru yönde bir karar. Şunlar korunmalıdır:

- `EdgeRailView` panel içeriğinin üstünde kalmalı.
- Rail'e panel açılış state'i üzerinden offset/scale/opacity verilmemeli.
- Seçili ikonun kendi küçük highlight animasyonu çalışabilir.
- Rail ikonları pencere genişlerken yatay olarak gezinmemeli.

Panel açılırken rail bir “tetikleyici ve çapa”dır; hareket eden nesne panel gövdesidir.

## Interruptibility: hızlı tersine çevirme

Apple tarzı akıcı arayüzün en önemli testi şudur:

1. Paneli aç.
2. Daha açılma bitmeden aynı ikona tekrar tıkla.
3. Kapanma bitmeden tekrar aç.

Doğru davranışta:

- bekleme yoktur,
- içerik bir kareliğine kaybolup geri gelmez,
- ray yer değiştirmez,
- eski completion en yeni state'i kapatmaz,
- pencere hedefe sıçramadan mevcut görsel konumundan yön değiştirir.

`motionRevision` state yarışını çözer. Buna rağmen `NSWindow` animator proxy hızlı retarget sırasında görünür bir frame sıçraması üretirse ikinci aşamada yalnız frame hareketi için hedef değiştirilebilen bir animator yazılmalıdır. Bu aşamaya ölçmeden geçilmemelidir; önce sabit içerik genişliği ve lifecycle koordinasyonu test edilmelidir.

Özel animator gerekirse şu özellikleri taşımalıdır:

- Her display frame'inde o anki `panel.frame` değerinden devam eder.
- Yeni hedef geldiğinde animasyonu iptal edip sıfırdan başlamaz; mevcut hız ve konumu devralır.
- Sağ kenarda `maxX`, sol kenarda `minX` sabit kalır.
- Y ekseninde üst kenar sabit kalır; gereksiz çapraz hareket oluşmaz.
- Ulaşılabilirlikte tamamen devre dışı kalır.

## Neden spring değil?

Spring her yerde daha “premium” değildir. Bu panel:

- büyük,
- metin ağırlıklı,
- ekranın sert kenarına bağlı,
- sık açılıp kapanan yardımcı bir yüzeydir.

Bu yüzden bounce içeriği okunurken oynatır ve paneli ekran kenarından koparır. Burada amaç kritik sönümlü spring hissine yakın, overshoot'suz bir curve'dür. Gerçek spring ancak drag ile doğrudan manipülasyon eklenirse ve bırakma hızı devralınırsa anlam kazanır.

## Reduce Motion davranışı

Mevcut kod reduce motion açıkken frame'i anında değiştiriyor. Bu güvenli ancak sert bir parlaklık/alan sıçraması oluşturabilir. Önerilen davranış:

- Pencere frame'i anında hedef boyuta geçsin.
- İçerik 0.08–0.10 sn opacity cross-fade kullansın.
- Offset, scale, blur ve spring kullanılmasın.
- Rail sabit kalsın.

Reduce Motion, “hiç geri bildirim yok” değil; konumsal hareket yerine kısa ve sakin bir görünürlük değişimidir.

## Yapılmaması gerekenler

- Panel içeriğine ayrıca `.move(edge:)` eklemek.
- Açılışta `scaleEffect(0.95)` kullanmak.
- Cam blur yarıçapını büyük aralıkta animasyonlamak.
- Satırları tek tek stagger ile açmak. Kullanıcı her panel açılışında listeyi beklememeli.
- Rail ve paneli farklı yaylarla hareket ettirmek.
- Kapanışta içeriği ilk karede view tree'den kaldırmak.
- Sadece duration değiştirerek temel layout problemini çözmeye çalışmak.
- Açılış ve kapanışta farklı mekânsal yollar kullanmak.

## Performans kontrolü

Animasyon değerlendirilirken yalnız “kaç FPS” değil, karelerde neyin değiştiği de incelenmelidir.

Kontrol listesi:

- Task başlıklarının satır kırılımı animasyon boyunca sabit mi?
- `PanelTaskListView` her frame yeni genişlikle layout oluyor mu?
- Cam yüzeyde tek katman mı var, iç kartlar ayrıca blur oluşturuyor mu?
- Scroll pozisyonu aç/kapat sonrası korunuyor mu?
- 500+ task ile frame pacing düzenli mi?
- Panel diğer monitörde ve sol kenarda aynı yolu aynalayabiliyor mu?

Instruments kullanılırsa önce SwiftUI ve Core Animation profilleriyle bakılmalıdır. İlk optimizasyon hedefi “daha kısa duration” değil, animasyon sırasında yeniden layout edilen görünüm sayısını azaltmaktır.

## Kabul kriterleri

- [ ] Açılış ilk tıklama karesinde tepki veriyor.
- [ ] Sağ kenarda ray sabit, panel sola açılıyor; sol kenarda hareket aynalanıyor.
- [ ] Görev metinleri açılış/kapanış sırasında yeniden satırlanmıyor.
- [ ] İçerik panelden bağımsız bir yönde kaymıyor veya ölçeklenmiyor.
- [ ] Açılış sonunda bounce/overshoot yok.
- [ ] Kapanış açıkça daha kısa ama ani değil.
- [ ] Aç-kapat-aç hızlı tekrarında jump veya flash yok.
- [ ] Eski completion yeni state'i bozmuyor.
- [ ] İçerik kapanış tamamlanana kadar mount edilmiş kalıyor, sonra kaldırılıyor.
- [ ] Panel açıkken farklı rail ikonuna geçiş frame animasyonunu tekrar başlatmıyor.
- [ ] Reduce Motion açıkken konumsal animasyon yok; kısa cross-fade var.
- [ ] Sol/sağ kenar, farklı panel genişlikleri ve farklı ekran ölçeklerinde davranış aynı.

## Önerilen uygulama sırası

1. `panelContentHost` için sabit width/height ekle.
2. Gerçek uygulamada aç/kapat kaydı al; metin reflow probleminin kaybolduğunu doğrula.
3. `motionPhase`, mount ve visibility state'lerini ekle.
4. `motionRevision` ile gecikmeli iş/completion yarışlarını kapat.
5. Motion token'larını tek kaynağa taşı.
6. Curve ve süreleri en son ayarla.
7. Hızlı tersine çevirme testinde frame jump kalırsa özel, retarget edilebilir frame animator'ı değerlendir.

Bu sıra önemlidir: önce geometri ve lifecycle düzeltilir, sonra hissiyat ayarlanır. Aksi hâlde daha iyi bir easing curve, yeniden satırlanan metni veya erken kaldırılan içeriği gizleyemez.
