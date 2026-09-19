# 00 — Genel Bakış

## Problem

Şu an görevler düz bir metin listesinde tutuluyor (checkbox'lı bir not dosyası).
Sorunlar:

- Görevi görmek için pencereyi açıp aramak gerekiyor → görev **görünmez** oluyor
- Kategori/proje ayrımı yok, her şey tek listede
- Hatırlatma, tarih, öncelik yok
- Telefonda erişim yok
- Tek satırlık bir görevin altındaki detaylar (mail adresi, notlar) satıra sıkışıyor

## Çözüm

> **Kapsam güncellemesi (2026-08-22):** Bu proje artık **sadece macOS**.
> iOS uygulaması, iCloud/CloudKit sync ve iOS widget'ları kapsam dışı bırakıldı.
> iOS widget'ların yerini **macOS widget** (Notification Center / masaüstü,
> WidgetKit) alıyor. Veri tamamen yerel (SwiftData, tek cihaz). Test ve
> dağıtımı kullanıcı kendisi yapacak — bu dokümanlardaki 09-PRODUCTION.md
> referans amaçlı kalıyor, aktif plana dahil değil.

İki katmanlı bir görev sistemi:

1. **Ana uygulama (macOS)** — tam liste, proje/etiket yönetimi, arama, detay
2. **Floating widget (macOS)** — ekranda istediğin yere sürüklediğin küçük bir kapsül.
   Üzerine gelince genişleyip bugünün görevlerini gösteriyor, oradan tik atabiliyorsun.
   Odaktaki uygulamayı **hiç değiştirmiyor** (nonactivating panel). Kenara
   gizlenme (peek tutamağı) ve "her zaman açık kal" (pinned) modları var.
3. **macOS Widget** — Notification Center'a veya masaüstüne eklenebilen,
   bugünün görevlerini gösteren salt-okunur WidgetKit widget'ı.

## Tasarım dili

macOS 26 / iOS 26 **Liquid Glass**: gerçek zamanlı refraksiyon, arkadaki içeriği bükerek
geçiren cam katmanlar, birbirine yaklaşınca birleşen (morph) şekiller.
Native API'ler (`.glassEffect`, `GlassEffectContainer`) kullanılacak — elle
blur/opacity taklidi **yapılmayacak**.

Referans: 2. ekran görüntüsündeki takvim widget'ı — küçük kapsül, hover'da açılan kart,
yumuşak gölge, yuvarlak köşe, yarı saydam katman.

## Hedef kullanıcı

Tek kullanıcı (kendim), tek cihaz (Mac). Yani:

- Çok kullanıcılı senaryo, paylaşım, ekip özelliği **yok**
- Backend **yok**
- iCloud/CloudKit sync **yok** — tamamen yerel SwiftData store
- iOS uygulaması **yok**
- Hesap sistemi **yok**
- Analytics/telemetry **yok**

Bu, kapsamı ciddi ölçüde küçültüyor. Test ve dağıtımı kullanıcı kendisi
yapacağı için [09-PRODUCTION.md](09-PRODUCTION.md) sadece referans amaçlı.

## Kapsam sınırları (v1'de YOK)

- iOS uygulaması — kapsam dışı
- iCloud/CloudKit sync — kapsam dışı
- Takvim entegrasyonu (EventKit) — v2
- Doğal dil ile görev girişi ("yarın 3'te X") — v2
- Alt görevler (subtask) — v2
- Tekrar eden görevler (recurring) — v2
- Apple Watch — v2
- İşbirliği / paylaşım — hiç

## Başarı kriteri

v1 "bitti" sayılır eğer:

- [ ] macOS'ta panel açılıyor, sürükleniyor, pozisyonu kalıcı, hover'da genişliyor
- [ ] Panel kenara gizlenebiliyor (peek tutamağı) ve "pinned" modda hep açık kalabiliyor
- [ ] Panelden görev tamamlanabiliyor, odak kaybolmuyor
- [ ] Görev ekleme/silme/düzenleme ana pencerede çalışıyor
- [ ] macOS widget bugünün görevlerini gösteriyor
- [ ] Global kısayol (⌥Space) ile hızlı görev ekleme çalışıyor
- [ ] Uygulama login'de otomatik başlıyor
- [ ] Testler geçiyor (dağıtım/imzalama kullanıcı tarafından yapılacak)
