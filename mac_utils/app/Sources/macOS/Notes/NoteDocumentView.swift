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
    /// Seçimin kapsadığı görevler — biçim çubuğu bunu okuyor.
    var onSelectionChange: ([UUID], Bool) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView()
        textView.delegate = context.coordinator
        textView.onToggle = onToggle
        textView.onClearMarker = onClearMarker
        textView.onRemoveMarker = onRemoveMarker
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
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
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.render(tasks: tasks, isDark: isDark, fontScale: fontScale)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NoteTextView else { return }
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

        init(_ parent: NoteDocumentView) {
            self.parent = parent
        }

        /// Görev listesi gerçekten değiştiyse yeniden çiziyor.
        func renderIfChanged(tasks: [Task], isDark: Bool, fontScale: Double) {
            let signature = Self.signature(of: tasks, isDark: isDark, fontScale: fontScale)
            guard signature != renderedSignature else { return }
            render(tasks: tasks, isDark: isDark, fontScale: fontScale)
        }

        func render(tasks: [Task], isDark: Bool, fontScale: Double) {
            guard let textView, let storage = textView.textStorage else { return }
            let selected = textView.selectedRange()

            storage.beginEditing()
            storage.setAttributedString(
                NoteDocumentBuilder.document(for: tasks, isDark: isDark, fontScale: fontScale)
            )
            storage.endEditing()

            // İmleç belge kısaldıysa taşmasın.
            let limit = storage.length
            textView.setSelectedRange(
                NSRange(location: min(selected.location, limit), length: min(selected.length, limit - min(selected.location, limit)))
            )
            renderedSignature = Self.signature(of: tasks, isDark: isDark, fontScale: fontScale)
        }

        private static func signature(of tasks: [Task], isDark: Bool, fontScale: Double) -> [String] {
            ["dark:\(isDark)|scale:\(fontScale)"]
                + tasks.map { "\($0.id)|\($0.kindRaw)|\($0.isCompleted)|\($0.title)" }
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

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onSelectionChange(
                NoteDocumentBuilder.selectedBlockIDs(in: textView),
                textView.selectedRange().length > 0
            )
        }
    }
}

/// Onay kutularına tıklamayı yakalayan metin görünümü.
final class NoteTextView: NSTextView {
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
