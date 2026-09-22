import AppKit

/// Etkin olmayan uygulamada metin kısayollarını (⌘C, ⌘V, ⌘X, ⌘A, ⌘Z)
/// çalıştırır.
///
/// Bu kısayolların hiçbiri uygulamanın kendi kodunda yok: hepsi sistemin
/// Düzen menüsünden gelir ve menü, yalnızca uygulama **öndeyken** klavye
/// kısayollarını yakalar. Yapışkan not ve kenar paneli ise
/// `.nonactivatingPanel`: onlara tıklamak uygulamayı öne getirmiyor —
/// zaten amaç bu, kullanıcı Chrome'la çalışırken notu kaybetmesin diye.
/// Sonuç olarak panelde yazmak çalışıyor (tuş vuruşları doğrudan ilk
/// yanıtlayıcıya gidiyor) ama kopyala/yapıştır hiç tepki vermiyordu:
/// ⌘C menüye gidiyor, menü bizim değil, olay düşüyordu.
///
/// Çözüm, kısayolu pencere düzeyinde karşılayıp eylemi **pencerenin kendi**
/// yanıtlayıcı zincirine göndermek.
///
/// Burada `NSApp.sendAction(…, to: nil, …)` işe yaramıyor: o yol hedefi
/// `NSApp.keyWindow` üzerinden arıyor ve uygulama etkin değilken bu
/// `nil` — panel kendi içinde key olsa bile. Ölçüldü: etkin olmayan bir
/// uygulamada `sendAction` `copy:` için bile `false` dönüyor, aynı anda
/// `firstResponder.tryToPerform(…)` altı eylemin hepsini çalıştırıyor.
///
/// `tryToPerform` ilk yanıtlayıcıdan başlayıp zinciri yukarı yürüyor;
/// böylece not belgesinde de, alttaki hızlı ekleme alanında da (alan
/// düzenleyicisi o anda ilk yanıtlayıcıdır) doğru yere düşüyor. Geri
/// al/yinele de bu yolla çalışıyor: `undo:` seçicisini zincirdeki hiçbir
/// nesne `responds(to:)` ile kabul etmiyor, AppKit onu çalışma anında
/// pencerenin geri alma yöneticisine bağlıyor.
extension NSPanel {

    /// Olay bir metin kısayoluysa çalıştırır ve `true` döner.
    func performsTextEditingKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }

        let withShift = flags.contains(.shift)

        let action: Selector? = switch key {
        case "x": withShift ? nil : #selector(NSText.cut(_:))
        case "c": withShift ? nil : #selector(NSText.copy(_:))
        case "v": withShift ? #selector(NSTextView.pasteAsPlainText(_:)) : #selector(NSText.paste(_:))
        case "a": withShift ? nil : #selector(NSResponder.selectAll(_:))
        // Geri al/yinele yanıtlayıcı zincirinde `undo:`/`redo:` olarak
        // dolaşıyor; Swift'te bu seçicilerin bildirimi yok, bu yüzden
        // adlarıyla kuruluyorlar. Karşılayan yoksa `sendAction` zaten
        // `false` dönüyor.
        case "z": withShift ? Selector(("redo:")) : Selector(("undo:"))
        default: nil
        }

        guard let action, let responder = firstResponder else { return false }
        return responder.tryToPerform(action, with: self)
    }
}
