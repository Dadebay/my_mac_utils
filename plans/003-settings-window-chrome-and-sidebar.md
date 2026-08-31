# 003 — Settings başlık çubuğunu ve sidebar üst hizasını birleştir

- **Status**: TODO
- **Commit**: unborn (repository has no `HEAD` yet)
- **Severity**: HIGH
- **Category**: Cohesion & physicality
- **Estimated scope**: 2 dosya, ~90 satır

## Problem

Settings penceresi standart `NavigationSplitView` ve görünür pencere başlığıyla
kuruluyor. Sidebar'ın kendi içeriği yalnızca `List` ile başlıyor; başlık çubuğu
alanı sidebar malzemesine katılmadığı için sol sütun üst kenara ulaşmıyor.
Ortadaki `Settings` başlığı ayrı bir katman gibi görünüyor, sidebar toggle ise
boş alanda tek başına kalıyor. Kullanıcının istediği uygulama kimliği de yok.

```swift
// Sources/macOS/Settings/SettingsView.swift:127-142 — mevcut
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 214, ideal: 234, max: 300)
        } detail: {
            detail
        }
        .navigationTitle(L10n.settingsTitle)
        .frame(
            minWidth: 760, idealWidth: 880, maxWidth: .infinity,
            minHeight: 540, idealHeight: 660, maxHeight: .infinity
        )
    }
```

```swift
// Sources/macOS/Settings/SettingsView.swift:163-184 — mevcut
    private var sidebar: some View {
        List(selection: selectionBinding) {
            ...
        }
        .listStyle(.sidebar)
        .searchable(...)
    }
```

Settings sahnesi de pencere kromunu özelleştirmiyor:

```swift
// Sources/macOS/App/GlassDoApp.swift:37-42 — mevcut
        Settings {
            SettingsView(switcherController: switcherController)
        }
        .windowResizability(.contentMinSize)
```

Trafik ışıkları yeniden çizilmemeli; ancak içerikle aralarında net bir güvenli
alan bulunmalı. Şu an pencerenin üst bölgesi kimlik, hiyerarşi ve hizalama
açısından boş ve kopuk.

## Target

Pencere, macOS System Settings benzeri birleşik bir krom kullanır:

- Yerel close/minimize/zoom düğmeleri korunur; elle taklit edilmez.
- Sidebar malzemesi pencerenin en üst kenarına kadar devam eder.
- Sol üstte trafik ışıklarının altında/yanında çakışmayan 52 pt yüksekliğinde
  bir sidebar header bulunur.
- Header'da `NSApp.applicationIconImage` 28×28 pt, yanında `GlassDo` 15 pt
  semibold ve `Settings` 11 pt secondary bulunur.
- Trafik ışığı bandında en az 20 pt yatay ve 14 pt dikey nefes alanı görünür;
  hiçbir içerik düğmelerin hit-area'sına girmez.
- Ortadaki yinelenen pencere başlığı gizlenir. Sidebar toggle, header'ın sağında
  hizalı kalır veya sistem toolbar'ında doğal konumunu korur; boşlukta yüzmez.
- Sidebar araması header'dan 10–12 pt sonra başlar; ilk seçim satırı üst kenara
  yapışmaz.

Pencere ilk açılırken ya da yeniden boyutlandırılırken layout animasyonu
oynatılmaz. Bölüm değişimi mevcut taşmasız yayla kalır:

```swift
.spring(response: 0.28, dampingFraction: 1)
```

`accessibilityReduceMotion` açıkken bölüm geçişi 0.16 sn saf opacity olur;
konum/ölçek hareketi eklenmez.

## Repo conventions to follow

- Yerel AppKit pencere düğmeleri korunur. `NSButton` ile kırmızı/sarı/yeşil
  daire üretme.
- SwiftUI görünümünün pencereye erişmesi gerekirse küçük, dosya-içi bir
  `NSViewRepresentable` configurator kullan; kalıcı state veya yeni bağımlılık
  ekleme.
- `SettingsView` halihazırda `@Environment(\.accessibilityReduceMotion)` ve
  `.spring(response: 0.28, dampingFraction: 1)` kullanıyor
  (`SettingsView.swift:109,288`). Yeni hareket bu sözleşmeyi bozmasın.
- App icon için asset adı tahmin etme; sistemin gerçek ikonunu
  `NSApp.applicationIconImage` üzerinden göster.
- Sidebar seçimini ve hover vurgusunu `List` çizmeye devam etsin.

## Steps

1. `Sources/macOS/App/GlassDoApp.swift` — `Settings` sahnesinde Settings
   penceresini birleşik titlebar stiline getir. Hedef AppKit durumları:
   `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`,
   `.fullSizeContentView` ve `.unified` toolbar stili. Bunu yalnızca Settings
   penceresine uygulayan küçük bir window configurator ekle; ana pencereye ve
   panel pencerelerine dokunma. Configurator birden çok `updateNSView` çağrısında
   idempotent olmalı.

2. Aynı configurator içinde standart trafik ışıklarını yeniden konumlandırma.
   Yalnızca sistemin belirlediği yerel düğmeleri kullan ve bunların superview
   hiyerarşisini bozma. İçerik tarafında en az 52 pt güvenli üst bant bırakarak
   istenen padding'i sağla. Düğmelerin kendisine transform/animation uygulama.

3. `Sources/macOS/Settings/SettingsView.swift` — sidebar'ı bir `VStack(spacing: 0)`
   içine al. En üstte yeni `settingsSidebarHeader` yer alsın; altında divider ve
   mevcut `List` olsun. Header tam genişlikte 52 pt yüksekliğinde olsun ve
   traffic-light safe area ile çakışmaması için en az 20 pt leading inset
   kullansın.

4. `settingsSidebarHeader` içinde gerçek uygulama ikonunu
   `Image(nsImage: NSApp.applicationIconImage)` ile 28×28 pt göster. Yanına
   `GlassDo` (`.system(size: 15, weight: .semibold)`) ve yerelleştirilmiş
   `L10n.settingsTitle` (`.system(size: 11)`, `.secondary`) ekle. Uzun çeviriler
   tek satırda truncate olmalı; icon sıkışmamalı.

5. Sidebar header ve liste aynı sidebar material üzerinde tek yüzey gibi
   görünmeli. Araya ayrı, koyu kart zemini ekleme. Divider `primary.opacity(0.08)`
   seviyesini geçmesin.

6. `.navigationTitle(L10n.settingsTitle)` ile üretilen yinelenen ortalanmış
   başlığı kaldır/gizle. Pencerenin VoiceOver title'ı kaybolmamalı; AppKit
   `window.title = L10n.settingsTitle` olarak kalsın.

7. Detail bölümünün mevcut opacity transition'ını koru. Reduced motion için
   mevcut `nil` yerine kısa bir saf fade kullan:
   ```swift
   .animation(
       reduceMotion
           ? .easeOut(duration: 0.16)
           : .spring(response: 0.28, dampingFraction: 1),
       value: selection
   )
   ```
   Sidebar/header yerleşimine veya pencere resize'ına `.animation` ekleme.

## Boundaries

- Trafik ışıklarını özel SwiftUI şekilleriyle yeniden oluşturma, renklendirme,
  gizleme veya işlevlerini yeniden yazma.
- Ana pencere kromuna, edge paneline ve window switcher'a dokunma.
- Sidebar'ın mevcut kategori gruplarını, aramayı veya selection binding'ini
  değiştirme.
- Pencere resize olayını spring ile animate etme; imleci 1:1 takip etmeli.
- App icon için yeni raster asset üretme.
- Yeni paket/bağımlılık ekleme.
- Mevcut kod planla eşleşmiyorsa doğaçlama yapmadan DUR ve bildir.

## Verification

- **Mechanical**:
  ```bash
  xcodebuild -project GlassDo.xcodeproj -scheme GlassDo-macOS -configuration Debug -derivedDataPath build/DerivedData build
  ```
- **Visual**: Settings'i normal pencere, maximized ve minimum 760×540 ölçüsünde;
  dark/light/System temalarında aç.
  - Sidebar zemini üst kenara kadar kesintisiz ulaşmalı.
  - Uygulama ikonu ve iki satır kimlik görünmeli.
  - Trafik ışıkları ikon/header/search ile çakışmamalı; üçü de tıklanmalı.
  - Ortada ikinci bir `Settings` başlığı kalmamalı.
  - Sidebar collapse/expand düğmesi boşlukta yüzmemeli.
- **Motion**: Kategoriler arasında hızlıca gez. İçerik taşmamalı veya scale
  yapmamalı. Reduce Motion açıkken yalnızca 160 ms fade görülmeli.
- **Done when**: Sol üst krom tek bir hizalı kompozisyon gibi görünüyor,
  trafik ışıkları tamamen yerel kalıyor ve minimum boyutta hiçbir içerik üst
  banda taşmıyor.

