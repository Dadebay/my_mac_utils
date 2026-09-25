import Foundation
import SwiftData

/// Masaüstünde serbestçe duran tek bir yapışkan not.
///
/// Notun içeriği ana görev listesinin kendisi; not yalnızca rengini ve
/// ekrandaki yerini taşıyor. Bir süre her notun kendi satırları vardı
/// (`blocks`), ama not ile ana pencere birbirinden ayrışıyordu ve
/// kullanıcı notun ana listenin kopyası olmasını istedi. O dönemden kalan
/// satırlar açılışta ana listeye taşınıyor (bkz. `StickyNoteMerge`);
/// `blocks` ilişkisi şema uyumu için duruyor, yeni satır almıyor.
@Model
public final class StickyNote {
    public var id: UUID = UUID()

    /// `NoteTint` sırası. Her notun kendi rengi var; masaüstünde yan yana
    /// duran notları birbirinden ayıran asıl şey bu.
    public var tintRaw: Int = 0

    /// Pencerenin ekrandaki yeri, `NSStringFromRect` biçiminde. Boşsa
    /// controller yeni bir yer seçiyor.
    public var frameString: String = ""

    public var createdAt: Date = Date()

    /// Ayrı not döneminden kalma satırlar — artık hep boş.
    @Relationship(deleteRule: .cascade, inverse: \Task.stickyNote)
    public var blocks: [Task]? = []

    public init(tintRaw: Int = 0) {
        self.tintRaw = tintRaw
    }
}

public extension StickyNote {
    /// Satırlar her zaman sıra numarasına göre — ilişki dizisi sırayı
    /// korumuyor.
    var orderedBlocks: [Task] {
        (blocks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}
