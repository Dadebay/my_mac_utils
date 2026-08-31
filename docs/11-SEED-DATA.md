# 11 — Başlangıç Verisi

Mevcut not dosyasındaki görevler, projelere dağıtılmış hâli. `SeedData.swift`
bunu ilk çalıştırmada (store boşsa) oluşturacak.

```swift
// Sources/GlassDoKit/Store/SeedData.swift
// Sadece store tamamen boşsa çalışır.
```

## İş / Aykitap — `#5E9BFF` · `briefcase`

- Aykitap — provider kod — her iki platformda güncelle — mutirows@gmail.com
- İş görüşmesi — Kıbrıs

## Food Delivery — `#FF9F43` · `bicycle`

- Errorlar: zakaz gelince adminka uwadamleniye gelmeli
- Yerleşim yerini el ile yazmasın — kartadan geocoding, tek "yerimi seç" ile
- Çek meselesi çözülmeli
- Kurye dostavka pulu hasaplanyşy görülmeli
- Kurye delivery ettikten sonra "tabşyrdym" diye endpoint gönderilmeli

## Shipaton — `#8B5CF6` · `car`

- Bottom nav bar üzerinde arabalar geçsin — modeller (video veya animasyon)
- Firebase landing page
- Klima çalıştırma animasyonu
- Araba çalıştırma animasyonu
- Splash screen — logo in / Sonky logo çalışması
- carDX
- Maşyn işledýän aparat tapmaly

## Öğrenme — `#34C759` · `book`

- React Native (Zafer Ayan) — 4. ders
- React Native (Zafer Ayan) — 5. ders
- YouTube kanalı açmalı

## Freelance — `#FF453A` · `dollarsign`

- Atelyam — 100$
- Samalyot projesi — bekliyor — toplantı
- WhatsApp erişim izni — Pulse Transfer app
- Salon app — tasarım yapılmalı
- Lionhires — Cyprus — Tech Interview → Final Interview → Soft skills

## Kişisel — `#64D2FF` · `person`

- Zagran uzatılmalı
- Rysgal bankadan kart alınmalı
- Sakamoto Days

## Todo App (bu proje) — `#FF9F43` · `checklist`

- Todo app for myself

---

## Not

Bu liste ilk sürümü doldurmak için. Sonnet 5 bunları `Task` nesnesi olarak
oluştururken:

- Hiçbirine `dueDate` verme (tarih bilgisi yok)
- Öncelikleri `.none` bırak — sen sonradan atarsın
- `sortIndex` dosyadaki sırayı korusun
- Uzun satırları başlık + not olarak böl:
  başlığa ilk cümle, geri kalanı `notes` alanına
  (örn. başlık: "provider kod", not: "her iki platformda güncelle — mutirows@gmail.com")
