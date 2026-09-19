import AppKit
import Foundation

/// Aktif (öndeki) uygulamayı izleyen tek merkezi servis.
///
/// Yalnızca bundle ID ve görünen adı bellekte tutuluyor — pencere başlığı,
/// URL, yazılan metin veya ekran içeriği hiçbir zaman okunmuyor/saklanmıyor.
/// `NSWorkspace.didActivateApplicationNotification` dinleniyor, polling
/// yapılmıyor; bu yüzden Accessibility izni gerekmiyor.
@MainActor
@Observable
final class ActiveApplicationMonitor {
    static let shared = ActiveApplicationMonitor()

    private(set) var activeBundleIdentifier: String?
    private(set) var activeApplicationName: String?

    private var observer: NSObjectProtocol?

    private init() {}

    var isRunning: Bool { observer != nil }

    func start() {
        guard observer == nil else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        activeBundleIdentifier = frontmost?.bundleIdentifier
        activeApplicationName = frontmost?.localizedName

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            _Concurrency.Task { @MainActor in
                self?.activeBundleIdentifier = app.bundleIdentifier
                self?.activeApplicationName = app.localizedName
            }
        }
    }

    /// Özellik kapatılınca çağrılır — bellekteki bilgi de temizlenir,
    /// yalnızca dinleme durmuyor.
    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        activeBundleIdentifier = nil
        activeApplicationName = nil
    }

    /// Kural oluşturma menüsü için: yüklü/çalışan, normal (arka plan
    /// aracısı olmayan) uygulamalar. Serbest bundle ID girişi asla
    /// sunulmuyor — yalnızca bu listeden seçilebiliyor.
    static func runningRegularApplications() -> [(bundleIdentifier: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let bundleIdentifier = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (bundleIdentifier, name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}
