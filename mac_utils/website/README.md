# GlassDo — tanıtım sitesi

Astro 5 + Tailwind CSS v4 ile yazılmış, tamamen statik, üç dilli
(EN / TR / RU) tanıtım sitesi. Firebase Hosting'e `dist/` klasörü yükleniyor.

## Neden Astro

Eski site Next.js'ti ve tanıtım sayfası için 860 KB JavaScript gönderiyordu.
Daha kötüsü: bölümler `opacity: 0` ile başlayıp JavaScript ile beliriyordu,
yani betik çalışmadan sayfa bomboştu.

Astro varsayılan olarak **paket göndermiyor**. Burada kalan tek JavaScript,
`<head>` ve `<body>` sonundaki iki küçük satır içi betik (beliriş animasyonu
ve menünün dışına tıklayınca kapanması); ikisi de olmasa sayfa tam olarak
çalışıyor. Dil menüsü ve SSS akordeonu artık `<details>` ile, yani tarayıcının
kendi yetenekleriyle çalışıyor. i18n yönlendirmesi ve sitemap üretimi de
çatının kendisinde yerleşik.

## Komutlar

```bash
npm install
npm run dev      # http://localhost:4321
npm run build    # dist/
npm run preview
```

Yayına alma (depo kökünden):

```bash
npm --prefix mac_utils/website run build && firebase deploy --only hosting
```

## Klasörler

| Yol | Ne |
| --- | --- |
| `src/pages/` | Yönlendirme: `/[lang]` ve `/[lang]/[page]` |
| `src/content/` | Tüm metinler: `en.json`, `tr.json`, `ru.json` |
| `src/components/` | Başlık, altbilgi, ikonlar, bölüm bileşenleri |
| `src/layouts/Base.astro` | `<head>`: canonical, hreflang, OG, JSON-LD |
| `src/i18n/ui.ts` | Gezinme/altbilgi metinleri |
| `src/i18n/meta.ts` | Sayfa başlıkları ve açıklamaları |
| `scripts/make-og.py` | `public/og.png` üretir |

### İçerik nereden geldi

Sitenin Next.js kaynağı kaybolmuştu; elde yalnızca Firebase'e dağıtılmış
derleme vardı. O derlemenin içindeki sunucu yükünde (`out/<dil>.txt`) bütün
metinlerin **yapılandırılmış hâli** duruyordu; `src/content/*.json` oradan
çıkarıldı. Yani hiçbir metin yeniden çevrilmedi, kullanıcının yazdığı gibi
duruyor — üstelik eski HTML'de hiç basılmayan üç SSS cevabı da geri geldi
(React yalnızca açık olan cevabı basıyordu, diğerleri arama motoruna hiç
görünmüyordu).

## SEO

Eski sitede olmayan, şimdi olan: sayfa başına başlık/açıklama, `canonical`,
üç dil + `x-default` için `hreflang`, Open Graph ve Twitter kartı, `og.png`,
`SoftwareApplication` JSON-LD, `robots.txt`, dil karşılıklarını da içeren
`sitemap-index.xml`, kalıcı önbellek başlıkları.

## Eksik ekran görüntüleri

`public/screenshots/` içinde beş dosya bekleniyor: `hero.png`, `edge-rail.png`,
`tasks-notes.png`, `system-monitoring.png`, `widgets-menu-bar.png`. Bunlar
yayındaki sitede de eksikti (404 veriyorlardı). Dosya yoksa kutuda kırık
görsel yerine sade bir yer tutucu çiziliyor; PNG'yi klasöre koyup yeniden
derlediğinde kendiliğinden gerçek görsele dönüyor.

## `out/` klasörü

Firebase'den geri indirilen **eski derlenmiş çıktı**. `_next/static/chunks/`
altındaki karma adlı yüzlerce dosya bu yüzden duruyor — kaynak kod değil,
derleyici çıktısı. Karşılaştırma için tutuluyor; yeni site doğrulandıktan
sonra silinebilir (commit `1a91310` içinde kayıtlı kalıyor).
