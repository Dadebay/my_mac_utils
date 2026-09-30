import AppKit
import GlassDoKit
import SwiftUI

// MARK: - Kategoriler

enum SettingsCategory: String, CaseIterable, Identifiable {
  case general, panelSize, railIcons, menuBar, widgets, network, alerts, windowSwitcher, about
  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: L10n.generalSection
    case .panelSize: L10n.panelSizeSection
    case .railIcons: L10n.railIconsSection
    case .menuBar: L10n.s("Menü Çubuğu", "Menu Bar", "Строка меню")
    case .widgets: L10n.s("Widget'lar", "Widgets", "Виджеты")
    case .network: L10n.s("Ağ", "Network", "Сеть")
    case .alerts: L10n.s("Uyarılar", "Alerts", "Оповещения")
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
    case .alerts:
      L10n.s("Isınma ve çöp kutusu", "Heat and Trash", "Нагрев и корзина")
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
    case .alerts: "bell.badge"
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
    case .alerts:
      [Color(red: 0.98, green: 0.72, blue: 0.24), Color(red: 0.86, green: 0.44, blue: 0.10)]
    case .windowSwitcher:
      [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 0.9, green: 0.44, blue: 0.12)]
    case .about:
      [Color(red: 0.30, green: 0.42, blue: 0.92), Color(red: 0.20, green: 0.28, blue: 0.78)]
    }
  }

  /// Ayarların hangi bölümünden çıkıldığı. Ayarlar çoğunlukla aynı ayarı
  /// bir daha kurcalamak için açılır; her açılışta "Genel"e dönmek
  /// kullanıcıyı bulduğu yerden geri atıyordu.
  ///
  /// Anahtar ayrı bir pencere döneminden kalma — o pencerenin
  /// `@AppStorage`'ı buraya taşındı, böylece sürüm atlayan kullanıcı son
  /// bölümünü kaybetmiyor. Ayarlar artık bir görünümün kendi durumu
  /// değil, pencere dışından da (dişli, menü çubuğu, ⌘,) sorulan bir
  /// bilgi olduğu için `UserDefaults`'tan doğrudan okunuyor.
  static let lastViewedKey = "settings.selectedCategory"

  static var lastViewed: SettingsCategory {
    get {
      let raw = UserDefaults.standard.string(forKey: lastViewedKey) ?? ""
      let stored = SettingsCategory(rawValue: raw) ?? .general
      // Kenar çubuğunda satırı olmayan bir bölüm hatırlanmış olabilir
      // (bkz. `sidebarCases`): o sayfaya dönmek, hiçbir satırın seçili
      // görünmediği bir pencere açardı.
      return sidebarCases.contains(stored) ? stored : .general
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: lastViewedKey) }
  }

  /// Kenar çubuğunda satırı olan bölümler.
  ///
  /// Widget'lar listede değil: sayfa masaüstü ve Bildirim Merkezi
  /// widget'larının önizleme galerisi ve widget'lar zaten kendi
  /// yerlerinden (Bildirim Merkezi, masaüstü) yönetiliyor — ayarlarda
  /// ikinci bir kapı olmasının karşılığı yoktu. Bölüm ve sayfası
  /// duruyor, yalnızca satırı listede değil; geri açmak için buraya
  /// eklemek yetiyor.
  static var sidebarCases: [SettingsCategory] {
    allCases.filter { $0 != .widgets }
  }
}

// MARK: - Genel

struct GeneralSettingsSection: View {
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

struct PanelSizeSettingsSection: View {
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
    // Önizleme solda, onu değiştiren kaydırıcılar sağda: geniş pencerede
    // kaydırıcıyı sürüklerken önizleme aynı ekranda, hemen yanında.
    SettingsColumns {
      SettingsCard(title: L10n.previewGroup, subtitle: L10n.previewHint) {
        RailPreview()
          .padding(.vertical, 8)
      }
    } trailing: {
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

struct RailIconsSettingsSection: View {
  @AppStorage(PanelSettings.showTasksIconKey) private var showTasks = true
  @AppStorage(PanelSettings.showAddIconKey) private var showAdd = true
  @AppStorage(PanelSettings.showCompletedIconKey) private var showCompleted = true
  @AppStorage(PanelSettings.showFoldersIconKey) private var showFolders = true
  @AppStorage(PanelSettings.showMemoryIconKey) private var showMemory = true
  @AppStorage(PanelSettings.showClipboardIconKey) private var showClipboard = true
  @AppStorage(PanelSettings.showNetworkIconKey) private var showNetwork = false
  @AppStorage(PanelSettings.showBatteryIconKey) private var showBattery = false
  @AppStorage(PanelSettings.showDiskIconKey) private var showDisk = false
  @AppStorage(PanelSettings.showProcessorIconKey) private var showProcessor = false
  @AppStorage(PanelSettings.showVolumeIconKey) private var showVolume = false
  @AppStorage(PanelSettings.showPinIconKey) private var showPin = true
  @AppStorage(PanelSettings.showWindowSwitcherIconKey) private var showWindowSwitcher = true
  @AppStorage(PanelSettings.showSettingsIconKey) private var showSettings = true
  @AppStorage(PanelSettings.selectedIconCornerRadiusKey) private var selectedCorner = PanelSettings
    .defaultSelectedIconCornerRadius

  /// Pano ve ses karıştırıcı rayda vardı ama burada satırları yoktu:
  /// ikisi ayarlardan hiç açılıp kapatılamıyordu ve üstteki "14'ten 11"
  /// sayacı onları saymadığı için yanlış sonuç veriyordu.
  private var visibleCount: Int {
    [
      showTasks, showAdd, showCompleted, showFolders,
      showMemory, showClipboard, showNetwork, showBattery, showDisk, showProcessor, showVolume,
      showPin, showWindowSwitcher, showSettings,
    ]
    .filter { $0 }.count
  }

  var body: some View {
    // Sütun boyları çok farklı (kısa bir önizleme, on dört satırlık bir
    // liste): hizalanırsa önizleme kartı yarısı boş bir kutuya dönüyor.
    SettingsColumns(alignsHeights: false) {
      // Köşe kaydırıcısı önizlemenin hemen altında. Eskiden sayfanın en
      // dibinde, on dört satırlık listenin altındaydı: kaydırıcıyı
      // sürüklerken etkilediği ikon ekranın dışında kalıyordu, yani
      // değişikliği ancak bırakıp yukarı kaydırınca görebiliyordun.
      // Denetim, değiştirdiği şeyin yanında durmalı.
      SettingsCard(title: L10n.previewGroup, subtitle: L10n.previewHint) {
        RailPreview()
          .padding(.vertical, 8)
        SettingsRowDivider()
        ValueSlider(
          label: L10n.selectedIconCornerRadiusLabel,
          value: $selectedCorner,
          range: PanelSettings.selectedIconCornerRadiusRange,
          format: { "\(Int($0.rounded())) pt" }
        )
      }
    } trailing: {
      // Liste rayın kendisini aynalıyor: aynı sıra, aynı üç bölüm.
      // Düz on dört satır, hangi ikonun rayda nerede durduğunu
      // söylemiyordu; "görevler — ölçerler — eylemler" ayrımı rayı
      // yukarıdan aşağıya okurken gözün zaten yaptığı ayrım.
      SettingsCard(
        title: L10n.visibleIconsGroup,
        subtitle: L10n.iconCountSummary(visibleCount, PanelSettings.totalIconCount),
        trailing: AnyView(ResetButton { PanelSettings.resetIconDefaults() })
      ) {
        groupLabel(L10n.s("Görevler", "Tasks", "Задачи"), isFirst: true)
        IconToggleRow(systemName: "checklist", label: L10n.showTasksIconLabel, isOn: $showTasks)
        SettingsRowDivider()
        IconToggleRow(systemName: "plus", label: L10n.showAddIconLabel, isOn: $showAdd)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "checkmark.circle", label: L10n.showCompletedIconLabel, isOn: $showCompleted)
        SettingsRowDivider()
        IconToggleRow(systemName: "folder", label: L10n.showFoldersIconLabel, isOn: $showFolders)

        groupLabel(L10n.s("Ölçerler ve araçlar", "Meters & tools", "Показатели и инструменты"))
        IconToggleRow(systemName: "memorychip", label: L10n.showMemoryIconLabel, isOn: $showMemory)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "doc.on.clipboard", label: L10n.showClipboardIconLabel, isOn: $showClipboard)
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
        IconToggleRow(
          systemName: "speaker.wave.2", label: L10n.showVolumeIconLabel, isOn: $showVolume)

        groupLabel(L10n.s("Eylemler", "Actions", "Действия"))
        IconToggleRow(systemName: "pin", label: L10n.showPinIconLabel, isOn: $showPin)
        SettingsRowDivider()
        IconToggleRow(
          systemName: "rectangle.on.rectangle", label: L10n.showWindowSwitcherIconLabel,
          isOn: $showWindowSwitcher)
        SettingsRowDivider()
        IconToggleRow(systemName: "gear", label: L10n.showSettingsIconLabel, isOn: $showSettings)
      }
    }
  }

  /// Kartın içindeki bölüm etiketi. Ayrı kartlar yerine tek kartın içinde:
  /// sayaç ve sıfırlama düğmesi on dört ikonun hepsi için geçerli, üç
  /// ayrı kartın başlıklarına bölünemezdi.
  private func groupLabel(_ title: String, isFirst: Bool = false) -> some View {
    Text(title)
      .font(.app(.caption, weight: .semibold))
      .foregroundStyle(.tertiary)
      .textCase(.uppercase)
      .kerning(0.4)
      .padding(.top, isFirst ? 6 : 16)
      .padding(.bottom, 2)
  }
}

// MARK: - Ağ

struct NetworkSettingsSection: View {
  @State private var isConfirmingReset = false
  @State private var agent = NetworkAgentController.shared

  /// Arka plan toplama gerçekten ayakta mı. Anahtarın açık görünmesi yetmez:
  /// macOS onayı beklenirken servis kayıtlı ama çalışmıyor olabiliyor.
  private var isCollectingInBackground: Bool {
    agent.isEnabled && agent.status == .enabled
  }

  var body: some View {
    content
      // Kullanıcı Sistem Ayarları'nda izni verip geri döndüğünde anahtarın
      // altındaki durum satırı eski hâlinde kalmasın.
      .task { agent.refreshStatus() }
      .onChange(of: agent.isEnabled) { _, _ in agent.refreshStatus() }
  }

  private var content: some View {
    SettingsColumns {
      SettingsCard(
        title: L10n.s("Kullanım Geçmişi", "Usage History", "История использования")
      ) {
        VStack(alignment: .leading, spacing: 10) {
          // Anahtar satırın sağ kenarında, uygulamadaki öteki bütün
          // satırlarda olduğu gibi. `Toggle`'ın kendi etiketiyle kurulunca
          // macOS anahtarı yazının hemen bitişiğine koyuyordu; geniş
          // kartta anahtar satırın ortasında asılı kalıyordu.
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text(L10n.s(
                "GlassDo kapalıyken de ölç",
                "Keep measuring while GlassDo is closed",
                "Измерять, даже когда GlassDo закрыт"
              ))
              .font(.app(.bodyLarge, weight: .medium))
              .fixedSize(horizontal: false, vertical: true)

              Text(agentStatusText)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(
              L10n.s(
                "GlassDo kapalıyken de ölç",
                "Keep measuring while GlassDo is closed",
                "Измерять, даже когда GlassDo закрыт"
              ),
              isOn: Binding(
                get: { agent.isEnabled },
                set: { agent.setEnabled($0) }
              )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
          }

          if agent.status == .requiresApproval {
            Button(L10n.s(
              "Sistem Ayarları'nda İzin Ver",
              "Approve in System Settings",
              "Разрешить в Системных настройках"
            )) {
              agent.openLoginItemsSettings()
            }
            .buttonStyle(.plain)
            .font(.app(.body, weight: .semibold))
            .foregroundStyle(Color.appAccent)
          }

          if let error = agent.lastError {
            Text(error)
              .font(.app(.caption))
              .foregroundStyle(SystemPalette.danger)
              .fixedSize(horizontal: false, vertical: true)
          }

          Divider().opacity(0.3)

          note(
            symbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            text: historyScopeText
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
    } trailing: {
      SettingsCard(
        title: L10n.s("Sıfırla", "Reset", "Сброс")
      ) {
        // Açıklama ile düğme yan yanaydı ve düğme `.fixedSize()` ile
        // sıkışmayı tamamen reddediyordu: pencere daraldıkça bütün
        // daralmayı paragraf yükleniyor, üç satırlık metin sekiz satıra
        // çıkıp sonunda kelime başına bir satıra iniyordu. Alt alta
        // durduklarında paragraf bütün genişliği kullanıyor, düğme de
        // tam adıyla duruyor.
        VStack(alignment: .leading, spacing: 10) {
          Text(L10n.s(
            "Kaydedilmiş bütün günlük ağ toplamlarını siler ve sayımı sıfırdan başlatır. Görevler, klasörler ve diğer ayarlar etkilenmez.",
            "Deletes every stored daily network total and restarts counting from zero. Tasks, folders and other settings are not affected.",
            "Удаляет все сохранённые дневные сетевые итоги и начинает подсчёт с нуля. Задачи, папки и другие настройки не затрагиваются."
          ))
          .font(.app(.body))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

          Button(role: .destructive) {
            isConfirmingReset = true
          } label: {
            Text(L10n.s("Ağ Geçmişini Sıfırla…", "Reset Network History…", "Сбросить историю сети…"))
              .font(.app(.bodyLarge, weight: .medium))
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
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


  /// Anahtarın altındaki satır: servisin gerçek durumu. "Açık" görünüp
  /// çalışmayan bir anahtar, eksik veriyi sonradan açıklanamaz hâle
  /// getiriyordu.
  private var agentStatusText: String {
    switch agent.status {
    case .enabled:
      L10n.s(
        "Arka plan ölçümü etkin.",
        "Background measurement is running.",
        "Фоновое измерение работает."
      )
    case .requiresApproval:
      L10n.s(
        "macOS onayı bekleniyor — izin verilene kadar ölçüm yapılmıyor.",
        "Waiting for macOS approval — nothing is measured until you allow it.",
        "Ожидается разрешение macOS — до него измерение не идёт."
      )
    case .notFound:
      L10n.s(
        "Arka plan bileşeni bulunamadı.",
        "The background helper is missing.",
        "Фоновый компонент не найден."
      )
    default:
      L10n.s(
        "Kapalı: geçmiş yalnızca GlassDo açıkken birikir.",
        "Off: history accumulates only while GlassDo is open.",
        "Выключено: история копится только при открытом GlassDo."
      )
    }
  }

  /// Panel ve ayarlar aynı gerçeği söylemeli.
  private var historyScopeText: String {
    isCollectingInBackground
      ? L10n.s(
          "Günlük toplamlar GlassDo kapalıyken de birikir. Ölçüm arka plan bileşeninin kurulduğu andan itibaren geçerlidir; ondan öncesi geri getirilemez.",
          "Daily totals keep accumulating while GlassDo is closed. Measurement starts when the background helper is installed; earlier traffic can't be recovered.",
          "Дневные итоги копятся и при закрытом GlassDo. Измерение начинается с установки фонового компонента; более ранний трафик вернуть нельзя."
        )
      : L10n.s(
          "Günlük toplamlar yalnızca GlassDo çalışırken birikir; sistem geriye dönük bir sayaç tutmuyor.",
          "Daily totals only accumulate while GlassDo runs; the system keeps no retroactive counter.",
          "Дневные итоги накапливаются только пока работает GlassDo; система не ведёт ретроактивный счётчик."
        )
  }

  private func note(symbolName: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: symbolName)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 16)
      Text(text)
        .font(.app(.body))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Pencere değiştirici

struct WindowSwitcherSettingsSection: View {
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
    // Kısayol solda (sayfanın asıl kararı), animasyon ve izinler sağda.
    SettingsColumns {
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
            .font(.app(.headline))
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
            .font(.app(.bodyLarge, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
              Capsule().fill(
                controller.isVisible ? Color.red.opacity(0.85) : Color.appAccent.opacity(0.85))
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
          .font(.app(.body))
          .foregroundStyle(.tertiary)
          // Uzun metin genişlik talep etmek yerine satır atlasın.
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
      }
    } trailing: {
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
          // Aynı paket kimliğinde ikinci bir kopya varken macOS isteği
          // çalışan ikiliye değil öteki kopyanın TCC kaydına bağlayabiliyor.
          // Bu düğmeyi o durumda göstermek, her basışta aynı sistem
          // penceresini açan ama hiçbir şeyi düzeltmeyen bir döngüydü.
          if otherInstalledCopies.isEmpty {
            Button {
              controller.requestPermissionsAndStart(userInitiated: true)
              refreshPermissions()
            } label: {
              Text(L10n.s("İzin İste", "Request Access", "Запросить доступ"))
                .font(.app(.bodyLarge, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appAccent)
          }

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
            .font(.app(.bodyLarge, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.appAccent)

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
        } else if !otherInstalledCopies.isEmpty {
          // Aynı paket kimliğinde ikinci bir kopya: izin sorunlarının en
          // kafa karıştırıcı kaynağı. macOS ikisini tek uygulama sayıyor;
          // izin birinin imzasına bağlanıyor, Ekran Kaydı sonrası
          // "Çık ve Yeniden Aç" ise uygulamayı kimlikten bulup çoğu zaman
          // ötekini açıyor. Kullanıcı izni verip yeniden açtığında
          // karşısına izinsiz kopya çıkıyor: "kapat aç yapınca izinler
          // gidiyor". İzinler yerindeyken de gösteriliyor, çünkü bir
          // sonraki yeniden açılış yine yanlış kopyayı başlatabilir.
          permissionNote(
            L10n.s(
              "Bu Mac'te aynı kimliği kullanan başka GlassDo kopyaları var: \(otherInstalledCopyPaths). macOS izinleri kopyalar arasında karıştırıyor ve \"Çık ve Yeniden Aç\" yanlış olanı başlatabiliyor. Yalnızca kullanacağın kopyayı bırak, diğerlerini Çöp Kutusu'na taşı, sonra izinleri yeniden ver.",
              "Other GlassDo copies with the same identity exist on this Mac: \(otherInstalledCopyPaths). macOS can mix permissions between them, and \"Quit & Reopen\" may launch the wrong one. Keep only the copy you use, move the others to the Trash, then grant the permissions again.",
              "На этом Mac есть другие копии GlassDo с тем же идентификатором: \(otherInstalledCopyPaths). macOS может путать разрешения между ними, а «Завершить и открыть снова» — запускать не ту копию. Оставьте только используемую копию, остальные переместите в Корзину и выдайте разрешения заново."
            ),
            isWarning: true
          )

          ForEach(otherInstalledCopies, id: \.path) { other in
            Button {
              NSWorkspace.shared.activateFileViewerSelecting([other])
            } label: {
              Text(
                L10n.s(
                  "Finder'da göster: \(other.lastPathComponent)",
                  "Show in Finder: \(other.lastPathComponent)",
                  "Показать в Finder: \(other.lastPathComponent)"
                )
              )
              .font(.app(.body, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appAccent)
            .padding(.bottom, 4)
          }
        } else if !accessibilityGranted {
          // En sık görülen durum: Sistem Ayarları'nda "GlassDo" açık
          // görünüyor ama izin başka bir kopyaya ait. Kurulum paketi
          // uygulamayı /Applications/GlassDo.app olarak kuruyor ve
          // "Developer ID Application" ile imzalıyor; `scripts/run.sh`'nin
          // derlediği GlassDo-macOS.app ise "Apple Development" ile imzalı.
          // Paket kimliği aynı olduğu için listede tek satır görünüyor,
          // macOS ise izni imzaya bağladığı için çalışan kopyayı
          // tanımıyor. Kart hangi kopyanın çalıştığını söylemezse
          // kullanıcı "açık ama çalışmıyor" ile baş başa kalıyordu.
          permissionNote(
            L10n.s(
              "Çalışan kopya: \(runningCopyName) (\(runningCopyFolder)). Listede GlassDo açık görünüyorsa izin büyük ihtimalle başka bir kopyaya ait (ör. /Applications'a kurulan GlassDo.app). Listeden − ile kaldır, sonra İzin İste'ye bas — ya da + ile bu kopyayı ekle.",
              "Running copy: \(runningCopyName) (\(runningCopyFolder)). If GlassDo already looks enabled in the list, the permission most likely belongs to another copy (e.g. the GlassDo.app installed in /Applications). Remove it with −, then press Request Access — or add this copy with +.",
              "Запущенная копия: \(runningCopyName) (\(runningCopyFolder)). Если GlassDo в списке уже включён, разрешение, скорее всего, принадлежит другой копии (например, GlassDo.app, установленной в /Applications). Удалите её кнопкой −, затем нажмите «Запросить доступ» — или добавьте эту копию кнопкой +."
            ),
            isWarning: true
          )

          Button {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
          } label: {
            Text(L10n.s("Bu kopyayı Finder'da göster", "Show this copy in Finder", "Показать эту копию в Finder"))
              .font(.app(.body, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.appAccent)
          .padding(.bottom, 4)
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
    // Kullanıcı izni Sistem Ayarları'nda verip geri döndüğünde yakalayıcı
    // kendiliğinden kuruluyordu ama kart ↻'ye basılana kadar ✗ göstermeye
    // devam ediyordu — "verdim ama hâlâ yok diyor".
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      refreshPermissions()
    }
  }

  /// Çalışan uygulamanın dosya adı — Sistem Ayarları listesinde görünen ad.
  private var runningCopyName: String { Bundle.main.bundleURL.lastPathComponent }

  /// Aynı paket kimliğine sahip, bu kopya dışındaki uygulamalar.
  ///
  /// Derleme ara çıktıları (Xcode'un DerivedData'sı, kurulum paketinin
  /// `build-release`'i) sayılmıyor: her derlemede yeniden oluşuyorlar,
  /// sayılsalar uyarı sürekli yanar, anlamını yitirirdi. `run.sh`'nin
  /// `build-debug`'ı ise sayılıyor — /Applications kopyası çalışırken
  /// karışıklığın öbür tarafı tam da o.
  private var otherInstalledCopies: [URL] {
    guard let identifier = Bundle.main.bundleIdentifier else { return [] }
    let running = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
      .map { $0.resolvingSymlinksInPath().standardizedFileURL }
      .filter { url in
        url != running
          && !url.path.contains("/DerivedData/")
          && !url.path.contains("/build-release/")
          // Çöp Kutusu'na atılan kopya diskte duruyor ve LaunchServices
          // onu hâlâ kayıtlı tutabiliyor; uyarının istediği şeyi yapan
          // kullanıcıya uyarı göstermeye devam etmek olmazdı.
          && !url.path.contains("/.Trash/")
          // Silinmiş ama kaydı henüz temizlenmemiş kopyalar.
          && FileManager.default.fileExists(atPath: url.path)
      }
  }

  /// Uyarıda tek kopya gösterilirse kullanıcı onu kaldırdıktan sonra
  /// LaunchServices'e kayıtlı üçüncü kopya aynı sorunu sürdürür. Bu yüzden
  /// bütün çakışan yollar tek seferde görünür.
  private var otherInstalledCopyPaths: String {
    otherInstalledCopies
      .map { ($0.path as NSString).abbreviatingWithTildeInPath }
      .joined(separator: ", ")
  }

  /// Çalışan kopyanın klasörü, ev dizini `~` ile kısaltılmış.
  private var runningCopyFolder: String {
    (Bundle.main.bundleURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
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
        .font(.app(.body))
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
        .font(.app(.headline))
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
          .font(.app(.headline))
        Text(subtitle)
          .font(.app(.body))
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 8)
    }
    .padding(.vertical, 7)
  }
}

// MARK: - Hakkında

struct AboutSettingsSection: View {
  /// Ayarlardaki "Hakkında" ile ayrı pencerede açılan "GlassDo Hakkında"
  /// aynı içerik: sürüm, bağlantılar ve kullanım istatistikleri. İki ayrı
  /// görünüm yazılsaydı biri güncellenip öteki geride kalırdı.
  var body: some View {
    AboutGlassDoView(isEmbedded: true)
  }
}
