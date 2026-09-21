import Foundation

public extension String {
    /// Ekranda gerçekten bir şey gösterir mi?
    ///
    /// Not editöründe satır arası boşluk bırakmak, veri tarafında başlığı
    /// "boş" bir görev yaratıyor. Ama bu başlıklar her zaman tam olarak
    /// boş olmuyor: silinen bir onay kutusundan geriye kalan nesne yer
    /// tutucusu (U+FFFC) ya da yapıştırılan metinden gelen sıfır
    /// genişlikli karakterler kalabiliyor. Bunlar boşluk sayılmadığı için
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` onları
    /// temizlemiyor ve satır listede boş bir kutu olarak görünüyordu.
    ///
    /// Burada tek tek karakter aramak yerine tersi soruluyor: içinde
    /// görünür tek bir karakter var mı?
    var hasVisibleContent: Bool {
        unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
                && !invisibleScalars.contains(scalar)
        }
    }
}

/// Boşluk ya da kontrol karakteri sayılmayan, yine de hiçbir şey çizmeyen
/// karakterler.
private let invisibleScalars: CharacterSet = [
    "\u{FFFC}",  // nesne yer tutucusu — metne gömülü ek (onay kutusu)
    "\u{FFFD}",  // çözülemeyen karakter
    "\u{200B}",  // sıfır genişlikli boşluk
    "\u{200C}",  // sıfır genişlikli birleştirmeyen
    "\u{200D}",  // sıfır genişlikli birleştiren
    "\u{2060}",  // kelime birleştirici
    "\u{FEFF}",  // bayt sırası işareti
]
