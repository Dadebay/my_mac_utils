# Animasyon planları

`improve-animations` denetiminden çıkan, uygulanmayı bekleyen planlar.
Her plan kendi içinde tamdır: dosya yolları, mevcut kod, hedef değerler ve
doğrulama adımları planın içinde yazılıdır — bu README'yi okumadan da
uygulanabilirler.

| # | Başlık | Önem | Kategori | Durum |
|---|---|---|---|---|
| [001](001-panel-satir-cikis-easing.md) | Panel görev satırının çıkış animasyonundaki `ease-in`'i kaldır | HIGH | Easing & duration | TODO |
| [002](002-reduced-motion-bosluklari.md) | Panel dışındaki hareketlere reduced-motion kapısı ekle | MEDIUM | Accessibility | TODO |
| [003](003-settings-window-chrome-and-sidebar.md) | Settings başlık çubuğunu ve sidebar üst hizasını birleştir | HIGH | Cohesion & physicality | TODO |
| [004](004-widgets-settings-responsive-gallery.md) | Widgets ayar galerisini responsive ve taşmasız yap | HIGH | Cohesion, layout & motion | TODO |
| [005](005-settings-sidebar-navigation.md) | Settings sidebar gezinmesini doğrudan ve hafif yap | HIGH | Purpose, interruptibility & cohesion | DONE |
| [006](006-processor-temperature-widget-hierarchy.md) | İşlemci sıcaklığı widget hiyerarşisini düzelt | HIGH | Purpose, cohesion & missed opportunity | DONE |
| [007](007-overview-widget-equal-grid.md) | Sistem özeti widget kartlarını eşit grid'e kilitle | HIGH | Cohesion, layout & performance | DONE |
| [008](008-panel-icon-content-switch-motion.md) | Açık panelde ikonlar arası geçişi izole et | HIGH | Purpose, interruptibility, cohesion & performance | TODO |

## Önerilen sıra

1. **008** — Açık panelde farklı rail ikonuna geçerken içerik anlık değişiyor
   ve global selection transaction ikon ağacını etkiliyor; en görünür güncel
   motion kusuru budur.
2. **005** — Tıklamayı engelleyen gesture kullanıcıyı Widgets sayfasında
   kilitliyor; önce navigasyon tekrar çalışır hâle gelmeli.
3. **003** — Pencere kromu ve sidebar güvenli alanı düzeltilmeli; bütün
   Settings sayfalarının ortak kabuğudur.
4. **004** — Ardından Widgets galerisinin layout taşması kaldırılmalı; 003'ün
   oluşturduğu son kullanılabilir genişlik üzerinden doğrulanmalı.
5. **006** — İşlemci sıcaklığında ana değer/grafik hiyerarşisini ve yanıltıcı
   peak normalizasyonunu düzeltir.
6. **007** — Büyük Sistem Özeti kartlarını deterministik 2×3 grid'e kilitler.
7. **001** — İki satırlık easing değişikliği, widget'ın en
   sık tekrarlanan etkileşimini (görev tamamlama) doğrudan etkiliyor.
8. **002** — Erişilebilirlik boşluğu; hissi değil, kapsamı genişletiyor.

## Bağımlılıklar

001 ve 002 birbirinden bağımsızdır. 003 önce, 004 sonra uygulanmalıdır: 004'ün
responsive doğrulaması 003'ün son pencere/sidebar geometrisini kullanır.

- 001 → `Sources/GlassDoKit/DesignSystem/Tokens.swift`, `Sources/macOS/Panel/PanelTaskListView.swift`
- 002 → `Sources/macOS/MainWindow/TaskRow.swift`, `Sources/macOS/MainWindow/ContentView.swift`, `Sources/macOS/WindowSwitcher/SwitcherOverlayView.swift`
- 003 → `Sources/macOS/App/GlassDoApp.swift`, `Sources/macOS/Settings/SettingsView.swift`
- 004 → `Sources/macOS/Settings/WidgetsSettingsSection.swift`
- 005 → `Sources/macOS/Settings/SettingsView.swift`
- 006 → `Sources/Widgets/SystemWidgetViews.swift`, `Sources/Widgets/WidgetChrome.swift`
- 007 → `Sources/Widgets/SystemOverviewWidgetView.swift`
- 008 → `Sources/GlassDoKit/DesignSystem/Tokens.swift`, `Sources/macOS/Panel/EdgeShellView.swift`, `Sources/macOS/Panel/EdgeRailView.swift`, `Sources/macOS/Panel/RailIconButton.swift`

## Denetimde bulunup plana dönüştürülmeyenler

Önceki genel denetimde aşağıdakiler doğrulandı ama plana yazılmadı — ileride
istenirse `improve-animations` yeniden çalıştırılabilir:

- **MEDIUM · Cohesion/Feedback** — Repo'nun kendi `PressScaleButtonStyle`'ı
  (`.pressScale`) yalnızca 3 yerde kullanılıyor; 21 ikon butonu (`TaskRow` düzenle/sil,
  `SystemMonitorView` kapat, `PoppedNoteView` başlık düğmeleri, `SwitcherOverlayView`
  trafik ışıkları, `FloatingBubbleView`) basıldığında hiçbir geri bildirim vermiyor.
- **MEDIUM · Physicality** — `TaskRow.swift:140` onay işareti `.scale(scale: 0.3)`
  ile beliriyor ("yoktan var olma"); aynı onay kutusu panelde ve notta
  `.symbolEffect(.replace)` kullanıyor.
- **LOW · Cohesion & tokens** — `Motion.expand` ve `Motion.collapse`
  (`Tokens.swift:12-13`) artık hiçbir yerde kullanılmıyor; ayrıca 15 adet elle
  yazılmış zayıf `.easeOut(duration:)` değeri, repo'nun kendi güçlü
  `timingCurve(0.23, 1, 0.32, 1)` eğrisinde birleştirilebilir.

## Kasıtlı olduğu için raporlanmayanlar

Bu kararlar denetimde incelendi ve **doğru** bulundu — değiştirilmemeli:

- `WindowSwitcherSettings.defaultFadeOutEnabled = false` — klavye ile açılan bir
  yüzey anında kapanmalı.
- `WindowSwitcherSettings.defaultApparitionDelayMs = 100` — çok hızlı ⌥+Tab'de
  bindirimin göz kırpmasını engelliyor.
- `EdgePanelController.popAnimate` taşmalı eğrisi (`0.34, 1.56, 0.64, 1`) —
  sürükleme bırakışında momentum taşıyan hareket için bounce doğrudur.
- `RowShatterOverlay` damlalarındaki `ease-in` — aşağı düşen parçacıklar
  hızlanır, bu yerçekimidir.
- `RailIconButton` rozetindeki `drawingGroup()` — Liquid Glass harmanlamasından
  kaçmak için, gerekçesi kodda yazılı.
