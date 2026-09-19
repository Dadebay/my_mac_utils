import SwiftData
import Foundation

@Model
public final class FolderBookmark {
    public var id: UUID = UUID()
    public var path: String = ""
    public var name: String = ""
    public var sortIndex: Int = 0

    /// Klasörü GlassDo mu oluşturdu?
    ///
    /// `true` ise dizin uygulamanın kendi alanında (`Application Support/
    /// GlassDo/Storage/<UUID>`) duruyor ve panel içinden gezilebilir, içine
    /// dosya kopyalanabilir, Çöp Kutusu'na taşınabilir. `false` ise
    /// kullanıcının kendi diskindeki bir klasöre yalnızca bağ tutuluyor;
    /// oraya hiçbir yıkıcı işlem yapılmıyor.
    ///
    /// Varsayılanı `false`: hafif geçişle uyumlu, mevcut kayıtlar bağlanmış
    /// klasör olarak okunmaya devam ediyor.
    public var isManagedStorage: Bool = false

    public init(path: String = "", name: String = "", isManagedStorage: Bool = false) {
        self.path = path
        self.name = name
        self.isManagedStorage = isManagedStorage
    }
}
