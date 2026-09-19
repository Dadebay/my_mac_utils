import AppKit
import Foundation
import UniformTypeIdentifiers

/// Raftan dışarı sürüklenen dosyanın hedefe devrini yürütür.
///
/// Önceki sürüm, bırakmanın gerçekten kabul edilip edilmediğini SwiftUI'ın
/// `.onDrag`'ı hiç bildirmediği için, dosyayı elle kurulmuş tembel bir
/// `NSItemProvider.registerFileRepresentation` temsili arkasına saklıyordu:
/// sistem dosyayı ancak hedef gerçekten isteyince okusun, o istek de
/// bırakmanın kabul edildiğinin işareti olsun diye. Bu iki ayrı şekilde
/// geri tepti:
///
/// 1. Raf, sürüklenen kutucuğun kendisinin de üstünde bulunduğu bir
///    `.onDrop` hedefi olduğu için SwiftUI, sürükleme sırasında "hedefte
///    isabet var mı" diye aynı sağlayıcıyı kendi içinde de okumaya
///    çalışıyor (`loadInPlaceFileRepresentationForTypeIdentifier`). Elle
///    kurulan temsil bunu desteklemediğinden SwiftUI'ın kendi köprüleme
///    kodu `nil` bir URL'i zorla çözmeye çalışıp uygulamayı çöktürüyordu.
/// 2. `.openInPlace` ekleyip o çökmeyi durdurunca bu kez Finder'ın kendisi
///    bırakmayı hiç kabul etmez oldu (imleçte "yasak" simgesi) — Finder
///    gerçek, önceden hazır bir dosya temsili bekliyor, elle kurulmuş
///    tembel/yerinde temsili güvenilir bulmuyor.
///
/// Çözüm: kendi temsilimizi elle kurmak yerine `NSItemProvider(contentsOf:)`
/// kullanmak — Finder'ın (ve hemen hemen her uygulamanın) zaten güvendiği,
/// sıradan "burada gerçek, diskte hazır bir dosya var" yolu. Bunun bedeli:
/// artık bırakmanın gerçekten tamamlanmasını bekleyemiyoruz — "kes" kipinde
/// asıl dosya, sürükleme başlar başlamaz Çöp'e gidiyor. İptal edilen bir
/// sürüklemede de öğe rafdan çıkmış olacak, ama Çöp'e gittiği için kayıp
/// değil, geri alınabilir; bunun karşılığında gerçek bırakmalar artık
/// güvenilir çalışıyor.
enum ShelfDragHandoff {
    /// Devredilen geçici kopyaların toplandığı klasör. Tek bir yerde
    /// toplanıyor ki eskiyenler topluca temizlenebilsin.
    private static let handoffDirectoryName = "GlassDoShelfHandoff"

    /// Devir kopyalarının saklanma süresi. Sistem geçici klasörü kendi
    /// takvimiyle temizliyor; bu yalnızca uygulamanın kendi artıklarını
    /// biriktirmemesi için.
    private static let handoffLifetime: TimeInterval = 60 * 60

    /// Sürüklemeye başlarken çağrılır — dosya burada hazırlanıp teslim
    /// edilir, kabul edilip edilmediği beklenmez.
    static func provider(for item: StorageItem, removesOnDragOut: Bool) -> NSItemProvider {
        guard removesOnDragOut else {
            // "Kopyala" kipi: rafın dosyası olduğu gibi verilir, raf
            // dokunulmadan kalır.
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }

        guard let handoff = try? makeHandoffCopy(of: item.url) else {
            // Kopya çıkarılamadıysa dosyayı yine de teslim et ama raftan
            // düşürme: kullanıcı hem dosyasını hem rafındakini kaybetmesin.
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }

        return NSItemProvider(contentsOf: handoff) ?? NSItemProvider()
    }

    /// Hedefe verilecek geçici kopyayı üretir. Dosya adı korunuyor ki
    /// Finder'a bırakıldığında doğru isimle inisin.
    private static func makeHandoffCopy(of url: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(handoffDirectoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// Geride kalan devir kopyalarını temizler. Raf görünürken çağrılıyor;
    /// sürükleme sırasında yapılsaydı sistemin hâlâ okuduğu bir kopyayı
    /// silme riski olurdu.
    static func purgeStaleHandoffs() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(handoffDirectoryName, isDirectory: true)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-handoffLifetime)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
