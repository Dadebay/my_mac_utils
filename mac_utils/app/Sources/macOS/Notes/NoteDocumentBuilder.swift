import AppKit
import GlassDoKit

/// Görev listesi ile metin belgesi arasındaki çeviri.
///
/// Tek yönlü değil: görevlerden belge kuruluyor (`document`), kullanıcı
/// yazdıkça belgeden paragraflar okunuyor (`paragraphs`). Her iki yön de
/// burada duruyor ki biçim değişince ikisi birlikte değişsin — ayrı
/// yerlerde olsalardı okuma, yazmanın gerisinde kalırdı.
enum NoteDocumentBuilder {

    /// Satır başındaki işaretler metnin parçası değil: onlar olsaydı
    /// kullanıcı "•" karakterini silebilir, kopyalayınca da metne
    /// karışırlardı. Onay kutusu bir ek (attachment), madde/numara ise
    /// paragraf girintisiyle çizilen bir önek.
    static func document(for tasks: [Task], isDark: Bool, fontScale: Double) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, task) in tasks.enumerated() {
            output.append(paragraph(
                for: task,
                ordinal: ordinal(at: index, in: tasks),
                isDark: isDark,
                fontScale: fontScale
            ))
            if index < tasks.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: [.glassDoBlockID: task.id]))
            }
        }

        return output
    }

    private static func paragraph(
        for task: Task,
        ordinal: Int,
        isDark: Bool,
        fontScale: Double
    ) -> NSAttributedString {
        let kind = task.kind
        let line = NSMutableAttributedString()

        if kind == .todo {
            let attachment = NoteCheckboxAttachment(
                isChecked: task.isCompleted,
                isDark: isDark,
                font: font(for: kind, scale: fontScale)
            )
            line.append(NSAttributedString(attachment: attachment))
            line.append(NSAttributedString(string: " "))
        } else if kind == .bullet {
            line.append(NSAttributedString(string: "•  "))
        } else if kind == .numbered {
            line.append(NSAttributedString(string: "\(ordinal).  "))
        }

        // İşaret olarak eklenen her karakter işaretleniyor; geri okurken
        // tam olarak bunlar atılıyor (bkz. `NSAttributedString.Key.glassDoMarker`).
        if line.length > 0 {
            line.addAttribute(.glassDoMarker, value: true, range: NSRange(location: 0, length: line.length))
        }

        line.append(NSAttributedString(string: displayText(for: task)))

        let full = NSRange(location: 0, length: line.length)
        line.addAttributes(attributes(for: task, isDark: isDark, fontScale: fontScale), range: full)
        line.addAttribute(.glassDoBlockID, value: task.id, range: full)
        return line
    }

    /// Ayırıcı ve boşluk bloklarının metni yok; belgede yine de bir
    /// paragraf kaplamaları gerekiyor, yoksa iki satır birleşirdi.
    private static func displayText(for task: Task) -> String {
        switch task.kind {
        case .divider: "────────"
        case .spacer: ""
        default: task.title
        }
    }

    static func font(for kind: TaskKind, scale: Double) -> NSFont {
        let size: CGFloat = switch kind {
        case .heading: 14
        case .text: 12
        default: 12.5
        }
        let scaled = size * CGFloat(NoteAppearance.clampedFontScale(scale))
        return kind == .heading
            ? AppFont.nsFont(size: scaled, weight: .semibold)
            : AppFont.nsFont(size: scaled)
    }

    private static func attributes(
        for task: Task,
        isDark: Bool,
        fontScale: Double
    ) -> [NSAttributedString.Key: Any] {
        let kind = task.kind

        let font = Self.font(for: kind, scale: fontScale)

        let base = isDark ? NSColor.white : NSColor.black
        let color: NSColor = if task.isCompleted {
            base.withAlphaComponent(0.45)
        } else if kind == .text || kind == .divider {
            base.withAlphaComponent(0.6)
        } else {
            base.withAlphaComponent(0.9)
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3 * CGFloat(NoteAppearance.clampedFontScale(fontScale))
        style.paragraphSpacing = (kind == .heading ? 6 : 4)
            * CGFloat(NoteAppearance.clampedFontScale(fontScale))
        style.paragraphSpacingBefore = kind == .heading ? 8 : 0
        // Sarmalanan satır, işaretin altına değil metnin hizasına dönüyor.
        style.headIndent = kind == .todo || kind == .bullet || kind == .numbered
            ? 18 * CGFloat(NoteAppearance.clampedFontScale(fontScale))
            : 0

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if task.isCompleted {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = base.withAlphaComponent(0.4)
        }
        return attributes
    }

    /// Numaralı blokların sıra numarası — yalnızca kesintisiz numaralı
    /// dizinin içinde sayılır, araya başka bir blok girince baştan başlar.
    private static func ordinal(at index: Int, in list: [Task]) -> Int {
        var number = 1
        var cursor = index - 1
        while cursor >= 0, list[cursor].kind == .numbered {
            number += 1
            cursor -= 1
        }
        return number
    }

    // MARK: - Belgeden okuma

    /// Belgedeki paragrafları, taşıdıkları görev kimlikleriyle birlikte
    /// döndürür. Metin, satır başındaki işaretlerden arındırılıyor —
    /// onlar görünüm, kullanıcının yazdığı metin değil.
    @MainActor
    static func paragraphs(in textView: NSTextView) -> [NoteParagraph] {
        guard let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        var result: [NoteParagraph] = []

        var location = 0
        while location <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            // Paragraf ayıracı metne dahil değil.
            var contentRange = lineRange
            if contentRange.length > 0,
               text.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1)) == "\n" {
                contentRange.length -= 1
            }

            let idSource = contentRange.length > 0 ? contentRange.location : lineRange.location
            let id = idSource < storage.length
                ? storage.attribute(.glassDoBlockID, at: idSource, effectiveRange: nil) as? UUID
                : nil

            result.append(NoteParagraph(id: id, text: strippedText(storage, in: contentRange)))

            if NSMaxRange(lineRange) <= location { break }
            location = NSMaxRange(lineRange)
            if location == text.length { break }
        }

        return result
    }

    /// Bizim çizdiğimiz işaret karakterlerini atarak paragrafın saf
    /// metnini verir.
    ///
    /// Ayıklama tamamen `glassDoMarker` özniteliğine dayanıyor: kullanıcının
    /// yazdığı metin, işarete ne kadar benzerse benzesin, hiçbir zaman
    /// kesilmiyor.
    private static func strippedText(_ storage: NSTextStorage, in range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        let attributed = storage.attributedSubstring(from: range)
        let result = NSMutableAttributedString(attributedString: attributed)

        // Sondan başa siliniyor ki aralıklar kaymasın.
        var markerRanges: [NSRange] = []
        result.enumerateAttribute(
            .glassDoMarker,
            in: NSRange(location: 0, length: result.length)
        ) { value, subrange, _ in
            if value != nil { markerRanges.append(subrange) }
        }
        for subrange in markerRanges.reversed() {
            result.deleteCharacters(in: subrange)
        }

        // Öznitelik taşımayan, eski belgelerden kalmış bir ek olursa
        // yine de metne karışmasın.
        return result.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// İmlecin bulunduğu blok. Backspace davranışı buna bakıyor:
    /// kimliği, metninin boş olup olmadığı, satır başında bir işaret
    /// (onay kutusu, madde, numara) taşıyıp taşımadığı ve imlecin metnin
    /// tam başında — yani işaretin hemen sağında — olup olmadığı.
    @MainActor
    static func caretBlock(
        in textView: NSTextView
    ) -> (id: UUID, isEmpty: Bool, hasMarker: Bool, atTextStart: Bool)? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        let text = storage.string as NSString
        let caret = min(textView.selectedRange().location, text.length)

        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        var contentRange = lineRange
        if contentRange.length > 0,
           text.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1)) == "\n" {
            contentRange.length -= 1
        }

        let idSource = contentRange.length > 0 ? contentRange.location : lineRange.location
        guard idSource < storage.length,
              let id = storage.attribute(.glassDoBlockID, at: idSource, effectiveRange: nil) as? UUID
        else { return nil }

        var markerRange = NSRange(location: contentRange.location, length: 0)
        let hasMarker = contentRange.length > 0
            && storage.attribute(
                .glassDoMarker,
                at: contentRange.location,
                longestEffectiveRange: &markerRange,
                in: contentRange
            ) != nil

        let stripped = contentRange.length > 0 ? strippedText(storage, in: contentRange) : ""
        let textStart = hasMarker ? NSMaxRange(markerRange) : contentRange.location
        return (id, stripped.isEmpty, hasMarker, caret == textStart)
    }

    /// Seçimin dokunduğu bütün blokların kimlikleri.
    @MainActor
    static func selectedBlockIDs(in textView: NSTextView) -> [UUID] {
        guard let storage = textView.textStorage else { return [] }
        let selection = textView.selectedRange()
        guard storage.length > 0 else { return [] }

        // Sıfır uzunlukta seçim de içinde bulunduğu bloğu bildiriyor:
        // imleç bir satırdayken blok türünü değiştirebilmek gerekiyor.
        let probe = selection.length > 0
            ? selection
            : NSRange(location: min(selection.location, storage.length - 1), length: 1)

        var ids: [UUID] = []
        storage.enumerateAttribute(.glassDoBlockID, in: probe) { value, _, _ in
            guard let id = value as? UUID, !ids.contains(id) else { return }
            ids.append(id)
        }
        return ids
    }
}
