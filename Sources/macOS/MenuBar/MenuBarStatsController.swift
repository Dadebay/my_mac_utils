import AppKit
import SwiftUI
import GlassDoKit

/// Menü çubuğundaki ölçerleri yönetir: hangileri açıksa o kadar
/// `NSStatusItem` yaratır, ölçüm değiştikçe içeriklerini tazeler,
/// tıklanınca ilgili kartı açar.
///
/// Ayrı bir `MenuBarExtra` yerine `NSStatusItem` kullanılıyor: SwiftUI'nin
/// `MenuBarExtra`'sı sahne (Scene) düzeyinde tanımlanıyor ve sayısı
/// derleme zamanında sabit — buradaysa kullanıcı çalışırken ölçer ekleyip
/// çıkarabiliyor.
@MainActor
final class MenuBarStatsController {
    static let shared = MenuBarStatsController()

    private var hosts: [MenuBarItemKind: StatusItemHost] = [:]
    private let stats = SystemStatsController.shared
    private var popover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?

    /// Ayarlar penceresini açan kanca — `EdgePanelController` ile aynı
    /// desen: SwiftUI'nin `openSettings` ortam eylemi yalnızca bir
    /// görünümün içinden çağrılabiliyor, menü çubuğu ise görünüm değil.
    var openSettings: (() -> Void)?

    private var isRunning = false
    /// Ölçüm döngüsü yalnızca en az bir ölçer görünürken çalışsın:
    /// menü çubuğu boşken iki saniyede bir sistemi yoklamanın karşılığı yok.
    private var isSamplingStarted = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        syncItems()
        observeStats()

        // Ayarlar penceresi seçimi değiştirdiğinde ölçerler anında
        // eklensin/çıksın — kaydet düğmesi yok.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.syncItems()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil

        for host in hosts.values {
            NSStatusBar.system.removeStatusItem(host.statusItem)
        }
        hosts.removeAll()

        if isSamplingStarted {
            isSamplingStarted = false
            stats.stop()
        }
    }

    // MARK: - Ölçer listesi

    /// Ayarlardaki seçimle menü çubuğunu eşitler. Zaten duran ölçerler
    /// yeniden yaratılmıyor — yaratılsalardı menü çubuğunda yerleri
    /// değişir, kullanıcının elle verdiği sıra bozulurdu.
    private func syncItems() {
        let desired = MenuBarSettings.enabledItems
        guard isRunning else { return }

        let desiredSet = Set(desired)
        for (kind, host) in hosts where !desiredSet.contains(kind) {
            NSStatusBar.system.removeStatusItem(host.statusItem)
            hosts.removeValue(forKey: kind)
        }

        for kind in desired where hosts[kind] == nil {
            hosts[kind] = StatusItemHost(
                kind: kind,
                onClick: { [weak self] kind, button in
                    self?.handleClick(kind: kind, button: button)
                },
                onOpenSettings: { [weak self] in
                    self?.requestSettings()
                }
            )
        }

        updateSampling(hasItems: !desired.isEmpty)
        refreshItems()
    }

    private func updateSampling(hasItems: Bool) {
        if hasItems, !isSamplingStarted {
            isSamplingStarted = true
            stats.start()
        } else if !hasItems, isSamplingStarted {
            isSamplingStarted = false
            stats.stop()
        }
    }

    // MARK: - Tazeleme

    /// `@Observable` ölçüm nesnesini izler. Kendi zamanlayıcısını kurmak
    /// yerine değişimi bekliyor: ölçüm iki saniyede bir yenilendiğinde
    /// menü çubuğu da tam o anda yenilensin, arada bir tur gecikmesin.
    private func observeStats() {
        withObservationTracking {
            _ = stats.cpu
            _ = stats.memory
            _ = stats.disk
            _ = stats.battery
            _ = stats.network
            _ = stats.device
        } onChange: { [weak self] in
            _Concurrency.Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.refreshItems()
                self.observeStats()
            }
        }
    }

    private func refreshItems() {
        guard !hosts.isEmpty else { return }
        let snapshot = currentSnapshot()
        for host in hosts.values {
            host.update(snapshot: snapshot)
        }
    }

    private func currentSnapshot() -> SystemSnapshot {
        SystemSnapshot(
            date: Date(),
            cpu: stats.cpu,
            memory: stats.memory,
            disk: stats.disk,
            battery: stats.battery,
            network: stats.network,
            device: stats.device,
            language: L10n.language.rawValue
        )
    }

    // MARK: - Tıklama

    private func handleClick(kind: MenuBarItemKind, button: NSStatusBarButton) {
        // Sağ tık ve Control+tık menü açar; sol tık kartı.
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            showMenu(for: kind, button: button)
        } else {
            togglePopover(for: kind, button: button)
        }
    }

    /// Kanca kurulmadıysa (ana pencere hiç açılmadıysa) SwiftUI'nin
    /// kendi ayar eylemi denenir.
    private func requestSettings() {
        if let openSettings {
            openSettings()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func togglePopover(for kind: MenuBarItemKind, button: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            self.popover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient

        // Sabit bir `contentSize` (eskiden 340×380) her kategori için aynı
        // kutuyu dayatıyordu — Memory gibi zengin kartların gerçek boyu bu
        // kutudan taşınca SwiftUI içeriği popover'ın kendi penceresinin
        // dışına render ediyor, o sınırın ötesi de arkadaki masaüstünü
        // gösteren tam saydam bir alan olarak kalıyordu. `.preferredContentSize`
        // popover'ı `NSHostingController`'ın kendi hesapladığı gerçek
        // boyuta göre otomatik ayarlıyor — içerik `MenuBarPopoverView`
        // içindeki `.frame(width:).frame(maxHeight:)` ile zaten sınırlı,
        // burada onu tekrar sabitlemeye gerek yok.
        let hostingController = NSHostingController(
            rootView: MenuBarPopoverView(category: kind.category)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    private func showMenu(for kind: MenuBarItemKind, button: NSStatusBarButton) {
        hosts[kind]?.showMenu()
    }
}

// MARK: - Tek bir menü çubuğu ögesi

/// Bir `NSStatusItem` ile onun içindeki SwiftUI çizimini bir arada tutar.
///
/// `NSObject` çünkü düğmenin hedefi (`target`/`action`) olması gerekiyor.
@MainActor
private final class StatusItemHost: NSObject {
    let kind: MenuBarItemKind
    let statusItem: NSStatusItem

    private let hosting: MenuBarHostingView
    private let onClick: (MenuBarItemKind, NSStatusBarButton) -> Void
    private let onOpenSettings: () -> Void

    init(
        kind: MenuBarItemKind,
        onClick: @escaping (MenuBarItemKind, NSStatusBarButton) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.kind = kind
        self.onClick = onClick
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Kalıcı bir ad verilmezse sistem bu ögeyi "sıradan" sayıyor:
        // menü çubuğu sıkışınca (çentikli ekran, çok sayıda menü ekstra'sı,
        // harici ekran bağlantısı değişince genişlik daralınca) konumunu
        // hatırlamadan taşma okunun arkasına gizleyebiliyor — kullanıcının
        // "bazen kayboluyor" dediği şey bu. `kind.rawValue` kalıcı olduğu
        // için (bkz. `MenuBarItemKind`) ad da öge yeniden yaratılsa bile
        // aynı kalıyor.
        statusItem.autosaveName = "menubar.\(kind.rawValue)"
        hosting = MenuBarHostingView(
            rootView: AnyView(MenuBarItemView(kind: kind, snapshot: SystemSnapshot()))
        )

        super.init()

        guard let button = statusItem.button else { return }

        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func update(snapshot: SystemSnapshot) {
        hosting.rootView = AnyView(MenuBarItemView(kind: kind, snapshot: snapshot))

        // Genişlik ölçerden ölçere değişiyor (grafik, çubuk, iki satır
        // sayı aynı yeri kaplamıyor), o yüzden ölçülüyor. Aynı ölçerin
        // genişliği ise değer değiştikçe oynamıyor: `MenuBarItemView`
        // her sayı alanına, alabileceği en geniş metne göre yer ayırıyor.
        // Tam puana yuvarlanıyor ki yarım puanlık ölçüm farkları da
        // menü çubuğunu oynatmasın.
        let width = hosting.fittingSize.width.rounded(.up)
        if width > 0, abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        onClick(kind, button)
    }

    /// Sağ tık menüsü. Hedefi bu nesne: menü maddelerinin eylemleri
    /// `@objc` olmak zorunda ve denetleyicinin kendisi `NSObject` değil.
    func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()
        menu.addItem(item(
            title: L10n.s("Bu ölçeri gizle", "Hide this reading", "Скрыть этот показатель"),
            action: #selector(hideItem)
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: L10n.settingsTitle + "…",
            action: #selector(openSettings)
        ))
        menu.addItem(item(title: L10n.quit, action: #selector(quit)))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func hideItem() {
        MenuBarSettings.toggle(kind)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Menü çubuğu düğmesinin içine yerleşen SwiftUI görünümü.
///
/// `hitTest` nil döndürüyor: aksi hâlde tıklamalar SwiftUI katmanında
/// yutuluyor ve `NSStatusItem`'ın kendi düğmesine hiç ulaşmıyor.
private final class MenuBarHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) desteklenmiyor")
    }

    @MainActor
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }
}
