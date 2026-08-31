# GlassDo — macOS Todo App

> Liquid Glass tasarımlı, ekranda serbest sürüklenebilen "floating widget" ve
> macOS WidgetKit entegrasyonu olan, tek cihazlı (yerel) bir görev yöneticisi.
>
> **Kapsam (2026-08-22 itibarıyla):** Sadece macOS. iOS uygulaması, iCloud sync
> ve iOS widget'ları kapsam dışı — detay için [00-OVERVIEW.md](00-OVERVIEW.md).
> Test/dağıtım kullanıcı tarafından yapılacak.

**Placeholder isim:** GlassDo · **Bundle ID:** `com.dadebay.glassdo` (istediğin gibi değiştir)

---

## Bu klasör nedir?

Bu dokümanlar, uygulamayı **Sonnet 5'e adım adım yazdırmak** için hazırlanmış tam bir
teknik şartname setidir. Her dosya bağımsız okunabilir; `10-PROMPTS.md` içindeki
promptları sırayla kopyala-yapıştır yaparak ilerlemen yeterli.

## Okuma sırası

| # | Dosya | İçerik |
|---|-------|--------|
| 00 | [00-OVERVIEW.md](00-OVERVIEW.md) | Fikir, hedef, kapsam, kısıtlar |
| 01 | [01-TECH-STACK.md](01-TECH-STACK.md) | Hangi dil, neden, alternatiflerin neden elendiği |
| 02 | [02-ARCHITECTURE.md](02-ARCHITECTURE.md) | Target yapısı, modüller, veri akışı |
| 03 | [03-DATA-MODEL.md](03-DATA-MODEL.md) | SwiftData modelleri (yerel store) |
| 04 | [04-FEATURES.md](04-FEATURES.md) | Özellik listesi, MVP / v1 / v2 ayrımı |
| 05 | [05-FLOATING-WIDGET.md](05-FLOATING-WIDGET.md) | Floating panel — *12 tarafından değiştirildi* |
| 06 | [06-LIQUID-GLASS.md](06-LIQUID-GLASS.md) | Tasarım sistemi, glass API'leri, tokenlar |
| 07 | [07-IMPLEMENTATION-PLAN.md](07-IMPLEMENTATION-PLAN.md) | Faz planı |
| 08 | [08-TESTING.md](08-TESTING.md) | Unit / UI / manuel test planı, komutlar |
| 09 | [09-PRODUCTION.md](09-PRODUCTION.md) | İmza, notarization (referans) |
| 10 | [10-PROMPTS.md](10-PROMPTS.md) | Sonnet 5'e verilecek hazır promptlar |
| 11 | [11-SEED-DATA.md](11-SEED-DATA.md) | Başlangıç görev listesi |
| 12 | [12-EDGE-RAIL.md](12-EDGE-RAIL.md) | **En kritik dosya** — kenar rayı + Liquid Glass panel |
| 13 | [13-WIDGETS-MENUBAR.md](13-WIDGETS-MENUBAR.md) | macOS widget'ları + menü çubuğu sistem ölçerleri |
| 14 | [14-SHIPPING-MONETIZATION-REVENUECAT.md](14-SHIPPING-MONETIZATION-REVENUECAT.md) | Satış kanalı, Free/Pro planı, RevenueCat ve release checklist |

## 30 saniyelik özet

- **Dil:** Swift 6 + SwiftUI, tek platform (macOS)
- **Veri:** SwiftData, tamamen yerel store (iCloud/CloudKit yok)
- **macOS floating widget:** `NSPanel` (nonactivating, borderless, floating level)
  + SwiftUI içerik + hover'da genişleyen animasyon + kenara gizlenme (peek) +
  pinned (her zaman açık) modu
- **macOS Widget:** WidgetKit (Notification Center / masaüstü), bugünün görevleri
- **Minimum OS:** macOS 26 (Liquid Glass için gerekli)
- **Test:** Swift Testing (`@Test`) + XCUITest + manuel checklist
- **Dağıtım:** kullanıcı kendisi yapacak (bkz. [09-PRODUCTION.md](09-PRODUCTION.md), referans)
