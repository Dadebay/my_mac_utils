# Planlar

Her plan kendi içinde tamdır: dosya yolları, mevcut kod, hedef değerler ve
doğrulama adımları planın içinde yazılıdır — bu dosyayı okumadan da
uygulanabilirler.

## Hareket (animasyon) planları

`improve-animations` denetiminden çıkanlar.

| # | Başlık | Önem | Kategori | Durum |
|---|--------|------|----------|-------|
| [012](012-panel-memory-segment-swap.md) | Apps ↔ macOS & System dilim geçişini yönlü ve animasyonlu yap | HIGH | Physicality · Cohesion | **DONE** |
| [013](013-panel-memory-list-data-updates.md) | Süreç listesindeki veri değişimlerini animasyona bağla | HIGH | Interruptibility | **DONE** |

> **Not:** 012 ve 013 uygulandı. Uygulamada plandan iki sapma var:
> `.animation` bağı dış `ScrollView`'a değil iç `LazyVStack`'e konuldu
> (dıştaki `.id(selectedSegment)` görünümü yeniden kurduğu için oraya
> konulsaydı takas sırasında satır animasyonu da tetiklenirdi), ve bölüm
> başlığına `.contentTransition(.opacity)` eklendi (denetimdeki "kaçırılmış
> fırsat" maddesi).

### Uygulama sırası

**012 → 013.** İkisi de `Sources/macOS/Panel/PanelMemoryView.swift` içindeki
aynı `appList` görünümünün sonuna değiştirici ekliyor. 012 önce uygulanırsa
013'ün 3. adımı son değiştirici sırasını (`.id` → `.transition` →
`.animation`) açıkça söylüyor. Ters sırada uygulanırsa aynı sonuca varılır
ama sıra elle kontrol edilmeli.

İkisi farklı kullanıcı olaylarını düzeltiyor, o yüzden ayrı ayrı da
uygulanabilirler:

- **012** — kullanıcı karoya bastığında (Apps ↔ macOS & System)
- **013** — liste kendiliğinden yenilendiğinde (iki saniyede bir)

### Denetimde bulunup plana dönüştürülmeyenler

Bu turda kullanıcı yalnızca dilim geçişi ve liste güncellemesini seçti.
Aşağıdaki bulgu doğrulandı ama plana yazılmadı:

- **LOW · Cohesion & tokens** — `PanelMemoryView.swift:248` süreç listesinin
  grup girişinde kademe (stagger) yok. AUDIT §7 30–80ms öneriyor; ilk ~6
  satırla sınırlı, etkileşimi engellemeyen bir gecikme uygun olurdu.

### Kaçırılmış fırsatlar (denetim notu)

- `PanelMemoryView.swift:218` bölüm başlığı ("RUNNING APPS" ↔ "SYSTEM
  PROCESSES") anında değişiyor. 012 uygulandıktan sonra listeyle aynı anda
  sönümlenmesi geçişi tek bir olay hâline getirir.

## Diğer planlar

| # | Başlık |
|---|--------|
| [009](009-macos-productivity-pro-features.md) | macOS üretkenlik Pro özellikleri |
| [010](010-promocodes-admin-revenuecat-firebase.md) | Promosyon kodu yönetimi (RevenueCat + Firebase) |
| [011](011-task-detail-panel-redesign-sonnet-brief.md) | Görev detay paneli yeniden tasarımı |
| [website-devam-eden-isler](website-devam-eden-isler.md) | Web sitesi devam eden işler |
