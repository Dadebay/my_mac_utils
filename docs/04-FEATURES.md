# 04 — Özellikler

Öncelik etiketleri: **[MVP]** ilk çalışan sürüm · **[v1]** bitmiş sayılması için gerekli · **[v2]** sonra

## Ortak (uygulama geneli — artık tek platform: macOS)

| # | Özellik | Öncelik | Durum |
|---|---|---|---|
| C1 | Görev ekle / düzenle / sil | MVP | ⏳ Faz 3 |
| C2 | Tamamlandı işaretle (tik) + geri al | MVP | ⏳ Faz 3 |
| C3 | Proje ile gruplama, renk + SF Symbol ikon | MVP | ✅ model hazır (Faz 2) |
| C4 | Öncelik (none/low/medium/high) | v1 | ✅ model hazır (Faz 2) |
| C5 | Bitiş tarihi + saat | v1 | ✅ model hazır (Faz 2) |
| C6 | Notlar (çok satırlı, görev detayında) | v1 | ✅ model hazır (Faz 2) |
| C7 | Etiketler (tag) | v1 | ✅ model hazır (Faz 2) |
| C8 | Arama (başlık + not içinde) | v1 | ⏳ Faz 3 |
| C9 | Sürükle-bırak sıralama | v1 | ⏳ Faz 3 |
| C10 | Akıllı listeler: Bugün / Yaklaşan / Tümü / Tamamlanan | v1 | ⏳ Faz 3 |
| C12 | Yerel bildirim (bitiş tarihinde) | v1 | ⏳ Faz 8 |
| C13 | Alt görevler | v2 | — |
| C14 | Tekrar eden görevler | v2 | — |
| C15 | Doğal dil girişi ("yarın 15:00 X") | v2 | — |
| C16 | Takvim (EventKit) okuma | v2 | — |

> `C11 iCloud sync` kapsam dışı bırakıldı — bkz. [00-OVERVIEW.md](00-OVERVIEW.md).

## macOS'a özel

| # | Özellik | Öncelik |
|---|---|---|
| M1 | **Floating panel** — sürüklenebilir, hover'da genişler | MVP |
| M2 | Panel pozisyonu kalıcı (yeniden başlatınca aynı yerde) | MVP |
| M3 | Panel odak çalmaz (nonactivating) | MVP |
| M4 | Panel tüm Space'lerde ve full-screen üstünde görünür | v1 |
| M5 | Ekran kenarına yapışma (snap) + kenara gizlenme (peek tutamağı) | v1 |
| M5b | **Pinned mod** — panel hiç küçülmeden her zaman açık dursun | v1 |
| M6 | Menü bar ikonu (`MenuBarExtra`) | MVP |
| M7 | Global kısayol ⌥Space → Quick Add penceresi | v1 |
| M8 | Login'de otomatik başlat (`SMAppService`) | v1 |
| M9 | Panel opaklık / boyut ayarı | v1 |
| M10 | Ana pencere: sidebar + liste + detay (3 kolon) | v1 |
| M11 | **macOS Widget** (Notification Center / masaüstü) — bugünün görevleri | v1 |
| M12 | Widget içinden tik atma (interaktif, AppIntent) | v1 |
| M13 | Shortcuts.app aksiyonları | v2 |

> iOS'a özel özellikler (liste ekranı, Lock Screen widget, Control Center,
> Dynamic Island, Apple Watch) kapsam dışı — iOS uygulaması artık planda yok.

## Ekranlar

### macOS ana pencere
```
┌─────────────┬───────────────────────────┬──────────────────┐
│  SIDEBAR    │       GÖREV LİSTESİ       │     DETAY        │
│             │                           │                  │
│  ○ Bugün    │  ☐ provider kod    ↑ ●    │  Başlık          │
│  ○ Yaklaşan │  ☐ geocoding       = ●    │  ┌────────────┐  │
│  ○ Tümü     │  ☑ splash screen          │  │ Notlar     │  │
│             │                           │  └────────────┘  │
│  PROJELER   │  + Yeni görev             │  Proje  ▾        │
│  ▪ İş       │                           │  Tarih  ▾        │
│  ▪ Shipaton │                           │  Öncelik ▾       │
│  ▪ Freelance│                           │  Etiketler       │
└─────────────┴───────────────────────────┴──────────────────┘
   NavigationSplitView, sidebar Liquid Glass, liste düz
```

### macOS floating panel — kapalı (collapsed)
```
    ╭──────────────────────────╮
    │ ◉  3 görev · Bugün    ⌄ │   ~180 × 40 pt, glass kapsül
    ╰──────────────────────────╯
```

### macOS floating panel — hover (expanded)
```
    ╭────────────────────────────────────╮
    │  Bugün                    ⚙︎  ✕   │
    │  ────────────────────────────────  │
    │  ☐ provider kod            İş  ↑  │
    │  ☐ geocoding etme     Delivery  =  │
    │  ☐ nav bar animasyon  Shipaton     │
    │  ────────────────────────────────  │
    │  + Hızlı ekle…                     │
    ╰────────────────────────────────────╯
        ~320 × 260 pt, GlassEffectContainer
```

Detay: [05-FLOATING-WIDGET.md](05-FLOATING-WIDGET.md)
