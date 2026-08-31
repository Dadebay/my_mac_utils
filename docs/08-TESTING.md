# 08 — Test Planı

> **Kapsam:** macOS-only. Sync/iOS/CloudKit test bölümleri kaldırıldı.
> Test/dağıtım kullanıcı tarafından yürütülecek — bu dosya referans.

## 1. Unit testler — Swift Testing

Xcode 26 ile `XCTest` yerine yeni `Testing` framework'ü kullan.

```swift
import Testing
import SwiftData
@testable import GlassDoKit

@MainActor
struct TaskTests {

    private func makeContext() throws -> ModelContext {
        let container = try AppStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("Görev tamamlanınca completedAt doluyor")
    func completion() throws {
        let ctx = try makeContext()
        let task = Task(title: "provider kod")
        ctx.insert(task)

        task.isCompleted = true
        task.completedAt = .now

        #expect(task.isCompleted)
        #expect(task.completedAt != nil)
    }

    @Test("Bugün filtresi tamamlananları dışlıyor")
    func todayFilter() throws {
        let ctx = try makeContext()
        let open = Task(title: "açık")
        let done = Task(title: "kapalı"); done.isCompleted = true
        ctx.insert(open); ctx.insert(done)

        let results = try ctx.fetch(
            FetchDescriptor<Task>(predicate: Task.todayPredicate())
        )
        #expect(results.count == 1)
        #expect(results.first?.title == "açık")
    }

    @Test("Öncelikler doğru sıralanıyor", arguments: Priority.allCases)
    func priorityRoundTrip(_ p: Priority) {
        let task = Task(title: "x")
        task.priority = p
        #expect(task.priority == p)
    }
}
```

### Şema / seed testi (CloudKit kapsam dışı olduğu için ayrı bir uyumluluk testi gerekmiyor)

```swift
@Test("Yerel container kuruluyor ve seed data doluyor")
@MainActor
func localContainerSeeds() throws {
    _ = try AppStore.makeContainer(inMemory: false)
}
```

✅ Bu ve idempotency testi Faz 2'de `SeedDataTests.swift` olarak yazıldı.

### Test edilecekler / edilmeyecekler

**Test et:** predicate'ler, tarih hesaplamaları, sıralama mantığı, panel frame
hesabı (`expandedFrame` — saf fonksiyon, kolay test edilir), renk hex parse,
App Intent davranışı.

**Etme:** SwiftUI view hiyerarşisi (kırılgan), SwiftData'nın kendisi,
AppKit pencere yaşam döngüsü (UI testine bırak).

### `expandedFrame` testi — panel mantığının kalbi

```swift
@Test("Sağ kenardaki panel sola doğru genişliyor")
func expandsLeftOnRightEdge() {
    let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let collapsed = NSRect(x: 1700, y: 900, width: 190, height: 44)
    let expanded = PanelGeometry.expandedFrame(
        from: collapsed, visible: screen,
        size: CGSize(width: 340, height: 300))

    #expect(expanded.maxX <= screen.maxX - 8)
    #expect(expanded.minX >= screen.minX)
}
```

> Bunun test edilebilmesi için `expandedFrame`'i controller'dan ayırıp
> `enum PanelGeometry` içinde **static, saf fonksiyon** yap. Sonnet'e bunu söyle.

---

## 2. UI testler — XCUITest

```swift
final class GlassDoUITests: XCTestCase {
    func testAddAndCompleteTask() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-InMemoryStore"]
        app.launch()

        app.buttons["newTask"].click()
        app.typeText("test görevi\n")

        let row = app.staticTexts["test görevi"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))

        app.checkBoxes.firstMatch.click()
        XCTAssertTrue(app.staticTexts["1 tamamlandı"].exists)
    }
}
```

Launch argümanı ile in-memory store kullan — testler gerçek verini bozmasın.

---

## 3. Manuel test checklist

### Floating panel (macOS) — en kritik bölüm

- [ ] Panel açılışta görünüyor
- [ ] Panel sürükleniyor (her yerinden, sadece başlıktan değil)
- [ ] Uygulama kapatılıp açılınca **aynı pozisyonda**
- [ ] Hover'da genişliyor, fare çıkınca küçülüyor
- [ ] Genişleme titremiyor (fare kenarda gezerken açılıp kapanmıyor)
- [ ] **Ekranın sağ kenarında** genişleyince ekran dışına taşmıyor
- [ ] **Ekranın alt kenarında** genişleyince taşmıyor
- [ ] Xcode odaktayken panelde tik at → **Xcode odakta kalıyor**
- [ ] Safari full-screen'deyken panel görünüyor
- [ ] Başka bir Space'e geçince panel geliyor
- [ ] ⌘` uygulama pencere döngüsünde panel çıkmıyor
- [ ] Mission Control'de garip davranmıyor
- [ ] İkinci monitörde çalışıyor; monitör çıkarılınca ana ekrana dönüyor
- [ ] Uyku/uyanma sonrası panel yerinde
- [ ] Ekran çözünürlüğü değişince panel görünür alanda kalıyor
- [ ] Kenara yapışınca 1.5 sn sonra tutamağa küçülüyor
- [ ] Tutamağa hover/tık ile panel geri geliyor
- [ ] Pin butonu açıkken panel hiç küçülmüyor/gizlenmiyor (hover'dan bağımsız)
- [ ] Pin kapatılınca normal hover + gizlenme davranışına dönüyor

### Liquid Glass görünüm

- [ ] Açık renkli duvar kağıdında okunuyor
- [ ] Koyu duvar kağıdında okunuyor
- [ ] Beyaz bir Safari sayfasının üstünde okunuyor
- [ ] Videonun üstünde okunuyor
- [ ] Light/Dark mode geçişinde bozulmuyor
- [ ] Erişilebilirlik → "Şeffaflığı azalt" açıkken opak yüzey
- [ ] "Hareketi azalt" açıkken animasyon yok
- [ ] Accent rengi değişince takip ediyor

### macOS Widget

- [ ] Widget bugünün görevlerini gösteriyor (Notification Center / masaüstü)
- [ ] Widget'ta tik at → ana app'te tamamlanmış
- [ ] Ana app'te tik at → widget güncelleniyor (`reloadAllTimelines`)
- [ ] Widget'ta görev yokken boş durum düzgün
- [ ] Widget small/medium boyutlarda düzgün

### Genel

- [ ] Login'de otomatik başlıyor
- [ ] ⌥Space her uygulamadan çalışıyor
- [ ] Boş liste durumu düzgün
- [ ] 500+ görevle liste akıcı
- [ ] Çok uzun görev başlığı taşmıyor
- [ ] Türkçe karakterler (ı, ğ, ş, ö, ü, ç) her yerde doğru
- [ ] Bellek: panel açıkken idle < 80 MB
- [ ] CPU: idle %0 civarı (animasyon yokken)

---

## 4. Komutlar

```bash
# Tüm testler (macOS)
xcodebuild test -scheme GlassDo-macOS -destination 'platform=macOS'
```

```bash
# Sadece derleme kontrolü (hızlı)
xcodebuild -scheme GlassDo-macOS -configuration Debug build 2>&1 | grep -E 'error|warning'
```

```bash
# Uygulamayı çalıştır
open ~/Library/Developer/Xcode/DerivedData/GlassDo-*/Build/Products/Debug/GlassDo.app
```

```bash
# Panel loglarını izle
log stream --predicate 'subsystem == "com.dadebay.glassdo"' --level debug
```


## 5. Performans ölçümü

Instruments ile:
- **Time Profiler** — panel expand animasyonu sırasında 60fps korunuyor mu
- **Allocations** — panel 100 kez açılıp kapanınca bellek büyüyor mu (leak)
- **Energy Log** — idle'da enerji etkisi "Low" olmalı

Bunları Faz 9'da bir kez yap, her fazda değil.
