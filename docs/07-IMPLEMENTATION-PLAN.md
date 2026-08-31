# 07 — Uygulama Planı

> **Kapsam güncellemesi (2026-08-22):** iOS uygulaması, iCloud sync ve iOS
> widget'ları kapsam dışı bırakıldı. Eski 9 fazlık plan buna göre kısaltıldı.
> Test/dağıtım (eski Faz 9) kullanıcı tarafından yapılacak, plana dahil değil.

7 faz. Her faz kendi başına çalışan/derlenen bir durum bırakır. Fazları
**tek tek** uygula, hepsini birden verme.

---

## Faz 0 — Ön hazırlık ✅ tamamlandı

```bash
brew install xcodegen
```

Team ID (`V793RH49BX`) `project.yml`'e işlendi, imzalama doğrulandı.

---

## Faz 1 — İskelet ✅ tamamlandı

- `project.yml`, `xcodegen generate`
- 2 target: `GlassDoKit`, `GlassDo-macOS` (+ `GlassDoKitTests`)
- macOS app "GlassDo" yazan bir pencereyle açılıyor ve derleniyor
- Git repo başlatıldı, `.gitignore` eklendi

**Kabul:** `xcodebuild -scheme GlassDo-macOS build` başarılı. ✅

> **Not:** XcodeGen 2.46'da her target'a (framework dahil) `info: path: ...`
> vermek zorunlu, yoksa `codesign` "bundle format unrecognized" ile patlıyor.
> Detay: [02-ARCHITECTURE.md](02-ARCHITECTURE.md#projectyml).

---

## Faz 2 — Veri katmanı ✅ tamamlandı

- `Task`, `Project`, `Tag`, `Priority` modelleri ([03-DATA-MODEL.md](03-DATA-MODEL.md))
- `AppStore.makeContainer()` — tamamen yerel store (CloudKit yok)
- Seed data: 7 proje + `11-SEED-DATA.md`'deki görev listesi
- `GlassDoKitTests`: 6 test, hepsi geçiyor

**Kabul:** Testler geçiyor, in-memory + local container kuruluyor. ✅

> **Not:** `#Predicate` içinde force-unwrap çalışma anında crash ediyor;
> `.flatMap` ile çözüldü. Detay: [03-DATA-MODEL.md](03-DATA-MODEL.md#sık-kullanılan-sorgular).

---

## Faz 3 — macOS ana pencere

- `NavigationSplitView`: sidebar (akıllı listeler + projeler) / liste / detay
- Görev ekle (Enter ile), sil (Delete), tamamla (tık)
- Detay paneli: başlık, not, proje, tarih, öncelik
- Sidebar'a Liquid Glass uygula
- Arama alanı (`.searchable`)

**Kabul:** Ana pencerede tam CRUD çalışıyor, veriler kalıcı.

---

## Faz 4 — Floating panel ✅ tamamlandı (Faz 12 ile değiştiriliyor)

> **Not:** Faz 4'ün ilk sürümü (yüzen kapsül + hover + kenara gizlenme + pin)
> uygulandı ve çalışıyor. Ancak tasarım, kullanıcının verdiği kenar-rayı
> referansı doğrultusunda **yeniden ele alındı** →
> [12-EDGE-RAIL.md](12-EDGE-RAIL.md). Sıradaki iş o dosyadaki 12.1–12.7
> adımları; `Sources/macOS/Panel/` içeriği orada belirtildiği gibi değişecek.

### Faz 4 (eski tasarım — referans)

[05-FLOATING-WIDGET.md](05-FLOATING-WIDGET.md) baştan sona uygula:

- `FloatingPanel: NSPanel`
- `FloatingPanelController` + `NSHostingView` bağlama
- Collapsed kapsül görünümü
- Hover → expand (gecikmeli)
- Sürükleme + pozisyon kalıcılığı + clamp
- Kenar snap + **kenara gizlenme (peek tutamağı)**
- **Pinned (her zaman açık) modu**
- Panelden tik atma, **odak kaybı olmadan**
- `MenuBarExtra`: Widget'ı göster/gizle, paneli pinle, ana pencere, ayarlar, çık

**Kabul:** Xcode odaktayken panelde tik at → Xcode odakta kalıyor. Panel
sürüklenip yeniden başlatıldığında aynı yerde açılıyor. Kenara gizlenme ve
pinned mod çalışıyor.

> Burada takılırsan: önce sabit boyutlu, hover'sız, sürüklenebilir bir panel
> çıkar. Sonra hover'ı ekle. En son peek/pinned modlarını ekle. Hepsini aynı
> anda debug etme.

---

## Faz 12 — Edge Rail + Liquid Glass Panel ⭐ (SIRADAKİ, en riskli faz)

Tam şartname: **[12-EDGE-RAIL.md](12-EDGE-RAIL.md)**

Kenara yapışık ikon rayı; hover'da **tek cam yüzey** olarak akarak açılıp görev
listesini gösteriyor. Üç mod: Rail / Sliver (otomatik gizlenme) / Pinned.
Mevcut `Sources/macOS/Panel/` içeriğinin yerine geçer.

Adımlar: 12.1 geometri+durum (saf, testli) → 12.2 ray → 12.3 hover+morph →
12.4 ikonlar+pin → 12.5 sliver+kenar değiştirme → 12.6 erişilebilirlik →
12.7 cila.

**Kabul:** [12-EDGE-RAIL.md](12-EDGE-RAIL.md) § 12 kabul kriterleri.

---

## Faz 5 — macOS Widget (WidgetKit)

- `GlassDoWidgets-macOS` app-extension target'ı, App Group'a bağlı
- `TodayWidget`: bugünün görevleri (Notification Center / masaüstü)
- `AppIntent` ile widget içinden tik atma (interaktif widget)
- Ana app'te her yazma sonrası `WidgetCenter.shared.reloadAllTimelines()`
- Widget'ta Liquid Glass — `containerBackground` ile
- Boş durum: "Bugün için görev yok 🎉"

**Kabul:** Widget'ta tik atınca ana app'te de tamamlanmış görünüyor.

---

## Faz 6 — macOS cilası

- Global kısayol ⌥Space → Quick Add penceresi (`KeyboardShortcuts` paketi)
- `SMAppService.mainApp.register()` — login'de başlat
- Ayarlar penceresi: Genel / Panel / Kısayollar sekmeleri
  · Panel opaklığı slider · Panel boyutu · Panelde hangi liste gösterilsin
  · Kenara gizlenme aç/kapa · Pinned mod varsayılanı · Login'de başlat toggle
- Yerel bildirimler (`UNUserNotificationCenter`) — bitiş tarihinde
- İlk çalıştırma karşılama ekranı

**Kabul:** Login'de otomatik açılıyor, ⌥Space her yerden çalışıyor.

---

## Test + dağıtım — kullanıcı tarafından

[08-TESTING.md](08-TESTING.md) ve [09-PRODUCTION.md](09-PRODUCTION.md) referans
olarak duruyor ama aktif plana dahil değil — imzalama, notarization, DMG/App
Store adımlarını kullanıcı kendisi yürütecek.

---

## Zaman tahmini

| Faz | Sonnet 5 ile | Durum |
|---|---|---|
| 0 | 20 dk | ✅ |
| 1 | 30 dk | ✅ |
| 2 | 1 sa | ✅ |
| 3 | 2–3 sa | ✅ |
| 4 | 3–5 sa | ✅ (12 ile değiştiriliyor) |
| **12** | **3–5 sa (debug ağırlıklı)** | **⏳ sıradaki** |
| 5 | 2–3 sa | ⏳ |
| 6 | 2–3 sa | ⏳ |

## Risk sıralaması

1. **Faz 12 hover + morph + odak** — AppKit/SwiftUI köprüsünde ince davranışlar
2. **Faz 5 widget veri paylaşımı** — App Group yanlışsa widget boş kalır
3. Liquid Glass API'leri — yeni, örnek az; `~/.claude/skills/apple-design/` ve
   Apple dokümanına bak
