# 001 — Panel görev satırının çıkış animasyonundaki `ease-in`'i kaldır

- **Status**: TODO
- **Commit**: (henüz commit yok — plan, commit'lenmemiş çalışma ağacına göre yazıldı)
- **Severity**: HIGH
- **Category**: Easing & duration
- **Estimated scope**: 2 dosya, ~15 satır

## Problem

Kenar panelindeki görev satırı, tamamlandığında `ease-in` ile 400 ms boyunca
kayboluyor. `ease-in` yavaş başlar — yani kullanıcının tam olarak baktığı ilk
anları geciktirir ve etkileşimi ağır hissettirir. UI'da giren ya da çıkan her
öğe `ease-out` kullanmalıdır. Ayrıca 400 ms, UI animasyonları için 300 ms'lik
bütçenin üzerinde. Bu, widget'ın en sık tekrarlanan etkileşimi (görev
tamamlama) olduğu için etkisi büyük.

İkinci bir sorun: `.opacity` ve `.scaleEffect`, `.overlay { RowShatterOverlay() }`
modifier'ından SONRA uygulandığı için damla efekti de satırla birlikte soluyor.
`RowShatterOverlay` zaten kendi içinde 0.4 sn'lik bir sönme animasyonu
çalıştırıyor (`Sources/macOS/Panel/PanelTaskListView.swift:198`), yani damlalar
şu anda ÇİFT kez soluyor ve satırın süresine kilitlenmiş durumdalar.

```swift
// Sources/macOS/Panel/PanelTaskListView.swift:99-105 — mevcut
        .overlay {
            if isShattering { RowShatterOverlay() }
        }
        .opacity(isShattering ? 0 : 1)
        .scaleEffect(isShattering ? 0.85 : 1, anchor: .leading)
        .animation(.easeIn(duration: Self.shatterDuration), value: isShattering)
    }
```

```swift
// Sources/macOS/Panel/PanelTaskListView.swift:153-155 — mevcut
            withAnimation(.easeIn(duration: Self.shatterDuration)) {
                shatteringTasks.insert(taskID)
            }
```

İlgili sabitler:

```swift
// Sources/macOS/Panel/PanelTaskListView.swift:15-16 — mevcut
    private static let completionDelay: Double = 3.5
    private static let shatterDuration: Double = 0.4
```

## Target

Satırın kendi çıkışı, repo'nun zaten kullandığı güçlü ease-out eğrisiyle
240 ms'de tamamlanır. Damla efekti (`RowShatterOverlay`) kendi 0.4 sn'lik
ömrünü bağımsız yaşar — satırın opaklık animasyonundan etkilenmez.

```swift
// hedef — Sources/GlassDoKit/DesignSystem/Tokens.swift, Motion enum'una eklenecek
    public static let rowExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
```

```swift
// hedef — Sources/macOS/Panel/PanelTaskListView.swift, row(_:) fonksiyonunun sonu
        .opacity(isShattering ? 0 : 1)
        .scaleEffect(isShattering ? 0.85 : 1, anchor: .leading)
        .animation(Motion.rowExit, value: isShattering)
        .overlay {
            if isShattering { RowShatterOverlay() }
        }
    }
```

```swift
// hedef — Sources/macOS/Panel/PanelTaskListView.swift, toggle(_:) içinde
            withAnimation(Motion.rowExit) {
                shatteringTasks.insert(taskID)
            }
```

`Self.shatterDuration` (0.4) DEĞİŞMEZ ve silinmez: satır 156'daki
`try? await _Concurrency.Task.sleep(for: .seconds(Self.shatterDuration))`
damlaların düşüşünü beklemek için gerekli, ve `RowShatterOverlay` içindeki
0.4 sn'lik damla animasyonuyla eşleşiyor. Yalnızca satırın kendi görsel
çıkışı 0.24 sn'ye iner.

## Repo conventions to follow

- Paylaşılan animasyon sabitleri `Sources/GlassDoKit/DesignSystem/Tokens.swift`
  içindeki `public enum Motion` bloğunda yaşar. Yeni eğriyi oraya ekle, dosya
  içinde elle `Animation.timingCurve(...)` yazma.
- `cubic-bezier(0.23, 1, 0.32, 1)` bu repo'nun standart güçlü ease-out
  eğrisidir. **Taklit edilecek örnek** — `Sources/GlassDoKit/DesignSystem/Tokens.swift:15`:
  ```swift
  public static let iconVisibility = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
  ```
- `PanelTaskListView.swift` zaten `import GlassDoKit` içeriyor ve `Motion.toggle`
  kullanıyor (satır 129, 136, 144) — `Motion.rowExit` için ek import gerekmez.

## Steps

1. `Sources/GlassDoKit/DesignSystem/Tokens.swift` — `public enum Motion` bloğunun
   içine, `panelContentDisappearance` tanımından sonra şu satırı ekle:
   ```swift
       /// Bir liste satırının listeden düşerken yaptığı çıkış. Giren/çıkan her
       /// öğe gibi ease-out — ease-in, kullanıcının tam baktığı ilk anları
       /// geciktirdiği için UI'da kullanılmaz.
       public static let rowExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
   ```

2. `Sources/macOS/Panel/PanelTaskListView.swift` — `row(_:)` fonksiyonunun
   sonundaki (mevcut satır 99-104) modifier zincirini, `.overlay` bloğu
   `.animation` satırından SONRA gelecek şekilde yeniden sırala ve `.easeIn`
   yerine yeni token'ı kullan:
   ```swift
        .opacity(isShattering ? 0 : 1)
        .scaleEffect(isShattering ? 0.85 : 1, anchor: .leading)
        .animation(Motion.rowExit, value: isShattering)
        // Damlalar satırın opaklık animasyonunun DIŞINDA kalmalı: kendi
        // 0.4 sn'lik sönme animasyonlarını çalıştırıyorlar, satırla birlikte
        // ikinci kez soldurulurlarsa efekt yarıda kesiliyor.
        .overlay {
            if isShattering { RowShatterOverlay() }
        }
   ```

3. `Sources/macOS/Panel/PanelTaskListView.swift` — mevcut satır 153'teki
   `withAnimation(.easeIn(duration: Self.shatterDuration)) {` ifadesini
   `withAnimation(Motion.rowExit) {` ile değiştir. Blok gövdesi
   (`shatteringTasks.insert(taskID)`) aynen kalır.

## Boundaries

- `RowShatterOverlay` (mevcut satır 171-205) içindeki
  `.animation(.easeIn(duration: 0.4).delay(droplet.delay), value: animate)`
  satırına **DOKUNMA**. Oradaki `ease-in` kasıtlı ve doğrudur: damlalar aşağı
  düşerken hızlanır, bu yerçekimidir.
- `completionDelay` (3.5) ve `shatterDuration` (0.4) sabitlerini **değiştirme
  veya silme**. İkisi de zamanlama sözleşmesinin parçası.
- `Motion.toggle` kullanan diğer `withAnimation` çağrılarına (satır 129, 136,
  144) dokunma.
- Başka hiçbir dosyada easing değiştirme. Bu plan yalnızca panel satırının
  çıkışını kapsar.
- Yeni bağımlılık ekleme.
- Adımlardaki kod bulduğun kodla eşleşmiyorsa (plan yazıldığından beri
  değişmişse) DUR ve doğaçlama yapmadan bildir.

## Verification

- **Mechanical**: Proje kökünden şu komut hatasız `** BUILD SUCCEEDED **` vermeli:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath build/DerivedData build
  ```
- **Feel check**: Uygulamayı çalıştır
  (`open build/DerivedData/Build/Products/Debug/GlassDo-macOS.app`), ekran
  kenarındaki widget'ta görev ikonuna tıklayıp paneli aç, bir görevin onay
  kutusuna tıkla ve 3.5 saniye bekle. Şunları doğrula:
  - Satır kaybolmaya **hızlı başlıyor**, yavaş sürünerek değil.
  - Yeşil damlalar satır kaybolduktan sonra da düşmeye devam ediyor ve
    yarıda kesilmiyor — düzeltmeden önce satırla aynı anda sönüyorlardı.
  - Aynı görevi arka arkaya işaretleyip 3.5 sn dolmadan tekrar tıklayarak
    iptal et; animasyon sıfırdan yeniden başlamıyor, mevcut durumundan
    geri dönüyor.
- **Done when**: `PanelTaskListView.swift` içinde `row(_:)` ve `toggle(_:)`
  fonksiyonlarında hiç `.easeIn` kalmadı (yalnızca `RowShatterOverlay`
  içindeki damla animasyonunda kaldı) ve `Motion.rowExit` iki yerde de
  kullanılıyor. Şu komut yalnızca 1 sonuç (satır 198, damlalar) dönmeli:
  ```bash
  grep -n "easeIn" Sources/macOS/Panel/PanelTaskListView.swift
  ```
