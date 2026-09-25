import AppKit
import GlassDoKit
import SwiftUI

extension NSAttributedString.Key {
    /// Satır başındaki işaretin (onay kutusu, madde noktası, sıra
    /// numarası) karakterleri. Bu işaretler kullanıcının yazdığı metin
    /// değil, bloğun türünün çizimi — belgeden geri okurken atılmaları
    /// gerekiyor.
    ///
    /// Önce metne bakarak ayıklanıyorlardı ("•  " ile başlıyorsa kes gibi).
    /// O yaklaşım kullanıcının kendi yazdığı metni işaret sanabiliyordu:
    /// Markdown yapıştıran biri satır başında "- [ ] " görüyor ve bu
    /// ayıklanıp kalıcı olarak siliniyordu. Öznitelik kullanınca hangi
    /// karakterlerin bizim çizdiğimiz olduğu kesin — metnin kendisi ne
    /// olursa olsun dokunulmuyor.
    static let glassDoMarker = NSAttributedString.Key("glassDoMarker")

    /// Paragrafın hangi göreve ait olduğu. Kimlik metnin kendisinde
    /// taşınıyor: kullanıcı satır ekleyip silerken sıra numarasına
    /// güvenilemez, ama `NSTextStorage` öznitelikleri düzenleme boyunca
    /// paragrafla birlikte taşınıyor. Enter'a basılınca yeni paragraf
    /// aynı kimliği miras alıyor — ikinci kez görülen kimlik, bölünmenin
    /// işareti (bkz. `NoteDocumentSync`).
    static let glassDoBlockID = NSAttributedString.Key("glassDoBlockID")
}

/// Metin görünümünden okunan tek bir paragraf.
struct NoteParagraph: Equatable {
    /// Paragrafın geldiği görev — yeni yazılmış bir satırda `nil`.
    var id: UUID?
    var text: String
}

/// SwiftUI tarafındaki denetimlerin metin görünümüne ulaşmasını sağlayan
/// ince köprü.
///
/// Seçim çubuğundaki çöp kutusu gibi denetimler AppKit'in seçimini
/// kullanmak zorunda: "seçili metni sil" komutunun karşılığı yalnızca
/// metin görünümünde var. Köprü olmadan SwiftUI'dan oraya ulaşmanın yolu
/// pencereyi ve ilk yanıtlayıcıyı elle aramaktan geçiyordu.
@MainActor
final class NoteEditorBridge {
    weak var textView: NSTextView?

    /// Seçili metni siler. Silme `textDidChange`'i tetikliyor, model de
    /// oradan eşitleniyor.
    func deleteSelectedText() {
        guard let textView, textView.selectedRange().length > 0 else { return }
        textView.delete(nil)
    }
}

/// Metin görünümündeki seçimin, çağıranın ihtiyacı olan özeti.
struct NoteSelection: Equatable {
    /// Seçimin dokunduğu bloklar.
    var blockIDs: [UUID] = []
    /// Gerçek bir aralık mı, yoksa yalnızca imleç mi.
    var isRange: Bool = false
    /// Seçim, dokunduğu blokların tamamını kapsıyor mu.
    var coversWholeBlocks: Bool = false
}

/// Notun tamamını **tek bir metin belgesi** olarak çizen editör.
///
/// Önceki sürümde her satır ayrı bir `NSTextField`'dı. macOS'ta her metin
/// alanı kendi düzenleyicisine sahip olduğu için satırlar arasına yayılan
/// bir seçim mümkün değildi — kullanıcı notun tamamını seçip kopyalayamıyordu.
/// Tek metin görünümünde seçim, sürükleme, ⌘A ve kopyalama sistemin kendi
/// davranışı; bizim yazmamız gereken tek şey paragrafların görevlerle
/// eşlenmesi.
struct NoteDocumentView: NSViewRepresentable {
    var tasks: [Task]
    var isDark: Bool
    var fontScale: Double
    /// Metin değiştiğinde paragrafların son hâli — çağıran bunu görevlerle
    /// eşitliyor.
    var onEdit: ([NoteParagraph]) -> Void
    /// Onay kutusuna tıklandı.
    var onToggle: (UUID) -> Void
    /// Boş bir satırda Backspace: satır boş satıra dönüyor.
    var onClearMarker: (UUID) -> Void
    /// Metnin tam başında Backspace: işaret kalkıyor, metin kalıyor.
    var onRemoveMarker: (UUID) -> Void
    /// Metin görünümüne komut göndermek için (bkz. `NoteEditorBridge`).
    var bridge: NoteEditorBridge
    /// Seçimin kapsadığı görevler — biçim çubuğu bunu okuyor.
    var onSelectionChange: (NoteSelection) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView()
        textView.delegate = context.coordinator
        textView.onToggle = onToggle
        textView.onClearMarker = onClearMarker
        textView.onRemoveMarker = onRemoveMarker
        textView.isRichText = false
        /* Metin görünümünün kendi geri alması kapalı: geri alma artık
           modelin yöneticisinde (bkz. `AppStore.makeContainer`). Açık
           kalsaydı iki yığın aynı ⌘Z için yarışırdı. */
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        /* Dikeyde serbestçe uzayabilmesi için üst sınırın açık olması
           gerekiyor; varsayılan sınır ilk çerçeveden geliyor ve uzun bir
           notta düzen o yükseklikte takılıp kalıyor. */
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 10)
        textView.textContainer?.widthTracksTextView = true
        // Akıllı tırnak ve otomatik düzeltme bir not defterinde yazılanı
        // sessizce değiştiriyordu — kod parçası ve bağlantı yapıştırmak
        // bu notun sık kullanımı.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        // Kaydırma çubuğu yok: dar not penceresinde sistem ayarı "her zaman
        // göster" olduğunda metnin sağ kenarına biniyordu. Kaydırma tekerlek
        // ve trackpad'le çalışmaya devam ediyor.
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        bridge.textView = textView
        context.coordinator.render(tasks: tasks, isDark: isDark, fontScale: fontScale)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NoteTextView else { return }
        bridge.textView = textView
        textView.onToggle = onToggle
        textView.onClearMarker = onClearMarker
        textView.onRemoveMarker = onRemoveMarker
        // Kullanıcı yazarken yeniden çizmek imleci başa atardı; yalnızca
        // dışarıdan gelen değişikliklerde (ana pencerede görev eklendi,
        // tamamlandı) belge tazeleniyor.
        guard !context.coordinator.isApplyingEdit else { return }
        context.coordinator.renderIfChanged(tasks: tasks, isDark: isDark, fontScale: fontScale)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteDocumentView
        weak var textView: NoteTextView?
        /// Kendi yazdığımız değişikliğin geri dönüp belgeyi yeniden
        /// çizmesini engelliyor.
        var isApplyingEdit = false
        private var renderedSignature: [String] = []
        /// Yalnızca blokların *yapısı* — kimlik, tür, tamamlanma. Başlık
        /// metni dışarıda: kullanıcı yazarken belgeyi yeniden kurmamanın
        /// ölçüsü bu (bkz. `renderIfChanged`).
        private var renderedStructure: [String] = []

        /// Geri alma sonrası bir sonraki çizim zorunlu.
        private var forceNextRender = false
        /* `deinit` ana aktörün dışında çalışıyor ve yalnızca bu diziyi
           okuyor; dizi de yalnızca `init` içinde yazılıyor. */
        nonisolated(unsafe) private var undoObservers: [NSObjectProtocol] = []

        init(_ parent: NoteDocumentView) {
            self.parent = parent
            super.init()

            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                let token = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.forceNextRender = true }
                }
                undoObservers.append(token)
            }
        }

        deinit {
            for token in undoObservers { NotificationCenter.default.removeObserver(token) }
        }

        /// Metin görünümü şu an yazılan yer mi.
        private var isEditing: Bool {
            guard let textView else { return false }
            return textView.window?.firstResponder === textView
        }

        /// Görev listesi gerçekten değiştiyse yeniden çiziyor.
        ///
        /// Kullanıcı yazarken yalnızca başlıklar değişmişse belge
        /// olduğu gibi bırakılıyor: yazılan metin zaten ekranda ve her
        /// yeniden kurulum imleci yerinden oynatıyor. Blok yapısı
        /// değiştiğinde (satır eklendi/silindi, tür ya da tamamlanma
        /// değişti) çizim şart — Enter'dan sonra onay kutusu böyle
        /// geliyor.
        func renderIfChanged(tasks: [Task], isDark: Bool, fontScale: Double) {
            let signature = Self.signature(of: tasks, isDark: isDark, fontScale: fontScale)

            /* Geri alma/yineleme modelden geldi: belgedeki metin artık
               modelinkiyle uyuşmuyor. Yazarken yeniden çizimi atlayan
               kural burada geçerli değil — atlanırsa ⌘Z hiçbir şey
               yapmamış gibi görünüyor. */
            let forced = forceNextRender
            forceNextRender = false

            guard forced || signature != renderedSignature else { return }

            let structure = Self.structure(of: tasks, isDark: isDark, fontScale: fontScale)
            if !forced, structure == renderedStructure, isEditing {
                renderedSignature = signature
                return
            }
            render(tasks: tasks, isDark: isDark, fontScale: fontScale)
        }

        func render(tasks: [Task], isDark: Bool, fontScale: Double) {
            guard let textView, let storage = textView.textStorage else { return }
            let selected = textView.selectedRange()
            // İmleç sayısal konumuyla değil, bloğunun kimliğiyle
            // korunuyor: işaret eklenip kalktıkça konumlar kayıyor ve
            // imleç komşu satıra düşüyordu (bkz. `CaretAnchor`).
            let anchor = NoteDocumentBuilder.caretAnchor(in: textView)
            // Belge baştan kurulurken kaydırma konumu korunmazsa uzun bir
            // notta her değişiklikte sayfa başa sıçrıyor.
            let visible = textView.enclosingScrollView?.contentView.bounds.origin
            let previousText = storage.string

            storage.beginEditing()
            storage.setAttributedString(
                NoteDocumentBuilder.document(for: tasks, isDark: isDark, fontScale: fontScale)
            )
            storage.endEditing()


            // İmleç belge kısaldıysa taşmasın.
            let limit = storage.length
            var location = min(selected.location, limit)
            var length = min(selected.length, limit - location)

            if let anchor, let restored = NoteDocumentBuilder.location(for: anchor, in: storage) {
                location = restored
                length = 0
            } else if length == 0 {
                // Çapanın bloğu silinmiş (ya da hiç yoktu): sayısal konum
                // korunuyor, ama satır başına eklenmiş olabilecek bir
                // işaretin soluna düşmesin diye işaretin sağına çekiliyor.
                location = NoteDocumentBuilder.caretFloor(in: storage, at: location)
            }

            textView.setSelectedRange(NSRange(location: location, length: length))

            // Yazım nitelikleri: kullanıcı tuşa bastığında metni bunlar
            // çiziyor, belgedeki mevcut nitelikler değil. Verilmezse yeni
            // yazılan karakterler sistem yazı tipine ve siyaha düşüyor;
            // koyu zeminde okunmuyorlardı.
            textView.typingAttributes = NoteDocumentBuilder.typingAttributes(
                isDark: isDark, fontScale: fontScale
            )

            if let visible, let clip = textView.enclosingScrollView?.contentView {
                clip.scroll(to: visible)
                clip.enclosingScrollView?.reflectScrolledClipView(clip)
            }

            /*
             * Belge baştan kuruldu ve görünüm elle kaydırıldı: ikisi de
             * AppKit'in kendi çizim döngüsünün dışında oldu. Görünümün
             * tazelenmesini ayrıca istemezsek, kısalan bir belgede eski
             * satırların pikselleri altta asılı kalıyor — notun dibinde
             * son satırın yarım bir kopyası görünüyordu.
             *
             * Düzen de zorlanıyor: ek (onay kutusu, ayırıcı) taşıyan
             * satırların yüksekliği yeniden ölçülmeden çizim istenirse
             * eski yükseklik kullanılıyor.
             */
            if let container = textView.textContainer, let layout = textView.layoutManager {
                layout.ensureLayout(for: container)
            }
            textView.needsDisplay = true

            renderedSignature = Self.signature(of: tasks, isDark: isDark, fontScale: fontScale)
            renderedStructure = Self.structure(of: tasks, isDark: isDark, fontScale: fontScale)
        }

        private static func signature(of tasks: [Task], isDark: Bool, fontScale: Double) -> [String] {
            ["dark:\(isDark)|scale:\(fontScale)"]
                + tasks.map { "\($0.id)|\($0.kindRaw)|\($0.isCompleted)|\($0.title)" }
        }

        private static func structure(of tasks: [Task], isDark: Bool, fontScale: Double) -> [String] {
            ["dark:\(isDark)|scale:\(fontScale)"]
                + tasks.map { "\($0.id)|\($0.kindRaw)|\($0.isCompleted)" }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isApplyingEdit = true
            let paragraphs = NoteDocumentBuilder.paragraphs(in: textView)
            parent.onEdit(paragraphs)
            // Eşitleme bittikten sonra yeniden çizime izin veriliyor; imza
            // da güncellendiği için gereksiz bir yeniden çizim olmuyor.
            _Concurrency.Task { @MainActor [weak self] in
                self?.isApplyingEdit = false
            }
        }

        /// İmleç satır başındaki işaretin soluna geçemiyor (bkz.
        /// `NoteDocumentBuilder.clampedCaret`). Aralık seçimleri serbest:
        /// bir satırı baştan sona seçip silmek satırı tümüyle siliyor.
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldRange: NSRange,
            toCharacterRange newRange: NSRange
        ) -> NSRange {
            guard newRange.length == 0, let storage = textView.textStorage else { return newRange }
            let location = NoteDocumentBuilder.clampedCaret(
                in: storage, from: oldRange.location, to: newRange.location
            )
            return NSRange(location: location, length: 0)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onSelectionChange(
                NoteSelection(
                    blockIDs: NoteDocumentBuilder.selectedBlockIDs(in: textView),
                    isRange: textView.selectedRange().length > 0,
                    coversWholeBlocks: NoteDocumentBuilder.selectionCoversWholeBlocks(in: textView)
                )
            )
        }
    }
}

/// Onay kutularına tıklamayı yakalayan metin görünümü.
final class NoteTextView: NSTextView {
    /// Yapıştırma her zaman düz metin.
    ///
    /// `isRichText = false` yalnızca kullanıcının biçim uygulamasını
    /// engelliyor; panoda RTF varsa AppKit onu yine de nitelikleriyle
    /// alabiliyor ve yapıştırılan satır kaynağının yazı tipiyle,
    /// puntosuyla geliyordu. Düz metin olarak alınınca satır belgenin
    /// kendi niteliklerini kullanıyor.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    /// ⌥⌘⇧V ("biçimsiz yapıştır") de aynı yola çıkıyor: iki ayrı davranış
    /// olmasının bir anlamı yok, belge zaten tek bir yazı tipi kullanıyor.
    override func pasteAsRichText(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    var onToggle: ((UUID) -> Void)?
    var onClearMarker: ((UUID) -> Void)?
    var onRemoveMarker: ((UUID) -> Void)?

    /// Satır başındaki işareti Backspace ile kaldırma.
    ///
    /// Önceden işaret metnin parçası olduğu için (ek + boşluk) kullanıcı
    /// satırı boşalttıktan sonra iki kez daha silmek zorunda kalıyordu;
    /// üstelik arada blok hâlâ görev olduğu için kutu yeniden çiziliyor,
    /// silinmemiş gibi görünüyordu. Şimdi tek Backspace bloğu boş satıra
    /// çeviriyor; ikinci Backspace de satırı bir öncekine bağlıyor.
    override func deleteBackward(_ sender: Any?) {
        if let block = NoteDocumentBuilder.caretBlock(in: self), block.hasMarker {
            // Boş satır: blok tamamen boş satıra dönüyor.
            if block.isEmpty {
                onClearMarker?(block.id)
                return
            }
            // Metnin tam başındayız: önce işaret kalkıyor, metin duruyor.
            // Liste editörlerinin ortak davranışı — madde işaretinden
            // kurtulmanın yolu menüye gitmek olmamalı.
            if block.atTextStart {
                onRemoveMarker?(block.id)
                return
            }
        }
        super.deleteBackward(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = checkboxID(at: point) {
            onToggle?(id)
            return
        }
        super.mouseDown(with: event)
    }

    /// Tıklanan yerde bir onay kutusu eki var mı.
    private func checkboxID(at point: NSPoint) -> UUID? {
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return nil }

        let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: local, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index < storage.length else { return nil }

        guard storage.attribute(.attachment, at: index, effectiveRange: nil) is NoteCheckboxAttachment else {
            return nil
        }
        return storage.attribute(.glassDoBlockID, at: index, effectiveRange: nil) as? UUID
    }
}

/// Satır başındaki onay kutusu. Metnin içinde tek bir karakter olarak
/// duruyor; böylece seçim onu da kapsıyor ve satır düzeni kaymıyor.
/// Nottaki ayırıcı satırı çizer.
///
/// Eskiden bu bir tire dizisiydi (`"────────"`): yazı tipine göre uzunluğu
/// değişiyor, satırın ortasında asılı kalıyor ve seçilebilir bir metin
/// parçası olduğu için ayırıcıdan çok "yanlışlıkla yazılmış tireler" gibi
/// duruyordu. Gerçek bir çizgi olarak çizilince her puntoda aynı
/// kalınlıkta kalıyor.
///
/// Genişlik `attachmentBounds` içinde satırın kendisinden okunuyor, yani
/// çizgi kenardan kenara uzanıyor ve pencere yeniden boyutlanınca
/// kendiliğinden uyuyor — belgeyi yeniden kurmaya gerek yok.
final class NoteDividerAttachment: NSTextAttachment {
    private static let height: CGFloat = 9
    private static let thickness: CGFloat = 1

    init(isDark: Bool) {
        super.init(data: nil, ofType: nil)
        image = Self.draw(isDark: isDark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(
            x: 0,
            y: -2,
            width: max(lineFrag.width - position.x, 24),
            height: Self.height
        )
    }

    /// Yatayda esnetilecek, bu yüzden dar çiziliyor; çizginin kalınlığı
    /// yükseklikten geldiği için esneme onu bozmuyor.
    private static func draw(isDark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 64, height: height), flipped: false) { rect in
            let line = NSRect(
                x: 0,
                y: (rect.height - thickness) / 2,
                width: rect.width,
                height: thickness
            )
            (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.18).setFill()
            NSBezierPath(rect: line).fill()
            return true
        }
    }
}

final class NoteCheckboxAttachment: NSTextAttachment {
    let isChecked: Bool

    private static let side: CGFloat = 13

    init(isChecked: Bool, isDark: Bool, font: NSFont) {
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
        image = Self.draw(isChecked: isChecked, isDark: isDark)
        // Ek varsayılan olarak yazı çizgisinin (baseline) üstüne oturuyor,
        // bu yüzden kutu metne göre yukarıda duruyordu. Büyük harf
        // yüksekliğine göre ortalanınca yanındaki yazıyla aynı hizaya
        // geliyor.
        bounds = CGRect(
            x: 0,
            y: (font.capHeight - Self.side) / 2,
            width: Self.side,
            height: Self.side
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    private static func draw(isChecked: Bool, isDark: Bool) -> NSImage {
        let side = Self.side
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)
            // Daire yerine yuvarlatılmış kare: uygulamanın geri kalanındaki
            // onay kutularıyla ve macOS'un kendi diliyle aynı şekil.
            let path = NSBezierPath(roundedRect: inset, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.2

            if isChecked {
                NSColor.systemGreen.setFill()
                path.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: inset.minX + inset.width * 0.26, y: inset.midY))
                tick.line(to: NSPoint(x: inset.minX + inset.width * 0.45, y: inset.minY + inset.height * 0.3))
                tick.line(to: NSPoint(x: inset.minX + inset.width * 0.76, y: inset.minY + inset.height * 0.68))
                tick.lineWidth = 1.6
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.42).setStroke()
                path.stroke()
            }
            return true
        }
        return image
    }
}
