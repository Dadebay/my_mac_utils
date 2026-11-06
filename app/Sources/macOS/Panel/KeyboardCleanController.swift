import AppKit
import ApplicationServices
import GlassDoKit
import Observation

/// Klavye temizleme kipi: etkinken bütün tuş vuruşlarını (medya/fonksiyon
/// tuşları dahil) sistemden tüketir, fare çalışmaya devam eder. İsteğe
/// bağlı olarak izleme dörtgenini de (hareket, tıklama, kaydırma, hareketler)
/// kapatır — olay düzeyinde izleme dörtgeni ile harici fare birbirinden
/// ayırt edilemediği için bu seçenekte bütün işaretçi girdisi durur.
///
/// Takılı kalmamak için iki çıkış yolu var: geri sayım bitince otomatik
/// kapanır, ve Escape'e 1,5 sn içinde üç kez basmak kipi hemen bitirir.
@MainActor
@Observable
final class KeyboardCleanController {
    static let shared = KeyboardCleanController()

    static let durationOptions: [Int] = [15, 30, 60, 120]
    private static let durationKey = "keyboardClean.duration"
    private static let trackpadKey = "keyboardClean.blockTrackpad"

    /// Kullanıcının seçtiği süre. Trackpad kapalıyken bitirmenin tek yolu
    /// Esc×3 ya da süre dolması olduğu için süre kısa tutulabilmeli.
    var duration: Int = {
        let stored = UserDefaults.standard.integer(forKey: "keyboardClean.duration")
        return KeyboardCleanController.durationOptions.contains(stored) ? stored : 30
    }() {
        didSet { UserDefaults.standard.set(duration, forKey: Self.durationKey) }
    }

    private(set) var isActive = false
    private(set) var secondsRemaining = 30
    private(set) var needsPermission = false

    var blockTrackpad: Bool = UserDefaults.standard.bool(forKey: KeyboardCleanController.trackpadKey) {
        didSet { UserDefaults.standard.set(blockTrackpad, forKey: Self.trackpadKey) }
    }

    @ObservationIgnored private var eventTap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var countdown: _Concurrency.Task<Void, Never>?
    @ObservationIgnored private var escapePresses: [TimeInterval] = []
    @ObservationIgnored private var blocksPointer = false

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            needsPermission = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return
        }
        needsPermission = false
        blocksPointer = blockTrackpad

        var types: [UInt32] = [
            CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            14,  // NX_SYSDEFINED: parlaklık, ses, medya tuşları
        ]
        if blocksPointer {
            types += [
                CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            ].map(\.rawValue)
            types += [18, 19, 20, 29, 30, 31, 32]  // izleme dörtgeni hareketleri
        }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardCleanTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            needsPermission = true
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        escapePresses = []
        secondsRemaining = duration
        isActive = true
        countdown = _Concurrency.Task { @MainActor [weak self] in
            while let self, self.isActive, self.secondsRemaining > 0 {
                try? await _Concurrency.Task.sleep(for: .seconds(1))
                if _Concurrency.Task.isCancelled { return }
                self.secondsRemaining -= 1
            }
            self?.stop()
        }
    }

    func stop() {
        countdown?.cancel()
        countdown = nil
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    /// C callback'ten çağrılır; tap ana döngüde olduğu için `assumeIsolated`
    /// güvenli (bkz. `WindowSwitcherController.handleTapEvent`).
    nonisolated fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            }
            return Unmanaged.passRetained(event)
        }
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 {
                MainActor.assumeIsolated { registerEscape() }
            }
        }
        return nil
    }

    private func registerEscape() {
        let now = ProcessInfo.processInfo.systemUptime
        escapePresses = escapePresses.filter { now - $0 < 1.5 } + [now]
        if escapePresses.count >= 3 { stop() }
    }
}

private func keyboardCleanTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let controller = Unmanaged<KeyboardCleanController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleTapEvent(type: type, event: event)
}
