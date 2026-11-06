import Foundation
import Observation

/// Klavye arka ışığı. `CoreBrightness` özel çatısındaki
/// `KeyboardBrightnessClient` çalışma zamanında yüklenir; bulunamazsa
/// (ışıksız klavye, farklı macOS sürümü) `isAvailable` false kalır ve
/// arayüz denetimi göstermez.
@MainActor
@Observable
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()

    private typealias GetBrightness = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private(set) var isAvailable = false
    private(set) var level: Double = 0

    @ObservationIgnored private var client: NSObject?
    @ObservationIgnored private var keyboardID: UInt64 = 0

    private init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }
        let client = cls.init()
        guard let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                .takeRetainedValue() as? [NSNumber],
              let first = ids.first
        else { return }
        self.client = client
        keyboardID = first.uint64Value
        isAvailable = true
        refresh()
    }

    func refresh() {
        guard let client else { return }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let imp = client.method(for: sel) else { return }
        let value = unsafeBitCast(imp, to: GetBrightness.self)(client, sel, keyboardID)
        level = Double(min(max(value, 0), 1))
    }

    func set(_ value: Double) {
        guard let client else { return }
        let clamped = min(max(value, 0), 1)
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let imp = client.method(for: sel) else { return }
        _ = unsafeBitCast(imp, to: SetBrightness.self)(client, sel, Float(clamped), keyboardID)
        level = clamped
    }

    func step(_ delta: Double) { set(level + delta) }
}
