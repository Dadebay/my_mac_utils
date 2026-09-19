import GlassDoKit
import SwiftUI

/// Masaüstüne çıkarılabilen pano kartları.
///
/// Ham değerler kalıcı: hangi widget'ların açık olduğu ve nerede durdukları
/// `UserDefaults`'a bu adlarla yazılıyor. Bir case yeniden adlandırılırsa
/// kullanıcının açık widget'ı bir daha geri gelmez — yeni bir case ekleyip
/// eskisini bırakmak gerekir.
enum DesktopWidgetKind: String, CaseIterable, Identifiable, Sendable {
    case processor
    case memory
    case network
    case networkActivity
    case battery
    case batteryHealth
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processor: L10n.processorLoadLabel
        case .memory: L10n.memoryLabel
        case .network: L10n.networkDataLabel
        case .networkActivity: L10n.networkActivityLabel
        case .battery: L10n.batteryLabel
        case .batteryHealth: L10n.batteryHealthLabel
        case .disk: L10n.diskLabel
        }
    }

    /// Pencerenin ilk boyu. Kartların içeriği farklı yoğunlukta: ağ
    /// etkinliği tek grafik, bellek ise halka + üç satır künye.
    var defaultSize: CGSize {
        switch self {
        case .processor: CGSize(width: 340, height: 300)
        case .memory: CGSize(width: 340, height: 300)
        case .network: CGSize(width: 340, height: 260)
        case .networkActivity: CGSize(width: 340, height: 230)
        case .battery: CGSize(width: 340, height: 270)
        case .batteryHealth: CGSize(width: 340, height: 250)
        case .disk: CGSize(width: 340, height: 270)
        }
    }
}
