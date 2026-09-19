import Foundation

/// Panel penceresinin üzerinde şu an bir dış sürükleme duruyor mu.
///
/// Sürüklemeyi artık pencerenin kendisi karşılıyor (bkz. `EdgePanel`), ama
/// "kabul etmeye açılıyor" görseli rafın SwiftUI görünümünde. İkisi arasında
/// tek yönlü, küçük bir köprü: AppKit tarafı yazar, `PanelShelfView` okur.
@MainActor
@Observable
final class ShelfDropTargeting {
    static let shared = ShelfDropTargeting()

    var isTargeted = false

    /// İçeri aktarma pencere katmanında başarısız olduysa gösterilecek metin.
    /// Rafın hata bandı bunu okuyor; aksi hâlde hata sessizce yutulurdu.
    var lastErrorMessage: String?

    private init() {}
}
