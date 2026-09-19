# 013 — Süreç listesindeki veri değişimlerini animasyona bağla

- **Status**: DONE (Uygulandı — `.animation(dataAnimation, value: listedProcesses)` `LazyVStack`'e bağlandı.)
- **Commit**: 51ab82c
- **Severity**: HIGH
- **Category**: Interruptibility · Missed opportunities
- **Estimated scope**: 1 dosya (`Sources/macOS/Panel/PanelMemoryView.swift`), ~10 satır

## Problem

Bellek paneli iki saniyede bir yenileniyor. Yenilemede süreç listesi
değişiyor: yeni bir uygulama açılıyor, biri kapanıyor, bellek kullanımı
değiştiği için sıralama kayıyor. Bunların **hiçbiri animasyonlu değil** —
satırlar zıplayarak beliriyor, kayboluyor ve yer değiştiriyor.

Sebep basit: görünümün üst yarısında üç ayrı animasyon bağı var, alt
yarısında hiç yok.

```swift
// Sources/macOS/Panel/PanelMemoryView.swift:102 — özet, bağlı
        .animation(dataAnimation, value: controller.memory)

// Sources/macOS/Panel/PanelMemoryView.swift:134 — çubuk, bağlı
        .animation(dataAnimation, value: controller.memory)

// Sources/macOS/Panel/PanelMemoryView.swift:151 — legend, bağlı
        .animation(dataAnimation, value: controller.memory)
```

```swift
// Sources/macOS/Panel/PanelMemoryView.swift:248-273 — liste, HİÇBİR bağ yok
    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(listedProcesses) { app in
                    PanelAppUsageRow(/* … */)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .mask(scrollEdgeMask)
    }
```

Satırların kendi `.transition(.opacity)`'si var
(`PanelMemoryView.swift:398`) ama bir geçişin çalışması için değişimin
animasyonlu bir işlem içinde olması gerekiyor. `controller.apps` kendi
zamanlayıcısından güncelleniyor, yani hiçbir `withAnimation` ya da
`.animation(_:value:)` kapsamında değil — geçiş hiç tetiklenmiyor.

## Target

Liste, üst yarısıyla aynı ritimde güncelleniyor: bir satır belirince
sönümlenerek giriyor, kaybolunca sönümlenerek çıkıyor, sıralama değişince
satırlar yeni yerlerine kayıyor.

Kullanılacak değer — repoda tanımlı, yenisi üretilmeyecek:

```swift
// Sources/GlassDoKit/DesignSystem/Tokens.swift — mevcut
Motion.dataUpdate  // .spring(response: 0.4, dampingFraction: 1.0)
```

`dampingFraction: 1.0` kritik sönümlü demek: taşma yok. Bu doğru, çünkü
liste kendiliğinden güncelleniyor — kullanıcının taşıdığı bir momentum
yok, yaylanma burada yalan olurdu.

Hedef kod:

```swift
// target — appList sonu
        .mask(scrollEdgeMask)
        // Liste, özet yarısıyla aynı ritimde güncelleniyor. Bağ
        // `listedProcesses`'e: `controller.memory`'ye bağlansaydı bayt
        // sayısı her değiştiğinde (yani her turda) tetiklenir, oysa asıl
        // mesele satırların gelip gitmesi ve sıra değiştirmesi.
        .animation(dataAnimation, value: listedProcesses)
    }
```

Bunun derlenmesi için `RunningAppUsage`'ın `Equatable` olması gerekiyor.
Değilse `.animation(_:value:)` yerine kimlik dizisine bağla:

```swift
// target — alternatif, RunningAppUsage Equatable değilse
        .animation(dataAnimation, value: listedProcesses.map(\.id))
```

## Repo conventions to follow

- **`dataAnimation` bu dosyada zaten tanımlı** (`PanelMemoryView.swift:44-46`):
  ```swift
  private var dataAnimation: Animation? {
      reduceMotion ? nil : Motion.dataUpdate
  }
  ```
  Reduce Motion ele alınması buradan geliyor — ayrıca dallanma yazma.
- **Exemplar**: `PanelMemoryView.swift:102` — özet bloğunun bağlanma biçimi
  birebir aynı kalıp.
- Yorumlar Türkçe ve **nedeni** anlatıyor.

## Steps

1. `Sources/macOS/Panel/PanelMemoryView.swift` içinde `appList`'in sonundaki
   `.mask(scrollEdgeMask)` satırının altına `.animation(dataAnimation, value: listedProcesses)`
   ekle (yorumuyla birlikte, yukarıdaki hedef koddaki gibi).
2. Derle. `RunningAppUsage` `Equatable` değil diye hata alırsan **modeli
   değiştirme** — bunun yerine bağı `value: listedProcesses.map(\.id)`
   olarak yaz. (`RunningAppUsage` `Identifiable` ve `id` tipi `pid_t`, yani
   `[pid_t]` karşılaştırılabilir.)
3. Plan 012 uygulanmışsa `appList` sonunda `.id(selectedSegment)` ve
   `.transition(swapTransition)` de bulunacak. Sıra şöyle olmalı —
   `.animation` en sonda:
   ```swift
   .mask(scrollEdgeMask)
   .id(selectedSegment)
   .transition(swapTransition)
   .animation(dataAnimation, value: listedProcesses)
   ```

## Boundaries

- Yalnızca `Sources/macOS/Panel/PanelMemoryView.swift` değişecek.
- `RunningAppUsage` modeline, `SystemMonitorController`'a ve yenileme
  aralığına dokunma.
- `PanelAppUsageRow` içindeki `.transition(.opacity)` (`:398`) ve
  `displayedFraction` mekanizması (`:389-403`) **olduğu gibi kalacak** —
  çubuğun 0'dan dolması bilinçli bir karar, kod yorumunda gerekçesi yazılı.
- Kademe (stagger) ekleme: bu planın kapsamı dışında, ayrı bir bulgu.
- Yeni token tanımlama.
- Adımlardaki kod bulduğunla eşleşmiyorsa **dur ve bildir**.

## Verification

- **Mekanik**:
  ```
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug \
    -derivedDataPath build/DerivedData build
  ```
  `BUILD SUCCEEDED` bekleniyor.
- **His kontrolü**: uygulamayı çalıştır, kenar panelini aç, bellek görünümüne
  geç ve listeyi izlerken:
  - Yeni bir uygulama aç (ör. Hesap Makinesi) → satır listeye **sönümlenerek**
    girmeli, aniden belirmemeli. Uygulamayı kapat → sönümlenerek çıkmalı ve
    altındaki satırlar boşluğu yayla kapatmalı.
  - Bir uygulamayı çok bellek tüketen bir işe sok (ör. tarayıcıda ağır bir
    sayfa) → sıralama değişince satırlar kayarak yer değiştirmeli.
  - Paneli 30 saniye açık bırak: liste her iki saniyede bir titremiyor,
    zıplamıyor olmalı. Titriyorsa bağ `controller.memory`'ye yapılmıştır —
    `listedProcesses` olmalı.
  - Sistem Ayarları → Erişilebilirlik → Görüntü → **Hareketi azalt** açıkken
    liste anında güncellenmeli, hiçbir kayma olmamalı.
- **Done when**: satır ekleme/çıkarma/sıralama animasyonlu, boşta beklerken
  liste sakin, Reduce Motion'da hareket yok ve build temiz.
