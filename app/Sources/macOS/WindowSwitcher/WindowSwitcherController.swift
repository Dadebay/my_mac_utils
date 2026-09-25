import AppKit
@preconcurrency import ApplicationServices
import ScreenCaptureKit
import SwiftUI
import GlassDoKit

private extension CGRect {
    /// AX ve CGWindow koordinatları aynı sistemde olsa da yuvarlama farkı
    /// olabiliyor — birkaç noktalık toleransla eşleştiriyoruz.
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(minX - other.minX) < tolerance
            && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}

/// AltTab'daki "⌥ basılı tut + Tab'a bas" davranışının aynısı: bir
/// `CGEventTap` ile global olarak Option+Tab'ı yakalar, açık pencereleri
/// canlı küçük resimleriyle bir bindirimde gösterir, Tab'a her basışta
/// seçimi ilerletir, Option bırakılınca seçili pencereyi öne getirir.
///
/// İki sistem izni gerektirir — ikisi de yalnızca kullanıcının kendisinin
/// Sistem Ayarları'ndan onaylayabileceği şeyler:
/// - Erişilebilirlik (global tuş yakalama için)
/// - Ekran Kaydı (pencere küçük resimleri için)
@MainActor
@Observable
final class WindowSwitcherController {

    private(set) var isVisible = false
    /// ⌥ basılı tutulduğu andan bırakılana kadar süren "değiştirici
    /// oturumu". `isVisible`'dan ayrı olması şart: `isVisible` ancak
    /// bindirim ekrana çizildikten sonra `true` oluyor, tuş olayları ise
    /// o ana kadar da gelmeye devam ediyor. İkisi tek değişkende
    /// toplandığında, hazırlık sürerken basılan Tab'lar "oturum yok" sayılıp
    /// yeni bir gösterim başlatıyor, bu arada bırakılan ⌥ ise hiç
    /// yakalanmıyordu — bindirim kullanıcı tuşu bıraktıktan sonra açılıp
    /// ekranda asılı kalıyordu.
    private var isSessionActive = false
    /// Pencere listesi hazır olmadan basılan Tab'lar burada birikip liste
    /// gelince tek seferde uygulanıyor; aksi hâlde o basışlar kayboluyordu.
    private var pendingAdvance = 0
    private(set) var windows: [SwitcherWindowInfo] = []
    private(set) var selectedIndex = 0

    /// Pencere küçültülünce ekranda çizilmediği için yakalanamıyor — son
    /// başarılı görüntüsü burada saklanıp kartta o gösteriliyor.
    /// Anahtar için bkz. `cacheKey(pid:title:)`.
    private var thumbnailCache: [String: NSImage] = [:]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayPanel: SwitcherOverlayPanel?
    private var activationObserver: (any NSObjectProtocol)?
    private var otherAppActivationObserver: (any NSObjectProtocol)?
    /// Bindirim açıkken dışarıya yapılan tıklamaları dinler — bkz. `hide`.
    private var outsideClickMonitor: Any?

    /// Etkinleşme bildirimi statik bir kapanıştan geliyor; uygulamada tek
    /// bir değiştirici olduğu için en son kurulan örnek burada tutuluyor.
    private static weak var activeInstance: WindowSwitcherController?

    /// TCC isteğinin daha önce gösterildiğini yeniden başlatmalar arasında
    /// saklıyoruz. Uygulama imzası değişmiş bir geliştirme derlemesinde
    /// macOS izni yeni ikili için reddedebilir; bu durumda her ray tıklaması
    /// veya her uygulama açılışı yeni bir sistem penceresi oluşturmamalı.
    /// Kullanıcı Ayarlar'daki açık `İzin İste` düğmesiyle istediği zaman
    /// bilinçli olarak yeniden deneyebilir.
    private static let accessibilityPromptRequestedKey =
        "windowSwitcher.accessibilityPromptRequested"

    /// Sistem "izinli" diyor ama olay yakalayıcı kurulamıyor. Bu, imzası
    /// değişmiş bir derlemede TCC kaydının eskimesinin işareti: Sistem
    /// Ayarları'nda anahtar açık görünür, macOS ise yeni ikiliyi tanımaz.
    private(set) var isAuthorizationStale = false

    /// Ayarlar penceresini açan kanca — `EdgePanelController` ile aynı
    /// desen. İzin eksikken kullanıcıyı durumun açıklandığı sayfaya
    /// götürmek için kullanılıyor.
    var openSettings: (() -> Void)?

    /// Global ⌥+Tab yakalamak için gereken tek izin. Küçük resimler ayrı
    /// bir izne bağlı ve o olmadan da pencere değiştirme çalışmalı —
    /// ikisini tek kapıya bağlamak, Erişilebilirlik'i vermiş kullanıcıya
    /// "hâlâ izin yok" demek anlamına geliyordu.
    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Yalnızca pencere küçük resimleri için. Yoksa kartlar simgeyle çizilir.
    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Ayarlar'daki "Test Et" düğmesi ve ray ikonu için: gerçek ⌥+Tab
    /// kısayolunu beklemeden bindirimi gösterir/kapatır. Otomatik kapanmaz —
    /// ekran görüntüsü almak gibi elle inceleme için süre sınırı yok.
    func toggleSummon() {
        if isVisible {
            dismissPreview()
        } else {
            showPreview()
        }
    }

    func showPreview() {
        guard hasAccessibilityPermission else {
            // Ray ikonuna/menüye basmak bilinçli bir kullanıcı eylemi:
            // `userInitiated: true` olmadan, izin isteği ömür boyu bir kez
            // gösterildiği için (kalıcı `accessibilityPromptRequestedKey`)
            // buradan hiçbir şey olmuyordu — düğme sessizce ölüydü.
            requestPermissionsAndStart(userInitiated: true)

            // Sistem isteği ikinci kez göstermeyi reddedebilir (özellikle
            // listede duran ama imzası değişmiş bir derlemede). O durumda
            // da kullanıcı boşluğa basmış olmasın: durumu ve ne yapması
            // gerektiğini anlatan Ayarlar sayfasına götür.
            if !hasAccessibilityPermission {
                openSettings?()
            }
            return
        }
        // `presentSwitcher()` sonunda `isSessionActive` kontrol ediliyor —
        // hazırlık sürerken kullanıcı ⌥'i bırakırsa bindirim açılmasın diye
        // eklenmişti (bkz. o denetimin yanındaki yorum). Yalnızca klavye
        // yolu (`decide()`) bunu `true` yapıyordu; ray ikonu ve Ayarlar'daki
        // "Test Et" gibi doğrudan çağrılar hiç ayarlamıyordu, bu yüzden aynı
        // denetime takılıp bindirim sessizce hiç açılmıyordu.
        isSessionActive = true
        _Concurrency.Task { await presentSwitcher() }
    }

    func dismissPreview() {
        guard isVisible else { return }
        hide()
    }

    /// Uygulama açılışında bir kez çağrılır. İzin zaten verilmişse tap'i
    /// hemen kurar; verilmemişse sessizce hiçbir şey yapmaz — kullanıcı
    /// menüden "İzinleri kontrol et"i çalıştırana kadar özellik pasif kalır.
    func startIfAuthorized() {
        // Kullanıcı izni Sistem Ayarları'nda verip uygulamaya döndüğünde
        // yakalayıcı kendiliğinden kurulsun: "izin verdim ama hâlâ
        // çalışmıyor, yeniden başlatmam mı gerekiyor" durumunu ortadan
        // kaldırıyor.
        installActivationObserverIfNeeded()
        guard hasAccessibilityPermission, eventTap == nil else { return }
        startEventTap()
    }

    private func installActivationObserverIfNeeded() {
        Self.activeInstance = self
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                WindowSwitcherController.activeInstance?.retryEventTapIfNeeded()
            }
        }

        // Bindirim `.nonactivatingPanel`: kartların dışına, ekranda görünen
        // başka bir uygulamaya tıklanınca GlassDo hiç "etkinleşmiyor" — o
        // uygulama doğrudan öne geliyor ve bindirim fark etmeden ekranda
        // asılı kalıyor. ⌥+Tab'ta bırakma anı (`decide()`) veya bir karta
        // tıklama dışındaki tek kapanma yolu bu: başka bir uygulama
        // önplana her geçtiğinde bindirim kapanır.
        otherAppActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            MainActor.assumeIsolated {
                WindowSwitcherController.activeInstance?.dismissPreview()
            }
        }
    }

    /// Erişilebilirlik bölmesini doğrudan açar. Sistem izin penceresini bir
    /// kez gösterdikten sonra tekrar göstermiyor; kullanıcıyı doğru sayfaya
    /// götürmenin tek yolu bu.
    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Uygulama öne geldiğinde: izin varsa ve yakalayıcı yoksa kur.
    func retryEventTapIfNeeded() {
        guard eventTap == nil, hasAccessibilityPermission else { return }
        startEventTap()
    }

    /// İzin isteklerini tetikler (sistem onay pencerelerini açar) ve —
    /// zaten izin verilmişse — tap'i kurar. Erişilebilirlik izni genelde
    /// yeni verildiğinde uygulamanın yeniden başlatılmasını gerektirir.
    /// - Parameter userInitiated: Ayarlar'daki "İzinleri kontrol et"
    ///   düğmesi gibi kullanıcının bilerek tetiklediği çağrılarda sistem
    ///   penceresi her seferinde açılır. Kısayol ya da ray tıklaması gibi
    ///   dolaylı çağrılarda ise kurulum boyunca yalnızca bir kez.
    func requestPermissionsAndStart(userInitiated: Bool = false) {
        let defaults = UserDefaults.standard
        let hasRequestedBefore = defaults.bool(forKey: Self.accessibilityPromptRequestedKey)
        let mayPrompt = userInitiated || !hasRequestedBefore

        if !AXIsProcessTrusted(), mayPrompt {
            // API çağrısından önce yaz: macOS uygulamayı öne/arkaya alırken
            // süreç kapanırsa bile sonraki açılış tekrar istemesin.
            defaults.set(true, forKey: Self.accessibilityPromptRequestedKey)
            let options = [axTrustedPromptKey.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        // Ekran kaydı yalnızca kullanıcı bilerek istediğinde soruluyor:
        // pencere değiştirme onsuz da çalışıyor, küçük resimler yerine
        // uygulama simgeleri görünüyor.
        if userInitiated, !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        startIfAuthorized()
    }

    // MARK: - Global tuş yakalama

    private func startEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: windowSwitcherEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // İzin verilmiş görünüyorken kurulum başarısızsa TCC kaydı
            // eskimiştir. Sessizce vazgeçmek yerine işaretleniyor ki
            // Ayarlar kullanıcıya ne yapacağını söyleyebilsin.
            isAuthorizationStale = hasAccessibilityPermission
            return
        }

        isAuthorizationStale = false
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// C callback'ten çağrılır (bkz. `windowSwitcherEventTapCallback`).
    /// Tab'ı bindirim açıkken sistemden tamamen tüketir (nil döner) —
    /// yoksa önde duran uygulamaya da bir Tab tuşu sızardı.
    ///
    /// `CGEventTapCallBack` `@convention(c)` olduğu için asla `@MainActor`
    /// izole olamaz, ama tap'i ana çalışma döngüsüne (`CFRunLoopGetMain()`)
    /// eklediğimiz için pratikte her zaman ana iş parçacığında çalışır —
    /// `assumeIsolated` bunu derleyiciye güvenli biçimde doğrular. `CGEvent`
    /// `Sendable` olmadığı için actor sınırını geçmeden önce ondan yalnızca
    /// gönderime uygun ilkel değerler (kod, bayraklar) çıkarılıyor.
    nonisolated fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated { reenableTap() }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        let shouldConsume = MainActor.assumeIsolated {
            decide(type: type, flags: flags, keyCode: keyCode)
        }
        return shouldConsume ? nil : Unmanaged.passRetained(event)
    }

    private func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    /// `true` dönerse olay tamamen tüketilir (sistemin geri kalanına
    /// sızmaz); `false` dönerse olay normal şekilde iletilir.
    private func decide(type: CGEventType, flags: CGEventFlags, keyCode: Int64) -> Bool {
        let modifierFlag = WindowSwitcherSettings.modifier.eventFlag

        if type == .flagsChanged {
            let modifierDown = flags.contains(modifierFlag)
            guard !modifierDown else { return false }

            if isVisible {
                commitSelection()
            } else if isSessionActive {
                // Bindirim daha çizilmeden tuş bırakıldı. Oturum burada
                // kapatılıyor ki hazırlığı süren gösterim kendini iptal
                // etsin — yoksa bindirim iş bittiğinde açılıp ekranda
                // sahipsiz kalıyordu.
                endSession()
            }
            return false
        }

        guard type == .keyDown else { return false }

        if isVisible, keyCode == Self.escapeKeyCode {
            cancel()
            return true
        }

        guard flags.contains(modifierFlag), keyCode == WindowSwitcherSettings.triggerKeyCode else {
            return false
        }

        if isSessionActive {
            advanceSelection(backward: flags.contains(.maskShift))
        } else {
            isSessionActive = true
            pendingAdvance = 0
            show()
        }
        return true
    }

    private static let escapeKeyCode: Int64 = 53

    /// Pencere değiştiricide hiç görünmeyecek uygulamalar.
    private static let excludedBundleIdentifiers: Set<String> = ["com.apple.finder"]

    // MARK: - Gösterme / gezinme / etkinleştirme

    private var pendingShowTask: _Concurrency.Task<Void, Never>?

    private func show() {
        guard hasAccessibilityPermission else {
            requestPermissionsAndStart()
            return
        }
        scheduleShow()
    }

    /// Ayarlar'daki "Beliriş gecikmesi" kadar bekleyip bindirimi gösterir —
    /// çok hızlı basılıp bırakılan ⌥+Tab'lerde bindirim hiç göz kırpmadan
    /// sessizce atlanır. Gecikme dolmadan tuş bırakılırsa `decide()` bu
    /// görevi iptal eder.
    private func scheduleShow() {
        pendingShowTask?.cancel()
        let delayMs = WindowSwitcherSettings.apparitionDelayMs
        guard delayMs > 0 else {
            _Concurrency.Task { await presentSwitcher() }
            return
        }
        pendingShowTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .milliseconds(Int(delayMs)))
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.presentSwitcher()
        }
    }

    private func advanceSelection(backward: Bool) {
        guard !windows.isEmpty else {
            // Liste hazırlanıyor; basış kaybolmasın diye saklanıyor.
            pendingAdvance += backward ? -1 : 1
            return
        }
        let count = windows.count
        selectedIndex = ((selectedIndex + (backward ? -1 : 1)) % count + count) % count
        updateOverlay()
    }

    private func commitSelection() {
        guard isVisible else { return }
        guard windows.indices.contains(selectedIndex) else {
            hide()
            return
        }
        let target = windows[selectedIndex]
        // Bindirim önce kapanır: kendi panelimiz hâlâ `.screenSaver`
        // seviyesindeyken hedef pencereyi öne almak, sistemin pencere
        // sıralamasını bizim panelin arkasında bırakabiliyordu.
        hide()
        activate(target)
    }

    private func cancel() {
        hide()
    }

    /// Bir karta doğrudan mouse ile tıklanınca çağrılır — klavye döngüsünü
    /// beklemeden o pencereyi seçip öne getirir.
    func selectAndActivate(_ window: SwitcherWindowInfo) {
        hide()
        activate(window)
    }

    private func hide() {
        isVisible = false
        endSession()
        stopOutsideClickMonitor()
        dismissOverlay()
    }

    /// Oturumu kapatır: bekleyen gösterimi iptal eder ve birikmiş Tab
    /// sayacını sıfırlar. Hazırlığı süren `presentSwitcher` bunu görüp
    /// kendini iptal ediyor.
    private func endSession() {
        isSessionActive = false
        pendingAdvance = 0
        pendingShowTask?.cancel()
        pendingShowTask = nil
    }

    /// Seçilen pencereyi gerçekten öne getirir. Yalnızca `activate()` ya da
    /// yalnızca `kAXRaiseAction` yetmiyor: uygulamanın **ana** (main) ve
    /// odaklı penceresini de bu pencereye ayarlamak gerekiyor — aksi hâlde
    /// uygulama öne gelse bile başka bir penceresi ana pencere olarak
    /// kalıyor ve seçtiğimiz pencere arkada duruyordu.
    private func activate(_ window: SwitcherWindowInfo) {
        _Concurrency.Task { await performActivation(window) }
    }

    /// Uygulamayı gerçekten **en öne** getirir.
    ///
    /// `NSRunningApplication.activate()` bu iş için yetmiyor: macOS 14'ten
    /// beri geçerli olan "cooperative activation" kuralı, önplanda olmayan
    /// normal (`.regular`) bir uygulamanın başka bir uygulamayı
    /// etkinleştirme isteğini reddediyor ya da yalnızca kısmen uyguluyor.
    /// Ölçtüğümüzde hedef pencere yükseliyor ama o an önde duran uygulamanın
    /// **arkasında** kalıyordu — kullanıcının gördüğü hata buydu.
    /// `activate(options: .activateIgnoringOtherApps)` de çare değil:
    /// `ignoringOtherApps` macOS 14'te kullanımdan kaldırıldı ve derleyicinin
    /// kendi uyarısındaki ifadeyle artık "hiçbir etkisi yok".
    ///
    /// LaunchServices üzerinden açmak — Dock ikonuna tıklamanın yaptığı şey —
    /// bu kısıta tabi değil ve hedefi güvenilir biçimde en öne alıyor.
    /// Uygulama zaten çalışıyorsa yeni bir kopya başlatmıyor
    /// (`createsNewApplicationInstance` varsayılan olarak `false`), yalnızca
    /// öne getiriyor.
    private func bringToFront(_ runningApp: NSRunningApplication?) async {
        guard let runningApp else { return }
        guard let bundleURL = runningApp.bundleURL else {
            runningApp.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(
            at: bundleURL, configuration: configuration
        )
    }

    /// Seçilen pencereyi uygulamanın kendi pencereleri arasında öne alır ve
    /// odaklar. Uygulamanın önplana geçmesi ayrı iş — bkz. `bringToFront`.
    ///
    /// "Ana" ve "odaklı" işaretleri **pencerenin kendisine** yazılıyor;
    /// uygulama elemanındaki `kAXMainWindow` / `kAXFocusedWindow` salt
    /// okunur, oraya yazmak sessizce başarısız oluyor.
    private func focusWindow(_ element: AXUIElement) {
        // Simge durumuna küçültülmüş pencere `kAXRaiseAction`'a yanıt
        // vermez — önce Dock'tan geri çağrılması gerekiyor.
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private func performActivation(_ window: SwitcherWindowInfo) async {
        let runningApp = NSRunningApplication(processIdentifier: window.pid)

        // Simge durumundaki kart: `windowID` yok (giriş Erişilebilirlik
        // API'sinden geliyor) ama hangi pencere olduğunu başlığından
        // biliyoruz — yalnızca O pencereyi geri çağır, uygulamanın diğer
        // küçültülmüş pencerelerine dokunma.
        if window.isMinimized {
            runningApp?.unhide()
            await bringToFront(runningApp)
            restoreMinimizedWindow(pid: window.pid, title: window.windowTitle)
            return
        }

        // Penceresiz giriş: uygulamanın hiç penceresi yok (hepsi kapatılmış).
        // Öne almak yetmiyor — Dock ikonuna tıklamış gibi davranıp yeni bir
        // pencere açtırmak gerekiyor.
        guard window.windowID != nil else {
            await restoreWindowlessApp(runningApp, pid: window.pid)
            return
        }

        guard let (_, target) = findAXWindow(
            pid: window.pid, title: window.windowTitle, frame: window.frame
        ) else {
            // Pencere kesin olarak bulunamadı: yanlış pencereyi öne
            // getirmektense yalnızca uygulamayı öne al.
            await bringToFront(runningApp)
            return
        }

        // Aynı uygulamanın iki penceresi arasında geçiş yaparken (iki Chrome
        // profili gibi) uygulama zaten öndedir. Onu yeniden öne almak macOS'a
        // uygulamanın kendi "key window"unu geri çağırtıyor, yani seçtiğimiz
        // pencereyi geri alıyordu; bu durumda yalnızca doğru pencereyi
        // seçmek yeterli.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
            await bringToFront(runningApp)
        }

        focusWindow(target)
    }

    /// Başlığı verilen tek bir küçültülmüş pencereyi Dock'tan geri çağırır.
    private func restoreMinimizedWindow(pid: pid_t, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        let target = axWindows.first { element in
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
            guard (minimizedRef as? Bool) == true else { return false }

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            return (titleRef as? String) == title
        }

        guard let target else { return }
        focusWindow(target)
    }

    /// Yalnızca logo gösteren (ekranda penceresi olmayan) bir kart
    /// etkinleştirilince çağrılır. Tek başına `activate()` yetmiyor:
    /// uygulama öne gelir ama pencereleri Dock'ta küçülmüş kalır, kullanıcıya
    /// "hiçbir şey açılmadı" gibi görünür.
    ///
    /// `bringToFront` zaten Dock ikonuna tıklamayla aynı yolu (LaunchServices)
    /// kullanıyor: penceresi olmayan bir uygulamada bu, uygulamaya yeni bir
    /// pencere açtırıyor. Ardından Erişilebilirlik üzerinden küçültülmüş
    /// pencereler de geri çağrılıyor.
    private func restoreWindowlessApp(_ runningApp: NSRunningApplication?, pid: pid_t) async {
        runningApp?.unhide()
        await bringToFront(runningApp)
        deminiaturizeAllWindows(pid: pid)
    }

    /// Uygulamanın bütün AX pencerelerini simge durumundan geri çağırır.
    /// `kAXMinimizedAttribute` okumak bazı uygulamalarda güvenilmez olduğu
    /// için durumu sorgulamadan doğrudan `false` yazıyoruz — zaten açık bir
    /// pencerede bunun etkisi yok. En az bir pencere bulunduysa `true` döner.
    @discardableResult
    private func deminiaturizeAllWindows(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else { return false }

        for axWindow in axWindows {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }

        if let first = axWindows.first {
            AXUIElementSetAttributeValue(first, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(first, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        return true
    }

    /// Kart üzerindeki kırmızı düğme — pencereyi kapatmakla yetinmez,
    /// kullanıcının "o uygulamadan temelli çıkabilmesi" için tüm süreci
    /// sonlandırır. Kart, listeden de hemen kaldırılır.
    ///
    /// İki yol deneniyor, çünkü tek başına hiçbiri her yapılandırmada
    /// çalışmıyor:
    ///
    /// 1. `terminate()` uygulamaya bir "çık" Apple Event'i gönderir. Temiz
    ///    yol budur — uygulama kaydedilmemiş işini sorabilir. Ama sandbox
    ///    içinde (yalnızca Release) Apple Event göndermek ayrı bir
    ///    yetkilendirme istiyor; o olmadığı için istek sessizce düşüyordu.
    ///    Düğmenin "hiçbir şey yapmamasının" sebebi buydu: kart listeden
    ///    kalkıyor ama uygulama açık kalıyordu.
    /// 2. Erişilebilirlik API'siyle uygulamanın kendi "Çık" menü öğesine
    ///    basmak. Anahtar nokta: bu izin (Erişilebilirlik) switcher'ın
    ///    zaten ihtiyaç duyduğu ve kullanıcının verdiği izin, yani yeni bir
    ///    izin penceresi çıkmıyor.
    func closeWindow(_ window: SwitcherWindowInfo) {
        let pid = window.pid
        let app = NSRunningApplication(processIdentifier: pid)

        // `terminate()`in dönüş değerine güvenilmiyor: sandbox'ta istek
        // sessizce düşse de `true` dönebiliyor ve yedek yol hiç
        // denenmiyordu — kart kalkıyor, uygulama açık kalıyordu (export
        // edilen sürümde kullanıcı bildirdi). Onun yerine sonuca
        // bakılıyor: kısa bir süre sonra süreç hâlâ ayaktaysa menü yolu.
        if app?.terminate() != true {
            pressQuitMenuItem(pid: pid)
        } else {
            _Concurrency.Task { @MainActor [weak self] in
                try? await _Concurrency.Task.sleep(for: .milliseconds(800))
                guard let app, !app.isTerminated else { return }
                self?.pressQuitMenuItem(pid: pid)
            }
        }

        removeFromSwitcher(window)
    }

    /// Uygulamanın menü çubuğundaki "Çık" öğesine basar.
    ///
    /// Öğe adına bakmıyoruz — uygulamanın diline göre "Quit", "Çık",
    /// "Beenden" olabilir. Bunun yerine kısayoluna bakıyoruz: Çık öğesi
    /// her uygulamada ⌘Q'dur. `cmdModifiers == 0` "yalnızca Command"
    /// demek, yani ⌥⌘Q gibi başka bir öğeyle karışmıyor.
    private func pressQuitMenuItem(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef else { return }

        var menuBarItemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarRef as! AXUIElement, kAXChildrenAttribute as CFString, &menuBarItemsRef) == .success,
              let menuBarItems = menuBarItemsRef as? [AXUIElement] else { return }

        for menuBarItem in menuBarItems {
            var menuRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &menuRef) == .success,
                  let menu = (menuRef as? [AXUIElement])?.first else { continue }

            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement] else { continue }

            for item in items where isQuitMenuItem(item) {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return
            }
        }
    }

    private func isQuitMenuItem(_ item: AXUIElement) -> Bool {
        var charRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &charRef) == .success,
              let char = charRef as? String,
              char.lowercased() == "q" else { return false }

        var modifiersRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modifiersRef) == .success,
              let modifiers = modifiersRef as? Int else { return false }

        return modifiers == 0
    }

    /// Sarı düğme — pencereyi simge durumuna küçültür.
    func minimizeWindow(_ window: SwitcherWindowInfo) {
        performWindowButtonAction(window, attribute: kAXMinimizeButtonAttribute as String)
    }

    /// Yeşil düğme — pencereyi büyütür / eski boyutuna döndürür.
    func maximizeWindow(_ window: SwitcherWindowInfo) {
        performWindowButtonAction(window, attribute: kAXZoomButtonAttribute as String)
    }

    private func removeFromSwitcher(_ window: SwitcherWindowInfo) {
        guard let index = windows.firstIndex(where: { $0.id == window.id }) else { return }
        windows.remove(at: index)
        guard !windows.isEmpty else {
            hide()
            return
        }
        selectedIndex = min(selectedIndex, windows.count - 1)
        updateOverlay()
    }

    /// `CGWindowID`, Erişilebilirlik API'sinden doğrudan erişilemiyor —
    /// bu yüzden uygulamanın pencerelerini eşleştirmemiz gerekiyor. Önce
    /// konuma göre eşleştiriyoruz (Chrome gibi sayfa başlığı sürekli
    /// değişen uygulamalarda başlık eşleşmesi güvenilmezdi — listeleme
    /// anıyla tıklama anı arasında başlık değişmişse yanlış pencere öne
    /// geliyordu). Konum eşleşmezse başlığa, o da olmazsa ilk pencereye düşer.
    private func findAXWindow(pid: pid_t, title: String, frame: CGRect?) -> (app: AXUIElement, window: AXUIElement)? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return nil }

        if let frame, let byFrame = axWindows.first(where: { axFrame($0)?.approximatelyEquals(frame) == true }) {
            return (appElement, byFrame)
        }

        if let byTitle = axWindows.first(where: { element in
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            return (titleRef as? String) == title
        }) {
            return (appElement, byTitle)
        }

        // Son çare yalnızca tek pencereli uygulamalarda güvenli. Aynı
        // uygulamanın birden çok penceresi varken (iki Chrome profili gibi)
        // "ilkini al" demek, kullanıcının seçtiğinden başka bir pencereyi
        // öne getirmek demekti — dışarıdan bakınca hiçbir şey olmamış gibi
        // görünüyordu, çünkü öne gelen zaten önde duran pencereydi.
        guard axWindows.count == 1, let only = axWindows.first else { return nil }
        return (appElement, only)
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((positionRef as! AXValue), .cgPoint, &origin),
              AXValueGetValue((sizeRef as! AXValue), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Pencerenin trafik ışığı düğmelerinden birini (küçült/büyüt) AX
    /// üzerinden bulup basar — gerçek düğmeye tıklamışız gibi davranır.
    private func performWindowButtonAction(_ window: SwitcherWindowInfo, attribute: String) {
        guard let (_, target) = findAXWindow(pid: window.pid, title: window.windowTitle, frame: window.frame) else { return }
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, attribute as CFString, &buttonRef) == .success,
              let buttonRef else { return }
        AXUIElementPerformAction((buttonRef as! AXUIElement), kAXPressAction as CFString)
    }

    // MARK: - Pencere listesi + küçük resim yakalama

    /// Küçük resim önbelleğinin anahtarı. `CGWindowID` kullanılamıyor çünkü
    /// küçültülmüş pencereler Erişilebilirlik API'sinden geliyor ve orada
    /// pencere kimliği yok — süreç ve başlık birleşimi yeterince ayırt edici.
    private static func cacheKey(pid: pid_t, title: String) -> String {
        "\(pid)|\(title)"
    }

    /// Bir uygulamanın GERÇEKTEN simge durumuna küçültülmüş pencereleri.
    private func minimizedWindows(of app: NSRunningApplication) -> [(title: String, frame: CGRect)] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return [] }

        return axWindows.compactMap { element in
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
            guard (minimizedRef as? Bool) == true else { return nil }

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? app.localizedName ?? ""

            return (title, axFrame(element) ?? .zero)
        }
    }

    /// GlassDo'nun kendi pencerelerinden hangileri değiştiricide yer alır.
    ///
    /// Ana pencere ve ekrana çıkarılmış görev listesi gerçek pencere: onlara
    /// geçmek anlamlı. Değiştiricinin kendi bindirmesi, kenar paneli/rayı ve
    /// masaüstü widget'ları pencere değil yüzey — listede kendilerini
    /// gösterselerdi kullanıcı "geçtiği" anda hiçbir şey olmazdı,
    /// bindirmenin kendisi ise listede kendini gösterirdi.
    private static func isSwitchableOwnWindow(_ windowNumber: CGWindowID) -> Bool {
        guard let window = NSApp.window(withWindowNumber: Int(windowNumber)) else {
            // Tanınmayan bir pencere: SwiftUI'ın kendi yardımcı pencereleri
            // (menü, popover) buraya düşüyor, listeye alınmıyorlar.
            return false
        }
        if window is SwitcherOverlayPanel { return false }
        if window is EdgePanel { return false }
        if window is DesktopWidgetPanel { return false }
        return true
    }

    private func presentSwitcher() async {
        // Fare (ray/menü çubuğu) ya da klavye — hangi yoldan geldiğine
        // bakmaksızın gerçek bir çağırma anı burada tek yerde toplanıyor;
        // ayrıca `showPreview()`/klavye kısayolunda işaretlemek aynı
        // kullanımı iki kez saymak olurdu.
        UsageStore.track(.windowSwitcher, source: .keyboardShortcut)

        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Yalnızca gerçekten ekranda olan pencereler. (`.optionAll`
        // denenmişti ama başka Space'lerdeki ve uygulamaların arka planda
        // tuttuğu gizli pencereleri de getirip aynı uygulamadan onlarca
        // sahte kart üretiyordu.) Küçültülmüş pencereler bunun yerine
        // aşağıda Erişilebilirlik API'sinden kesin olarak bulunuyor.
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // Yalnızca Dock'ta görünen normal uygulamalar — Finder hariç.
        //
        // Finder bir ara listeye alınmıştı: etkinleştirme yolu düzeltilince
        // açık klasör pencerelerine de geçilebilir olmuştu. Ama karttaki
        // kırmızı düğme pencereyi değil **uygulamayı** sonlandırıyor (bkz.
        // `closeWindow`, bilinçli bir karar) ve masaüstünü çizen süreç
        // Finder'ın kendisi: sonlandırıldığı anda masaüstündeki bütün
        // dosyalar ekrandan siliniyor. Üstelik Finder'ın çoğu zaman açık
        // klasör penceresi olmadığı için listede genellikle yalnızca
        // "penceresiz uygulama" kartı olarak beliriyordu — yani kullanıcıya
        // sunduğu tek eylem, masaüstünü yok etme riski taşıyan o düğmeydi.
        // GlassDo'nun kendi pencereleri de listeye giriyor: ekrana
        // çıkarılmış görev listesi ve ana pencere de kullanıcının geçmek
        // isteyeceği pencereler. Eskiden uygulamanın tamamı PID ile
        // dışarıda bırakılıyordu; bunun yerine yalnızca pencere olmayan
        // yüzeyler eleniyor (bkz. `isSwitchableOwnWindow`) — değiştiricinin
        // kendi bindirmesi listede kendini gösteremez.
        let eligibleApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && !Self.excludedBundleIdentifiers.contains(app.bundleIdentifier ?? "")
        }
        let eligiblePIDs = Set(eligibleApps.map(\.processIdentifier))

        typealias Entry = (pid: pid_t, windowID: CGWindowID, appName: String, title: String, frame: CGRect)

        let entries: [Entry] = rawList.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, eligiblePIDs.contains(pid) else { return nil }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            if pid == ownPID, !Self.isSwitchableOwnWindow(windowID) { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 60, (bounds["Height"] ?? 0) > 60 else { return nil }
            let appName = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? appName
            let frame = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )
            return (pid, windowID, appName, title, frame)
        }

        // Küçültülmüş pencere taraması kendi uygulamamızı atlıyor: panel
        // ve widget'lar küçültülemiyor, ana pencere zaten yukarıda
        // yakalanıyor.
        // Gerçekten simge durumuna küçültülmüş pencereler (AX `kAXMinimized`).
        let minimized: [(app: NSRunningApplication, title: String, frame: CGRect)] =
            eligibleApps.filter { $0.processIdentifier != ownPID }.flatMap { app in
                minimizedWindows(of: app).map { (app, $0.title, $0.frame) }
            }

        let pidsWithWindows = Set(entries.map(\.pid)).union(minimized.map(\.app.processIdentifier))

        // Hiç penceresi olmayan (hepsi kapatılmış) uygulamalar — Cmd+Tab'ın
        // da yaptığı gibi en azından logolarıyla listede yer alır.
        let windowlessApps = eligibleApps.filter {
            !pidsWithWindows.contains($0.processIdentifier) && $0.processIdentifier != ownPID
        }

        guard !entries.isEmpty || !minimized.isEmpty || !windowlessApps.isEmpty else { return }

        var built: [SwitcherWindowInfo] = []

        for entry in entries {
            let icon = NSRunningApplication(processIdentifier: entry.pid)?.icon
            // Önce elde olanla çiziliyor: bu pencerenin daha önce alınmış
            // görüntüsü varsa o, yoksa boş. Taze görüntüler bindirim
            // açıldıktan sonra arkada yükleniyor (bkz. `loadThumbnails`).
            let thumbnail = thumbnailCache[Self.cacheKey(pid: entry.pid, title: entry.title)]

            built.append(SwitcherWindowInfo(
                windowID: entry.windowID, pid: entry.pid, appName: entry.appName,
                windowTitle: entry.title, frame: entry.frame, icon: icon, thumbnail: thumbnail
            ))
        }

        for item in minimized {
            let pid = item.app.processIdentifier
            let name = item.app.localizedName ?? ""
            // Küçültülmüş pencere ekranda çizilmediği için yakalanamaz —
            // küçültülmeden önce alınmış son görüntüsü kullanılır.
            let thumbnail = thumbnailCache[Self.cacheKey(pid: pid, title: item.title)]
            built.append(SwitcherWindowInfo(
                windowID: nil, pid: pid, appName: name,
                windowTitle: item.title,
                frame: item.frame.width > 1 ? item.frame : nil,
                icon: item.app.icon, thumbnail: thumbnail, isMinimized: true
            ))
        }

        for app in windowlessApps {
            let name = app.localizedName ?? ""
            built.append(SwitcherWindowInfo(
                windowID: nil, pid: app.processIdentifier, appName: name,
                windowTitle: name, frame: nil, icon: app.icon, thumbnail: nil
            ))
        }

        // Artık var olmayan pencerelerin görüntülerini önbellekte tutma.
        let liveKeys = Set(entries.map { Self.cacheKey(pid: $0.pid, title: $0.title) })
            .union(minimized.map { Self.cacheKey(pid: $0.app.processIdentifier, title: $0.title) })
        thumbnailCache = thumbnailCache.filter { liveKeys.contains($0.key) }

        // Kullanıcı hazırlık sürerken ⌥'i bıraktıysa bindirimi hiç açma.
        guard isSessionActive else { return }

        windows = built
        // İlk Option+Tab, aktif pencerede değil bir sonrakinde başlar —
        // Cmd+Tab'ın alışılmış davranışıyla aynı. Hazırlık sürerken basılan
        // Tab'lar da buraya ekleniyor, böylece hiçbiri kaybolmuyor.
        let start = built.count > 1 ? 1 : 0
        let count = max(built.count, 1)
        selectedIndex = ((start + pendingAdvance) % count + count) % count
        pendingAdvance = 0
        isVisible = true
        presentOverlay()

        await loadThumbnails(for: entries)
    }

    /// Küçük resimleri bindirim açıldıktan SONRA yükler.
    ///
    /// Önceden bunlar `isVisible = true` olmadan önce, pencere başına
    /// sırayla yakalanıyordu; tek başına `SCShareableContent` ~50 ms,
    /// üstüne her pencere için ayrı bir yakalama. Bu süre boyunca
    /// değiştirici "açık değil" sayıldığı için basılan Tab'lar kayboluyor,
    /// bırakılan ⌥ yakalanmıyordu. Artık liste anında çiziliyor, görüntüler
    /// geldikçe yerine oturuyor.
    private func loadThumbnails(
        for entries: [(pid: pid_t, windowID: CGWindowID, appName: String, title: String, frame: CGRect)]
    ) async {
        guard let shareable = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return }

        for entry in entries {
            // Kullanıcı bu arada seçimini yaptıysa yakalamayı sürdürmenin
            // anlamı yok.
            guard isVisible else { return }
            guard let scWindow = shareable.windows.first(where: { $0.windowID == entry.windowID }),
                  let thumbnail = await Self.captureThumbnail(of: scWindow) else { continue }

            let key = Self.cacheKey(pid: entry.pid, title: entry.title)
            thumbnailCache[key] = thumbnail

            guard isVisible,
                  let index = windows.firstIndex(where: { $0.windowID == entry.windowID })
            else { continue }
            windows[index].thumbnail = thumbnail
            updateOverlay()
        }
    }

    private static func captureThumbnail(of window: SCWindow) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // `width`/`height` ÇIKTI piksel arabelleğinin boyutu. Daha önce nokta
        // boyutu (1x) veriliyordu — bu da Retina ekranlarda küçük resmi
        // düşük çözünürlükte yakalayıp kart boyutuna büyütünce metni
        // bulanıklaştırıyordu (özellikle metin yoğun Chrome sayfalarında
        // fark ediliyordu). Ekranın gerçek `backingScaleFactor`'ü ile
        // çarpıp native çözünürlükte yakalıyoruz.
        let scale = (NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }) ?? NSScreen.main)?.backingScaleFactor ?? 2
        config.width = max(Int((window.frame.width * scale).rounded()), 2)
        config.height = max(Int((window.frame.height * scale).rounded()), 2)
        // `scalesToFit`, içeriği en-boy oranını KORUYARAK arabelleğe
        // sığdırıyor — arabelleğin oranı pencereninkiyle birebir aynı olsa
        // bile yuvarlama farkları köşelerde ince boşluk (letterbox) olarak
        // beliriyor, "bütün pencere küçültülüp içeride yüzüyor" görünümü
        // veriyordu. `width`/`height`'ı zaten pencerenin native piksel
        // boyutuna eşitlediğimiz için ek ölçeklemeye hiç gerek yok.
        config.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // `size`, NOKTA cinsinden veriliyor (piksel değil) — aksi hâlde
            // AppKit görüntüyü Retina'da 2x değil "dev bir 1x görüntü"
            // sanıp yanlış temsilini seçebiliyordu.
            return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        } catch {
            return nil
        }
    }

    // MARK: - Bindirim penceresi

    private func presentOverlay() {
        let panel: SwitcherOverlayPanel
        if let existing = overlayPanel {
            panel = existing
            panel.alphaValue = 1
        } else {
            panel = SwitcherOverlayPanel(contentRect: .zero)
            overlayPanel = panel
        }
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        layoutOverlay()
        panel.orderFrontRegardless()
        startOutsideClickMonitor()
    }

    /// Bindirimin dışına tıklayınca kapanması.
    ///
    /// `NSWorkspace.didActivateApplication` gözlemcisi (bkz.
    /// `installActivationObserverIfNeeded`) bunun yalnızca bir kısmını
    /// yakalıyordu: tıklanan uygulama zaten önplandaysa uygulama değişimi
    /// olmuyor, bildirim hiç gelmiyor ve bindirim ekranda asılı kalıyordu.
    /// Genel fare izleyicisi yalnızca **başka** uygulamalara giden olayları
    /// gördüğü için kartlara yapılan tıklamalar buraya düşmüyor.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissPreview()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func updateOverlay() {
        guard let panel = overlayPanel else { return }
        (panel.contentView as? NSHostingView<SwitcherOverlayView>)?.rootView = overlayView
        // Kart kaldırıldığında/eklendiğinde toplam boyut değişir.
        layoutOverlay()
    }

    /// Bindirim, imlecin bulunduğu ekranda gösterilir.
    private var overlayScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private var overlayView: SwitcherOverlayView {
        let screenWidth = overlayScreen?.visibleFrame.width ?? 1200
        return SwitcherOverlayView(
            windows: windows,
            selectedIndex: selectedIndex,
            onSelect: { [weak self] window in self?.selectAndActivate(window) },
            onDismiss: { [weak self] in self?.dismissPreview() },
            onClose: { [weak self] window in self?.closeWindow(window) },
            onMinimize: { [weak self] window in self?.minimizeWindow(window) },
            onMaximize: { [weak self] window in self?.maximizeWindow(window) },
            // Dış dolgu (2×20) ve ekran kenarında nefes payı düşülüyor.
            maxRowWidth: max(screenWidth - 160, 320)
        )
    }

    private func layoutOverlay() {
        guard let panel = overlayPanel,
              let hostingView = panel.contentView,
              let screen = overlayScreen else { return }

        // Kartlar pencerelerin en-boy oranına göre farklı genişliklerde ve
        // gerektiğinde birden çok satıra sarıldığı için boyut artık sabit
        // değil — görünümün kendi doğal ölçüsünü kullanıyoruz.
        let size = hostingView.fittingSize
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func dismissOverlay() {
        guard let panel = overlayPanel else { return }
        guard WindowSwitcherSettings.fadeOutEnabled else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
    }
}

/// ApplicationServices'in `var` olarak dışa verdiği bu sabit, Swift 6'nın
/// katı eşzamanlılık denetimi altında "paylaşılan değişebilir durum"
/// sayılıyor — pratikte hiç değişmeyen bir CFString sabiti olduğu için
/// güvenle `nonisolated(unsafe)` işaretleniyor.
nonisolated(unsafe) private let axTrustedPromptKey = kAXTrustedCheckOptionPrompt

/// `CGEventTapCallBack` bir `@convention(c)` fonksiyon işaretçisi bekler —
/// Swift closure'ları context yakalayamaz, bu yüzden serbest bir fonksiyon
/// olarak tanımlanıp `userInfo` üzerinden controller'a erişiyor.
private func windowSwitcherEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let controller = Unmanaged<WindowSwitcherController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleTapEvent(type: type, event: event)
}
