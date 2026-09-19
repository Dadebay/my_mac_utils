# 012 — Apps ↔ macOS & System dilim geçişini yönlü ve animasyonlu yap

- **Status**: DONE (Uygulandı — bkz. `PanelMemoryView.swift` `swapTransition`, `.id(selectedSegment)`.)
- **Commit**: 51ab82c
- **Severity**: HIGH
- **Category**: Physicality & origin · Cohesion & tokens
- **Estimated scope**: 1 dosya (`Sources/macOS/Panel/PanelMemoryView.swift`), ~30 satır

## Problem

Kenar panelindeki bellek görünümünde legend'daki iki karo — "Apps" (sol) ve
"macOS & System" (sağ) — alttaki süreç listesini değiştiriyor. Geçiş
kullanıcıya **animasyonsuz** görünüyor: eski liste yok oluyor, yenisi
yerinde beliriyor.

Kodda bir animasyon *niyeti* var ama çalışmıyor:

```swift
// Sources/macOS/Panel/PanelMemoryView.swift:157-163 — mevcut
            Button {
                withAnimation(Motion.toggle) {
                    selectedSegment = segment.id
                    confirmingQuit = nil
                }
            } label: {
                legendLabel(segment)
            }
```

```swift
// Sources/macOS/Panel/PanelMemoryView.swift:248-272 — mevcut
    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(listedProcesses) { app in
                    PanelAppUsageRow(
                        app: app,
                        fraction: fraction(of: app),
                        valueText: Self.text(app.memoryBytes),
                        canQuit: app.isTerminable,
                        isConfirmingQuit: confirmingQuit == app.id,
                        onBeginQuit: { beginConfirming(app) },
                        onConfirmQuit: { confirmQuit(app) }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .mask(scrollEdgeMask)
```

Üç ayrı sorun:

1. `ForEach(listedProcesses)` iki farklı diziyi aynı konumda gösteriyor ve
   `LazyVStack` bir `ScrollView` içinde. Lazy kapsayıcı ekran dışındaki
   satırları hiç oluşturmadığı için satırlardaki `.transition(.opacity)`
   (`PanelMemoryView.swift:398`) çoğu zaman hiç tetiklenmiyor — geçiş
   anında oluyor.
2. `Motion.toggle` yanlış token. Tanımı `Animation.snappy(duration: 0.2)`
   (`Sources/GlassDoKit/DesignSystem/Tokens.swift`) ve `.snappy` hafif
   yaylanma taşıyor. Repoda "panel zaten açıkken içeriği değiştir" durumu
   için ayrı tokenlar var: `Motion.panelContentSwapIn` / `panelContentSwapOut`.
3. Geçişin yönü yok. Legend iki sütunlu bir grid: "Apps" solda, "macOS &
   System" sağda (`PanelMemoryView.swift:139-152`). Liste yön taşımadığı
   için hangi karodan geldiği bilgisi kayboluyor.

Ayrıca bölüm başlığındaki sayaç, bu dosyada `.contentTransition` taşımayan
tek sayı — Apps↔System geçişinde 8'den 42'ye sıçrıyor:

```swift
// Sources/macOS/Panel/PanelMemoryView.swift:228-234 — mevcut
                Text("\(listedProcesses.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
```

## Target

Dilime basıldığında liste yönlü olarak değişiyor: "macOS & System" seçilince
yeni liste sağdan girip eski liste sola çıkıyor, "Apps" seçilince tam tersi.
Sayaç ve başlık aynı anda sönümleniyor. Reduce Motion açıkken kayma yok,
yalnızca sönümlenme kalıyor.

Kullanılacak kesin değerler (hepsi repoda zaten tanımlı, yenisi
üretilmeyecek):

```swift
// Sources/GlassDoKit/DesignSystem/Tokens.swift — mevcut tanımlar
Motion.panelContentSwapIn   // .timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
Motion.panelContentSwapOut  // .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
```

Hedef kod:

```swift
// target — appList
    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(listedProcesses) { app in
                    PanelAppUsageRow(/* değişmiyor */)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .mask(scrollEdgeMask)
        // Listenin tamamı tek bir kimlik taşıyor: dilim değişince SwiftUI
        // satırları tek tek eşleştirmeye çalışmıyor, bloğu komple
        // değiştiriyor. Lazy kapsayıcıda satır bazlı geçişin çalışmama
        // sorunu böylece ortadan kalkıyor.
        .id(selectedSegment)
        .transition(swapTransition)
    }

// target — yeni yardımcı
    /// Liste, seçilen karonun bulunduğu taraftan giriyor: "Apps" solda,
    /// "macOS & System" sağda. Yön mekânsal olarak doğru olmazsa geçiş
    /// "bir yerden geldi" değil "bir anda değişti" diye okunuyor.
    private var swapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let entering: Edge = selectedSegment == .system ? .trailing : .leading
        let leaving: Edge = selectedSegment == .system ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: entering).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity)
        )
    }
```

```swift
// target — legendEntry butonu
            Button {
                withAnimation(Motion.panelContentSwapIn) {
                    selectedSegment = segment.id
                    confirmingQuit = nil
                }
            } label: {
                legendLabel(segment)
            }
```

```swift
// target — sayaç rozeti
                Text("\(listedProcesses.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
```

## Repo conventions to follow

- **Hareket tokenları** `Sources/GlassDoKit/DesignSystem/Tokens.swift`
  içindeki `Motion` enum'unda. Yeni eğri/süre **tanımlama** — yukarıda adı
  geçenleri kullan.
- **Reduce Motion kalıbı**: bu dosyada zaten
  `private var dataAnimation: Animation? { reduceMotion ? nil : Motion.dataUpdate }`
  (`PanelMemoryView.swift:44-46`) ve satır düzeyinde
  `contentTransition(reduceMotion ? .identity : .numericText())`
  (`PanelMemoryView.swift:88`) var. Aynı kalıbı izle.
- **Yönlü geçiş exemplar'ı**: `Sources/macOS/Panel/PanelFolderShelfView.swift`
  içinde liste ↔ tarayıcı geçişi tam olarak bu biçimde yazılı — liste
  `.move(edge: .leading)`, tarayıcı `.move(edge: .trailing)`, Reduce Motion'da
  ikisi de `.opacity`. Ona bak.
- Yorumlar Türkçe ve **nedeni** anlatıyor, ne yaptığını değil.

## Steps

1. `Sources/macOS/Panel/PanelMemoryView.swift:158` — `withAnimation(Motion.toggle)`
   çağrısını `withAnimation(Motion.panelContentSwapIn)` yap. **Yalnızca
   `legendEntry` içindeki bu çağrı**; `beginConfirming` (`:297`) ve
   `:301`'deki `Motion.toggle` kullanımlarına dokunma — onlar kapatma
   onayı için, farklı bir etkileşim.
2. Aynı dosyada `appsSection` içindeki sayaç `Text`ine (`:228`)
   `.contentTransition(reduceMotion ? .identity : .numericText())` ekle;
   `.monospacedDigit()` ile `.foregroundStyle(.secondary)` arasına koy.
3. `appList`'in sonuna (`:272`, `.mask(scrollEdgeMask)` satırının hemen
   altına) `.id(selectedSegment)` ve `.transition(swapTransition)` ekle.
4. `swapTransition` hesaplanan özelliğini `appList`'in hemen ardına,
   `fraction(of:)` fonksiyonundan önce ekle (yukarıdaki hedef kodun aynısı,
   yorumu dahil).

## Boundaries

- Yalnızca `Sources/macOS/Panel/PanelMemoryView.swift` değişecek.
- `PanelAppUsageRow` içindeki `.transition(.opacity)` (`:398`) **kalacak** —
  planı 013 ona dayanıyor.
- `Tokens.swift`'e yeni token ekleme.
- Görünüm hiyerarşisini, dolguları, renkleri, yazı tiplerini değiştirme —
  yalnızca hareket.
- `SystemMonitorView.swift`'e (ana penceredeki karşılığı) dokunma.
- Adımlardaki kod bulduğunla eşleşmiyorsa (commit 51ab82c'den beri kaymışsa)
  **dur ve bildir**, doğaçlama yapma.

## Verification

- **Mekanik**:
  ```
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug \
    -derivedDataPath build/DerivedData build
  ```
  `BUILD SUCCEEDED` bekleniyor, yeni uyarı çıkmamalı.
- **His kontrolü**: uygulamayı çalıştır, kenar panelini aç, bellek ikonuna
  geç, sonra:
  - "macOS & System" karosuna bas → liste **sağdan** girmeli, eski liste
    sola çıkmalı. "Apps"a geri bas → tam tersi yönde olmalı. Yön iki
    tarafta da aynıysa `swapTransition` yanlış bağlanmıştır.
  - Sayaç rozeti (8 → 42) yuvarlanarak değişmeli, sıçramamalı.
  - İki karoya hızlıca art arda bas: hareket kesilip yeni yöne dönmeli,
    baştan başlamamalı.
  - Sistem Ayarları → Erişilebilirlik → Görüntü → **Hareketi azalt**'ı aç,
    paneli yeniden aç: kayma tamamen kalkmalı, yalnızca sönümlenme kalmalı;
    sayaç anında değişmeli.
- **Done when**: geçişin yönü seçilen karonun tarafını izliyor, sayaç
  yuvarlanıyor, Reduce Motion'da hiçbir yatay hareket yok ve build temiz.
