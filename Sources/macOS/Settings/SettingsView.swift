import AppKit
import GlassDoKit
import SwiftUI

// MARK: - Kategoriler

enum SettingsCategory: String, CaseIterable, Identifiable {
  case general, panelSize, railIcons, menuBar, widgets, network, windowSwitcher, about
  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: L10n.generalSection
    case .panelSize: L10n.panelSizeSection
    case .railIcons: L10n.railIconsSection
    case .menuBar: L10n.s("Menü Çubuğu", "Menu Bar", "Строка меню")
    case .widgets: L10n.s("Widget'lar", "Widgets", "Виджеты")
    case .network: L10n.s("Ağ", "Network", "Сеть")
    case .windowSwitcher: L10n.windowSwitcherSection
    case .about: L10n.aboutSection
    }
  }

  var subtitle: String {
    switch self {
    case .general: L10n.s("Tema ve dil", "Theme and language", "Тема и язык")
    case .panelSize: L10n.s("Ölçüler ve köşeler", "Dimensions and corners", "Размеры и углы")
    case .railIcons:
      L10n.s("Hangi ikonlar görünsün", "Which icons appear", "Какие значки отображать")
    case .menuBar: L10n.s("Sistem ölçerleri", "System readings", "Системные показатели")
    case .widgets:
      L10n.s(
        "Masaüstü ve Bildirim Merkezi", "Desktop and Notification Center",
        "Рабочий стол и Центр уведомлений")
    case .network:
      L10n.s("Kullanım geçmişi", "Usage history", "История использования")
    case .windowSwitcher:
      L10n.s(
        "⌥ + Tab ile pencere değiştirme", "Switch windows with ⌥ + Tab",
        "Переключение окон с ⌥ + Tab")
    case .about: L10n.s("Sürüm bilgisi", "Version info", "Информация о версии")
    }
  }

  var symbolName: String {
    switch self {
    case .general: "gearshape"
    case .panelSize: "arrow.up.left.and.arrow.down.right"
    case .railIcons: "sidebar.right"
    case .menuBar: "menubar.rectangle"
    case .widgets: "square.grid.2x2"
    case .network: "globe"
    case .windowSwitcher: "rectangle.on.rectangle"
    case .about: "info.circle"
    }
  }

  var tint: [Color] {
    switch self {
    case .general: [Color(white: 0.62), Color(white: 0.42)]
    case .panelSize:
      [Color(red: 0.24, green: 0.58, blue: 1.0), Color(red: 0.12, green: 0.38, blue: 0.9)]
    case .railIcons:
      [Color(red: 0.68, green: 0.36, blue: 0.98), Color(red: 0.48, green: 0.22, blue: 0.86)]
    case .menuBar:
      [Color(red: 0.36, green: 0.78, blue: 0.62), Color(red: 0.18, green: 0.58, blue: 0.46)]
    case .widgets:
      [Color(red: 0.98, green: 0.42, blue: 0.62), Color(red: 0.82, green: 0.22, blue: 0.46)]
    case .network:
      [Color(red: 0.24, green: 0.78, blue: 0.74), Color(red: 0.10, green: 0.56, blue: 0.56)]
    case .windowSwitcher:
      [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 0.9, green: 0.44, blue: 0.12)]
    case .about:
      [Color(red: 0.30, green: 0.42, blue: 0.92), Color(red: 0.20, green: 0.28, blue: 0.78)]
    }
  }

}

// MARK: - Kök

struct SettingsView: View {
  let switcherController: WindowSwitcherController

  /// Son bakılan bölüm hatırlanıyor. Ayarlar penceresi çoğunlukla aynı
  /// ayarı bir daha kurcalamak için açılır; her açılışta "Genel"e dönmek
  /// kullanıcıyı bulduğu yerden geri atıyordu.
  @AppStorage("settings.selectedCategory") private var storedSelection = SettingsCategory.general
    .rawValue
  /// Tema bu pencerede seçiliyor; pencerenin kendisi de o seçime uymalı.
  /// Önceden koyu temaya çivilenmişti — açık temayı seçen kullanıcı
  /// seçtiği şeyi tam da seçtiği yerde göremiyordu.
  @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.system.rawValue
  @State private var searchText = ""

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var selection: SettingsCategory {
    SettingsCategory(rawValue: storedSelection) ?? .general
  }

  /// `List` seçimi boşa düşebilir (boş alana tıklama, arama sonucu yok).
  /// nil'e düşünce son geçerli bölüm korunuyor — sağ taraf hiç boşalmasın.
  private var selectionBinding: Binding<SettingsCategory?> {
    Binding(
      get: { selection },
      set: { newValue in
        guard let newValue else { return }
        storedSelection = newValue.rawValue
      }
    )
  }

  var body: some View {
    HSplitView {
      sidebar
        .frame(minWidth: 214, idealWidth: 234, maxWidth: 300)

      detail
        .frame(minWidth: 546, maxWidth: .infinity, maxHeight: .infinity)
    }
    // Settings kenar çubuğu hiçbir zaman gizlenmiyor. NavigationSplitView
    // bu kullanımda kapatılamayan bir sidebar-toggle üretip trafik
    // ışıklarının altında tek başına asılı bırakıyordu; HSplitView aynı
    // yerel ayırıcı/yeniden boyutlandırma davranışını o gereksiz chrome
    // olmadan sağlıyor.
    // Pencere artık büyüyebiliyor. Önceden 660×520'ye çivilenmişti ve
    // uzun bölümler (widget galerisi, pencere değiştirici) alttan
    // kesiliyor, kullanıcının pencereyi açmaktan başka çaresi olmuyordu.
    .frame(
      minWidth: 760, idealWidth: 880, maxWidth: .infinity,
      minHeight: 540, idealHeight: 660, maxHeight: .infinity
    )
    .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .system).colorScheme)
  }

  // MARK: Kenar çubuğu

  private var groups: [SidebarGroup] {
    [
      SidebarGroup(id: "top", title: nil, items: [.general]),
      SidebarGroup(
        id: "panel", title: L10n.s("Panel", "Panel", "Панель"),
        items: [.panelSize, .railIcons, .windowSwitcher]),
      SidebarGroup(
        id: "system", title: L10n.s("Sistem", "System", "Система"), items: [.menuBar, .widgets, .network]),
      SidebarGroup(id: "app", title: L10n.s("Uygulama", "App", "Приложение"), items: [.about]),
    ]
  }

  private var filteredGroups: [SidebarGroup] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return groups }
    return groups.compactMap { group in
      let matches = group.items.filter {
        $0.title.localizedCaseInsensitiveContains(query)
          || $0.subtitle.localizedCaseInsensitiveContains(query)
      }
      guard !matches.isEmpty else { return nil }
      return SidebarGroup(id: group.id, title: group.title, items: matches)
    }
  }

  /// Trafik ışıklarının altındaki alan bir boşluk değil, uygulama kimliği
  /// ve arama için kullanılan gerçek bir başlık. Böylece pencerenin üst
  /// bölgesi tek başına duran bir sidebar simgesi yerine açık bir hiyerarşi
  /// kuruyor.
  private var sidebar: some View {
    VStack(spacing: 0) {
      sidebarIdentity
        .padding(.top, 50)

      settingsSearchField
        .padding(.top, 14)
        .padding(.bottom, 10)

      List(selection: selectionBinding) {
        ForEach(filteredGroups) { group in
          if let title = group.title {
            Section(title) { rows(group.items) }
          } else {
            Section { rows(group.items) }
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(.regularMaterial)
  }

  private var sidebarIdentity: some View {
    HStack(spacing: 11) {
      AppBrandMark(size: 34)

      VStack(alignment: .leading, spacing: 1) {
        Text("GlassDo")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
        Text(L10n.settingsTitle)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .accessibilityElement(children: .combine)
  }

  private var settingsSearchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)

      TextField(
        L10n.s("Ayarlarda ara", "Search settings", "Поиск в настройках"),
        text: $searchText
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))

      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.s("Aramayı temizle", "Clear search", "Очистить поиск"))
      }
    }
    .padding(.horizontal, 11)
    .frame(height: 32)
    .background {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color.primary.opacity(0.065))
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }
    .padding(.horizontal, 14)
  }

  private func rows(_ items: [SettingsCategory]) -> some View {
    ForEach(items) { category in
      SettingsSidebarRowLabel(category: category, isSelected: selection == category)
        .tag(category)
    }
  }
}

private struct SidebarGroup: Identifiable {
  let id: String
  let title: String?
  let items: [SettingsCategory]
}

/// Kategori rozeti. Kenar çubuğu satırı ile sayfa başlığı aynı rozeti
/// kullanıyor — seçilen satırla açılan sayfa arasındaki bağ görsel olarak
/// kurulsun diye (aynı nesne, iki yerde).
private struct SettingsCategoryIcon: View {
  let category: SettingsCategory
  var size: CGFloat = 26
  var radius: CGFloat = 7
  var isSelected = false

  private var accent: Color {
    category.tint.first ?? .accentColor
  }

  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      // Büyük gradient uygulama rozeti yerine macOS sidebar'larındaki
      // gibi sakin, tek tintli bir sembol yüzeyi. Seçim renginin
      // üstündeyken beyaz material kullanarak kontrastı korur.
      .fill(isSelected ? Color.white.opacity(0.18) : accent.opacity(0.14))
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: category.symbolName)
          .font(.system(size: size * 0.48, weight: .medium))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(isSelected ? Color.white : accent)
      }
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(
            isSelected ? Color.white.opacity(0.20) : accent.opacity(0.18),
            lineWidth: 0.5
          )
      }
  }
}

/// Kenar çubuğu satırı. Seçim vurgusunu ve üzerine gelme geri bildirimini
/// `List` kendisi çiziyor — elle çizilen ikinci bir vurgu sistemin
/// kendi vurgusuyla yarışıyordu. Seçiliyken yazı kalınlığı da
/// değişmiyor: kalınlık değişimi satırın genişliğini oynatıp seçim
/// anında gözle görülür bir sıçrama yaratıyordu.
private struct SettingsSidebarRowLabel: View {
  let category: SettingsCategory
  let isSelected: Bool

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 10) {
      SettingsCategoryIcon(category: category, isSelected: isSelected)

      VStack(alignment: .leading, spacing: 1) {
        Text(category.title)
          .font(.system(size: 13))
          .foregroundStyle(.primary)
        Text(category.subtitle)
          // Malzeme üzerindeki ikincil metin `.tertiary` ile
          // okunmuyordu; canlılık için bir kademe yukarı.
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityLabel(category.subtitle)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 2)
    .frame(minHeight: 46)
    .contentShape(Rectangle())
    .background {
      // Seçim vurgusunu `List` kendisi çiziyor; bu yalnızca üzerine
      // gelince beliren, seçimden bağımsız hafif bir geri bildirim.
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.primary.opacity(isHovering && !isSelected ? 0.04 : 0))
    }
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .combine)
  }
}

extension SettingsView {

  // MARK: Ayrıntı

  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
        header

        switch selection {
        case .general: GeneralSettingsSection()
        case .panelSize: PanelSizeSettingsSection()
        case .railIcons: RailIconsSettingsSection()
        case .menuBar: MenuBarSettingsSection()
        case .widgets: WidgetsSettingsSection()
        case .network: NetworkSettingsSection()
        case .windowSwitcher: WindowSwitcherSettingsSection(controller: switcherController)
        case .about: AboutSettingsSection()
        }

        // Kısa sayfalarda (ör. Rail Icons) ScrollView'ın boş pencere
        // yüksekliğini içeriğe ÖNERDİĞİ durumlarda fazladan alanı BURADA,
        // içeriğin ALTINDA yutan tek eleman bu. `maxHeight: .infinity`
        // veren bir dış çerçeveyle aynı işi yapmaya çalışmak (önceki
        // deneme) ScrollView'ın kendi ölçüm geçişiyle çakışıp başlığı
        // pencerenin ortasına doğru itiyordu — burada VStack'in kendi
        // doğal üstten-alta akışı tek doğruluk kaynağı.
        Spacer(minLength: 0)
      }
      .padding(.horizontal, SettingsMetrics.contentHorizontalInset)
      .padding(.top, SettingsMetrics.contentTopInset)
      .padding(.bottom, SettingsMetrics.contentBottomInset)
      // Yalnızca genişlik sınırlanıyor — yükseklik ekseninde hiçbir
      // `maxHeight` yok, o yüzden bu çerçevenin dikey hizalaması (`.leading`
      // == dikeyde `.center`) burada anlamsız/etkisiz: içeriği dikeyde
      // konumlandıran tek şey yukarıdaki `Spacer`.
      .frame(maxWidth: SettingsMetrics.contentMaxWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Bölüm değişince içerik tamamen yeniden kuruluyor: eski
      // satırların (özellikle segmentli seçicilerin) yanlış ölçülmüş
      // boyutlarını miras almasınlar.
      .id(selection)
      .transition(.opacity)
    }
    // Geçiş sönümlü, taşmasız: burada kullanıcının taşıdığı bir momentum
    // yok — sekme değiştirmek bir fırlatma değil. Reduce Motion açıkken
    // kayma/ölçek kalkıyor ama geri bildirim tamamen kaybolmuyor —
    // kısa bir opaklık geçişi kalıyor.
    .animation(
      reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16),
      value: selection
    )
    .scrollBounceBehavior(.basedOnSize)
    .background(.windowBackground)
  }

  /// Sayfa başlığı. Kenar çubuğundaki rozetin büyütülmüş hâli + bölümün
  /// bir satırlık açıklaması. Ortadaki yinelenen pencere başlığının
  /// yerini bu alıyor — sayfanın ne olduğunu tek yerden anlatıyor.
  private var header: some View {
    HStack(spacing: 14) {
      SettingsCategoryIcon(category: selection, size: 48, radius: 11)

      VStack(alignment: .leading, spacing: 3) {
        Text(selection.title)
          .font(.system(size: 28, weight: .semibold))
          // Büyük puntoda harfler olduğundan daha aralıklı görünür;
          // sistem yazı tipinin optik boyutlandırmasıyla aynı yönde
          // hafifçe sıkılıyor.
          .kerning(-0.6)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(selection.subtitle)
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
  }
}

// MARK: - Genel

private struct GeneralSettingsSection: View {
  @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.system.rawValue
  @State private var language = LocalizationManager.shared.language

  var body: some View {
    SettingsCard(title: L10n.appearanceGroup) {
      SettingsSegmentedRow(
        label: L10n.themeLabel,
        selection: $themeRaw,
        options: AppTheme.allCases.map { ($0.rawValue, $0.displayName) }
      )
      SettingsRowDivider()
      SettingsSegmentedRow(
        label: L10n.languageLabel,
        selection: $language,
        options: AppLanguage.allCases.map { ($0, $0.displayName) }
      )
      .onChange(of: language) { _, newValue in
        LocalizationManager.shared.language = newValue
      }
    }
  }
}

// MARK: - Panel boyutu

private struct PanelSizeSettingsSection: View {
  @AppStorage(PanelSettings.iconScaleKey) private var iconScale = PanelSettings.defaultIconScale
  @AppStorage(PanelSettings.panelWidthKey) private var panelWidth = PanelSettings.defaultPanelWidth
  @AppStorage(PanelSettings.panelHeightKey) private var panelHeight = PanelSettings
    .defaultPanelHeight
  @AppStorage(PanelSettings.railWidthKey) private var railWidth = PanelSettings.defaultRailWidth
  @AppStorage(PanelSettings.cornerRadiusKey) private var cornerRadius = PanelSettings
    .defaultCornerRadius
  @AppStorage(PanelSettings.selectedIconPaddingKey) private var selectedIconPadding = PanelSettings
    .defaultSelectedIconPadding

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: L10n.previewGroup, subtitle: L10n.previewHint) {
        RailPreview()
          .padding(.vertical, 8)
      }

      SettingsCard(
        title: L10n.railGroup,
        trailing: AnyView(ResetButton { PanelSettings.resetSizeDefaults() })
      ) {
        ValueSlider(
          label: L10n.railWidthLabel,
          value: $railWidth,
          range: PanelSettings.railWidthRange,
          format: { "\(Int($0.rounded())) pt" }
        )
        SettingsRowDivider()
        ValueSlider(
          label: L10n.iconSizeLabel,
          value: $iconScale,
          range: PanelSettings.iconScaleRange,
          format: { "%\(Int(($0 * 100).rounded()))" },
          step: 0.05
        )
        SettingsRowDivider()
        ValueSlider(
          label: L10n.cornerRadiusLabel,
          value: $cornerRadius,
          range: PanelSettings.cornerRadiusRange,
          format: { "\(Int($0.rounded())) pt" }
        )
        SettingsRowDivider()
        ValueSlider(
          label: L10n.selectedIconPaddingLabel,
          value: $selectedIconPadding,
          range: PanelSettings.selectedIconPaddingRange,
          format: { "\(Int($0.rounded())) pt" }
        )
      }

      SettingsCard(title: L10n.expandedPanelGroup) {
        ValueSlider(
          label: L10n.panelWidthLabel,
          value: $panelWidth,
          range: PanelSettings.panelWidthRange,
          format: { "\(Int($0.rounded())) pt" }
        )
        SettingsRowDivider()
        ValueSlider(
          label: L10n.panelHeightLabel,
          value: $panelHeight,
          range: PanelSettings.panelHeightRange,
          format: { "\(Int($0.rounded())) pt" }
        )
      }
    }
  }
}

// MARK: - Ray ikonları

private struct RailIconsSettingsSection: View {
  @AppStorage(PanelSettings.showTasksIconKey) private var showTasks = true
  @AppStorage(PanelSettings.showAddIconKey) private var showAdd = true
  @AppStorage(PanelSettings.showCompletedIconKey) private var showCompleted = true
  @AppStorage(PanelSettings.showFoldersIconKey) private var showFolders = true
  @AppStorage(PanelSettings.showMemoryIconKey) private var showMemory = true
  @AppStorage(PanelSettings.showNetworkIconKey) private var showNetwork = false
  @AppStorage(PanelSettings.showBatteryIconKey) private var showBattery = false
  @AppStorage(PanelSettings.showDiskIconKey) private var showDisk = false
  @AppStorage(PanelSettings.showProcessorIconKey) private var showProcessor = false
  @AppStorage(PanelSettings.showPinIconKey) private var showPin = true
  @AppStorage(PanelSettings.showWindowSwitcherIconKey) private var showWindowSwitcher = true
  @AppStorage(PanelSettings.showSettingsIconKey) private var showSettings = true
  @AppStorage(PanelSettings.selectedIconCornerRadiusKey) private var selectedCorner = PanelSettings
    .defaultSelectedIconCornerRadius

  private var visibleCount: Int {
    [
      showTasks, showAdd, showCompleted, showFolders, showMemory,
      showNetwork, showBattery, showDisk, showProcessor,
      showPin, showWindowSwitcher, showSettings,
    ]
    .filter { $0 }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: L10n.previewGroup, subtitle: L10n.previewHint) {
        RailPreview()
          .padding(.vertical, 8)
      }

      SettingsCard(
        title: L10n.visibleIconsGroup,
        subtitle: L10n.iconCountSummary(visibleCount, PanelSettings.totalIconCount),
        trailing: AnyView(ResetButton { PanelSettings.resetIconDefaults() })
      ) {
        IconToggleRow(systemName: "checklist", label: L10n.showTasksIconLabel, isOn: $showTasks)
        SettingsRowDivider()
        IconToggleRow(systemName: "plus", label: L10n.showAddIconLabel, isOn: $showAdd)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "checkmark.circle", label: L10n.showCompletedIconLabel, isOn: $showCompleted)
        SettingsRowDivider()
        IconToggleRow(systemName: "folder", label: L10n.showFoldersIconLabel, isOn: $showFolders)
        SettingsRowDivider()
        IconToggleRow(systemName: "memorychip", label: L10n.showMemoryIconLabel, isOn: $showMemory)
        SettingsRowDivider()
        IconToggleRow(systemName: "globe", label: L10n.showNetworkIconLabel, isOn: $showNetwork)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "battery.100percent", label: L10n.showBatteryIconLabel, isOn: $showBattery)
        SettingsRowDivider()
        IconToggleRow(systemName: "internaldrive", label: L10n.showDiskIconLabel, isOn: $showDisk)
        SettingsRowDivider()
        IconToggleRow(systemName: "cpu", label: L10n.showProcessorIconLabel, isOn: $showProcessor)
        SettingsRowDivider()
        IconToggleRow(systemName: "pin", label: L10n.showPinIconLabel, isOn: $showPin)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "rectangle.on.rectangle", label: L10n.showWindowSwitcherIconLabel,
          isOn: $showWindowSwitcher)
        SettingsRowDivider()
        IconToggleRow(systemName: "gear", label: L10n.showSettingsIconLabel, isOn: $showSettings)
      }

      SettingsCard(title: L10n.iconStyleGroup) {
        ValueSlider(
          label: L10n.selectedIconCornerRadiusLabel,
          value: $selectedCorner,
          range: PanelSettings.selectedIconCornerRadiusRange,
          format: { "\(Int($0.rounded())) pt" }
        )
      }
    }
  }
}

// MARK: - Ağ

private struct NetworkSettingsSection: View {
  @State private var isConfirmingReset = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(
        title: L10n.s("Kullanım Geçmişi", "Usage History", "История использования")
      ) {
        VStack(alignment: .leading, spacing: 10) {
          note(
            symbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            text: L10n.s(
              "Günlük toplamlar yalnızca GlassDo çalışırken birikir; sistem geriye dönük bir sayaç tutmuyor.",
              "Daily totals only accumulate while GlassDo runs; the system keeps no retroactive counter.",
              "Дневные итоги накапливаются только пока работает GlassDo; система не ведёт ретроактивный счётчик."
            )
          )
          note(
            symbolName: "lock.shield",
            text: L10n.s(
              "Yalnızca fiziksel Wi-Fi/Ethernet arayüzleri sayılır. VPN tünelleri ayrıca eklenmez — aynı baytlar zaten fiziksel arayüzden geçer.",
              "Only physical Wi-Fi/Ethernet interfaces are counted. VPN tunnels are not added separately — the same bytes already pass through the physical interface.",
              "Учитываются только физические интерфейсы Wi-Fi/Ethernet. VPN-туннели не добавляются отдельно — те же байты уже проходят через физический интерфейс."
            )
          )
        }
        .padding(.vertical, 2)
      }

      SettingsCard(
        title: L10n.s("Sıfırla", "Reset", "Сброс")
      ) {
        HStack(alignment: .top, spacing: 12) {
          Text(L10n.s(
            "Kaydedilmiş bütün günlük ağ toplamlarını siler ve sayımı sıfırdan başlatır. Görevler, klasörler ve diğer ayarlar etkilenmez.",
            "Deletes every stored daily network total and restarts counting from zero. Tasks, folders and other settings are not affected.",
            "Удаляет все сохранённые дневные сетевые итоги и начинает подсчёт с нуля. Задачи, папки и другие настройки не затрагиваются."
          ))
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 8)

          Button(role: .destructive) {
            isConfirmingReset = true
          } label: {
            Text(L10n.s("Ağ Geçmişini Sıfırla…", "Reset Network History…", "Сбросить историю сети…"))
              .font(.system(size: 12, weight: .medium))
          }
          .fixedSize()
        }
        .padding(.vertical, 4)
      }
    }
    .confirmationDialog(
      L10n.s(
        "Ağ geçmişi sıfırlansın mı?",
        "Reset network history?",
        "Сбросить историю сети?"
      ),
      isPresented: $isConfirmingReset,
      titleVisibility: .visible
    ) {
      Button(L10n.s("Sıfırla", "Reset", "Сбросить"), role: .destructive) {
        // Sıfırlama hemen yeni çizgiyi kuruyor ve widget'ı tazeliyor;
        // uygulamayı yeniden başlatmak gerekmiyor.
        NetworkHistoryStore.shared.resetHistory()
      }
      Button(L10n.s("İptal", "Cancel", "Отмена"), role: .cancel) {}
    } message: {
      Text(L10n.s(
        "Bugün, dün ve son 30 günün bütün ağ toplamları silinir. Bu işlem geri alınamaz.",
        "Today, yesterday and all last-30-day network totals are deleted. This cannot be undone.",
        "Итоги за сегодня, вчера и все последние 30 дней будут удалены. Это действие необратимо."
      ))
    }
  }

  private func note(symbolName: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: symbolName)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 16)
      Text(text)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Pencere değiştirici

private struct WindowSwitcherSettingsSection: View {
  let controller: WindowSwitcherController

  /// İzinler sistem ayarlarından değiştiği anda otomatik güncellenmez —
  /// görünüme her gelindiğinde ve "Yenile"ye basıldığında tazelenir.
  @State private var accessibilityGranted = false
  @State private var screenRecordingGranted = false

  @State private var modifierRaw = WindowSwitcherSettings.modifier.rawValue
  @State private var triggerKeyCode = Int(WindowSwitcherSettings.triggerKeyCode)
  @State private var triggerKeyLabel = WindowSwitcherSettings.triggerKeyLabel

  @AppStorage(WindowSwitcherSettings.apparitionDelayKey) private var apparitionDelayMs =
    WindowSwitcherSettings.defaultApparitionDelayMs
  @AppStorage(WindowSwitcherSettings.fadeOutEnabledKey) private var fadeOutEnabled =
    WindowSwitcherSettings.defaultFadeOutEnabled
  @AppStorage(WindowSwitcherSettings.fadeInPreviewEnabledKey) private var fadeInPreviewEnabled =
    WindowSwitcherSettings.defaultFadeInPreviewEnabled

  private var currentModifier: SwitcherModifier {
    SwitcherModifier(rawValue: modifierRaw) ?? .option
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(
        title: L10n.s("Kısayol", "Shortcut", "Комбинация клавиш"),
        subtitle: L10n.s(
          "\(currentModifier.symbol) basılı tut, \(triggerKeyLabel)'a bas — bırakınca seçili pencere öne gelir",
          "Hold \(currentModifier.symbol), press \(triggerKeyLabel) — release to bring the selected window forward",
          "Удерживайте \(currentModifier.symbol), нажмите \(triggerKeyLabel) — отпустите, чтобы выбранное окно вышло на передний план"
        ),
        trailing: AnyView(ResetButton { resetShortcutDefaults() })
      ) {
        SettingsSegmentedRow(
          label: L10n.s("Basılı tutulan tuş", "Hold key", "Удерживаемая клавиша"),
          selection: $modifierRaw,
          options: SwitcherModifier.allCases.map { ($0.rawValue, "\($0.symbol) \($0.displayName)") }
        )
        .onChange(of: modifierRaw) { _, newValue in
          UserDefaults.standard.set(newValue, forKey: WindowSwitcherSettings.modifierKey)
        }

        SettingsRowDivider()

        HStack {
          Text(L10n.s("Tekrarlanan tuş", "Repeated key", "Повторяемая клавиша"))
            .font(.system(size: 13))
          Spacer(minLength: 12)
          ShortcutKeyRecorder(keyCode: $triggerKeyCode, keyLabel: $triggerKeyLabel)
            .onChange(of: triggerKeyCode) { _, newValue in
              UserDefaults.standard.set(newValue, forKey: WindowSwitcherSettings.triggerKeyCodeKey)
            }
            .onChange(of: triggerKeyLabel) { _, newValue in
              UserDefaults.standard.set(newValue, forKey: WindowSwitcherSettings.triggerKeyLabelKey)
            }
        }
        .padding(.vertical, 9)

        SettingsRowDivider()

        HStack(spacing: 10) {
          Button {
            controller.toggleSummon()
          } label: {
            Text(
              controller.isVisible
                ? L10n.s("Kapat", "Close", "Закрыть")
                : L10n.s("Test Et", "Test It", "Протестировать")
            )
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
              Capsule().fill(
                controller.isVisible ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.85))
            )
            .foregroundStyle(.white)
          }
          .buttonStyle(.plain)

          Text(
            controller.isVisible
              ? L10n.s(
                "Ekran görüntüsü almak için açık kalır — bitirince Kapat'a bas",
                "Stays open so you can take a screenshot — press Close when done",
                "Остаётся открытым, чтобы вы могли сделать снимок экрана — нажмите «Закрыть», когда закончите"
              )
              : L10n.s(
                "İzinler verildiyse bindirimi kapatana kadar açık tutar",
                "Keeps the overlay open until you close it, if permissions are granted",
                "Оставляет наложение открытым, пока вы его не закроете, если разрешения предоставлены"
              )
          )
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          // Uzun metin genişlik talep etmek yerine satır atlasın.
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
      }

      SettingsCard(
        title: L10n.s("Animasyonlar", "Animations", "Анимации"),
        trailing: AnyView(ResetButton { resetAnimationDefaults() })
      ) {
        ValueSlider(
          label: L10n.s(
            "Beliriş gecikmesi", "Apparition delay of Switcher", "Задержка появления переключателя"),
          value: $apparitionDelayMs,
          range: WindowSwitcherSettings.apparitionDelayRange,
          format: { "\(Int($0.rounded())) ms" },
          step: 10
        )

        SettingsRowDivider()

        animationToggleRow(
          label: L10n.s(
            "Kaybolma animasyonu", "Fade out animation of Switcher",
            "Анимация исчезновения переключателя"),
          isOn: $fadeOutEnabled
        )

        SettingsRowDivider()

        animationToggleRow(
          label: L10n.s(
            "Önizlemenin belirme animasyonu", "Fade in animation of Preview",
            "Анимация появления предпросмотра"),
          isOn: $fadeInPreviewEnabled
        )
      }

      SettingsCard(
        title: L10n.s("İzinler", "Permissions", "Разрешения"),
        trailing: AnyView(
          Button {
            refreshPermissions()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        )
      ) {
        permissionRow(
          granted: accessibilityGranted,
          title: L10n.s("Erişilebilirlik", "Accessibility", "Специальные возможности"),
          subtitle: L10n.s(
            "Global ⌥+Tab yakalamak için gerekli",
            "Required to capture ⌥+Tab globally",
            "Требуется для глобального перехвата ⌥+Tab"
          )
        )
        SettingsRowDivider()
        permissionRow(
          granted: screenRecordingGranted,
          title: L10n.s("Ekran Kaydı", "Screen Recording", "Запись экрана"),
          subtitle: L10n.s(
            "Pencere küçük resimleri için gerekli",
            "Required for window thumbnails",
            "Требуется для миниатюр окон"
          )
        )

        HStack(spacing: 14) {
          Button {
            controller.requestPermissionsAndStart(userInitiated: true)
            refreshPermissions()
          } label: {
            Text(L10n.s("İzin İste", "Request Access", "Запросить доступ"))
              .font(.system(size: 12, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)

          Button {
            controller.openAccessibilitySettings()
          } label: {
            Text(
              L10n.s(
                "Sistem Ayarları'nı Aç",
                "Open System Settings",
                "Открыть системные настройки"
              )
            )
            .font(.system(size: 12, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)

          Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)

        // İzin listede açık görünürken yakalayıcı kurulamıyorsa
        // sorun izinde değil, kaydın eskimesinde: imzasız bir
        // derlemede her yeni ikili TCC kaydını geçersiz kılıyor.
        // Kullanıcıya "yeniden başlat" demek burada yanlış olurdu,
        // çünkü yeniden başlatmak bunu çözmüyor.
        if controller.isAuthorizationStale {
          permissionNote(
            L10n.s(
              "İzin verilmiş görünüyor ama macOS bu derlemeyi tanımıyor. Sistem Ayarları'ndaki listeden GlassDo'yu − ile kaldırıp + ile yeniden ekle.",
              "The permission looks granted but macOS doesn’t recognize this build. In System Settings, remove GlassDo from the list with − and add it again with +.",
              "Разрешение выглядит выданным, но macOS не распознаёт эту сборку. В системных настройках удалите GlassDo из списка кнопкой − и добавьте заново кнопкой +."
            ),
            isWarning: true
          )
        } else if accessibilityGranted, !screenRecordingGranted {
          permissionNote(
            L10n.s(
              "Pencere değiştirme çalışıyor. Ekran Kaydı olmadan kartlarda küçük resim yerine uygulama simgesi görünür.",
              "Window switching works. Without Screen Recording the cards show app icons instead of thumbnails.",
              "Переключение окон работает. Без записи экрана на карточках вместо миниатюр показаны значки приложений."
            ),
            isWarning: false
          )
        }
      }
    }
    .onAppear(perform: refreshPermissions)
  }

  private func refreshPermissions() {
    accessibilityGranted = controller.hasAccessibilityPermission
    screenRecordingGranted = controller.hasScreenRecordingPermission
    // Durum tazelenirken yakalayıcıyı da kurmayı dene: izin az önce
    // verildiyse kullanıcı hiçbir şey yapmadan çalışmaya başlasın.
    controller.retryEventTapIfNeeded()
  }

  private func permissionNote(_ text: String, isWarning: Bool) -> some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle")
        .font(.system(size: 10))
        .foregroundStyle(isWarning ? Color.orange : Color.secondary)

      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.bottom, 4)
  }

  private func resetShortcutDefaults() {
    WindowSwitcherSettings.resetDefaults()
    modifierRaw = WindowSwitcherSettings.defaultModifier.rawValue
    triggerKeyCode = WindowSwitcherSettings.defaultTriggerKeyCode
    triggerKeyLabel = WindowSwitcherSettings.defaultTriggerKeyLabel
    apparitionDelayMs = WindowSwitcherSettings.defaultApparitionDelayMs
    fadeOutEnabled = WindowSwitcherSettings.defaultFadeOutEnabled
    fadeInPreviewEnabled = WindowSwitcherSettings.defaultFadeInPreviewEnabled
  }

  private func resetAnimationDefaults() {
    apparitionDelayMs = WindowSwitcherSettings.defaultApparitionDelayMs
    fadeOutEnabled = WindowSwitcherSettings.defaultFadeOutEnabled
    fadeInPreviewEnabled = WindowSwitcherSettings.defaultFadeInPreviewEnabled
  }

  private func animationToggleRow(label: String, isOn: Binding<Bool>) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 13))
      Spacer(minLength: 12)
      Toggle("", isOn: isOn)
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
    }
    .padding(.vertical, 9)
  }

  private func permissionRow(granted: Bool, title: String, subtitle: String) -> some View {
    HStack(spacing: 11) {
      Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
        .font(.system(size: 15))
        .foregroundStyle(granted ? Color(red: 0.30, green: 0.78, blue: 0.45) : Color.secondary)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 13))
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 8)
    }
    .padding(.vertical, 7)
  }
}

// MARK: - Hakkında

private struct AboutSettingsSection: View {
  var body: some View {
    SettingsCard {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Color.black.opacity(0.6))
          .frame(width: 48, height: 48)
          .overlay {
            Image(systemName: "checklist")
              .font(.system(size: 22))
              .foregroundStyle(.white)
          }
        VStack(alignment: .leading, spacing: 3) {
          Text("GlassDo")
            .font(.system(size: 15, weight: .semibold))
          Text("\(L10n.versionLabel) \(GlassDoKit.version)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 8)
    }
  }
}
