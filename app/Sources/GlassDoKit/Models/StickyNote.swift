import Foundation
import SwiftData

/// Masaüstünde serbestçe duran tek bir yapışkan not.
///
/// Notun içeriği görev listesinin kendisi değil, kendi satırları. Eskiden
/// not, ana listenin ikinci bir görünümüydü: nottaki bir satıra tik atmak
/// onu "tamamlandı" yapıp listeden düşürüyordu ve satır notun ortasından
/// kayboluyordu. Yapışkan bir notta beklenen şey bu değil — tik atılan
/// satır yerinde, üstü çizili olarak durur.
///
/// Satırlar yine `Task`: blok türleri (görev, başlık, madde, ayırıcı)
/// zaten orada tanımlı ve not editörü onların üzerine kurulu. Fark, bu
/// satırların `stickyNote` alanının dolu olması — ana listenin
/// sorguları onları dışarıda bırakıyor.
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

    /// Notun satırları. Not silinince satırları da gidiyor — ana listede
    /// sahipsiz satır olarak kalmazlar.
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
