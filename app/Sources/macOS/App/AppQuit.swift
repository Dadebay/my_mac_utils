import AppKit

/// Uygulamanın gerçekten kapanıp kapanmayacağına karar veren yer.
///
/// Menü çubuğu ölçerleri, kenar paneli, masaüstü widget'ları ve yapışkan
/// notlar pencereye değil sürece bağlı. Dock'taki "Çık" ya da uygulama
/// menüsündeki ⌘Q süreci öldürünce hepsi birden gidiyordu — kullanıcı
/// yalnızca Dock'taki simgeyi kapatmak istemişti. Artık bu yollar
/// uygulamayı "arka plana" alıyor: pencereler kapanıyor, Dock simgesi
/// kalkıyor, widget'lar çalışmaya devam ediyor.
///
/// Gerçek çıkış yalnızca menü çubuğundaki "Çık" düğmelerinden
/// (`AppQuit.terminate()`) ya da sistemden (oturum kapatma, yeniden
/// başlatma, kapatma) geliyor — sistemin çıkışını engellemek oturumun
/// kapanmasını da engellerdi.
@MainActor
enum AppQuit {
    /// Bir sonraki `terminate` isteğinin gerçekten kapatması isteniyor.
    private static var isExplicit = false

    /// Menü çubuğundaki "Çık": süreç gerçekten sonlanıyor.
    static func terminate() {
        isExplicit = true
        NSApp.terminate(nil)
    }

    /// `applicationShouldTerminate` bunu soruyor.
    static func shouldTerminate() -> Bool {
        isExplicit || isSystemQuit
    }

    /// Oturum kapatma / yeniden başlatma / kapatma sırasında sistemin
    /// gönderdiği "çık" olayı bir neden taşıyor; Dock'un gönderdiği
    /// taşımıyor.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass,
              event.eventID == kAEQuitApplication
        else { return false }
        return event.attributeDescriptor(forKeyword: kAEQuitReason) != nil
    }

    /// Dock simgesini kaldırıp pencereleri kapatır. Paneller (kenar
    /// paneli, widget'lar, notlar, pencere değiştirici) yerinde kalıyor.
    static func moveToBackground() {
        for window in NSApp.windows where !(window is NSPanel) && window.isVisible {
            if window.styleMask.contains(.titled) { window.close() }
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Bir pencere yeniden açıldığında Dock simgesi geri geliyor — pencere
    /// ⌘Tab'da ve Dock'ta bulunamazsa kaybolmuş gibi görünür.
    static func restoreDockIconIfNeeded(for window: NSWindow) {
        guard NSApp.activationPolicy() != .regular,
              !(window is NSPanel),
              window.styleMask.contains(.titled)
        else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
