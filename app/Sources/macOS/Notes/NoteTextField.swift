import SwiftUI
import AppKit

/// SwiftUI'ın `TextField` + `.onKeyPress` ikilisi, alan boşken Backspace'i
/// güvenilir biçimde yakalayamıyor — düzenlenebilir metin alanları
/// tuşları kendi iç editörlerinde tükettiği için `onKeyPress` hiç
/// tetiklenmiyordu. Bu, `NSTextField`'ın delegesindeki
/// `doCommandBy:` üzerinden Backspace ve Enter'ı doğrudan AppKit
/// seviyesinde yakalayan ince bir köprü.
/// ⌘ ya da ⇧ basılıyken tıklamayı kendine almayan metin alanı.
///
/// Satır seçimi bunun üzerine kurulu: alan satırın neredeyse tamamını
/// kapladığı için düz tıklama ona gidiyor (yazmaya devam), değiştirici
/// tuşlu tıklama ise arkadaki satıra geçiyor ve seçim oluyor. `hitTest`
/// dışında bir yol yok — `NSTextField` tıklamayı SwiftUI'a hiç
/// ulaştırmadan kendi düzenleyicisinde tüketiyor.
private final class SelectionPassthroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) || flags.contains(.shift) { return nil }
        return super.hitTest(point)
    }
}

struct NoteTextField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var strikethrough: Bool
    /// Bu satırın odakta olup olmadığı — dışarıdaki paylaşılan seçime bağlı.
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    /// Alan zaten boşken Backspace'e basılınca çağrılır.
    let onDeleteEmpty: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = SelectionPassthroughTextField()
        // Zengin metin kapalı: panodan gelen yazı kaynağının yazı tipini ve
        // puntosunu taşımasın, satır belgenin yüzüyle devam etsin.
        field.allowsEditingTextAttributes = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.font = font
        let isEditing = nsView.currentEditor() != nil

        // Yazarken metni çizen şey alanın kendisi değil, pencerenin ortak
        // "field editor"ı. Onun yazı tipi ve yazım nitelikleri ayrı
        // tutuluyor; verilmezse sistem yazı tipine düşüyor ve düzenlenen
        // satır ötekilerden başka bir yüzle görünüyordu.
        if let editor = nsView.currentEditor() as? NSTextView {
            editor.font = font
            editor.typingAttributes[.font] = font
            editor.typingAttributes[.foregroundColor] = textColor
        }

        if !isEditing {
            if strikethrough {
                let attributed = NSMutableAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ])
                nsView.attributedStringValue = attributed
            } else {
                nsView.textColor = textColor
                if nsView.stringValue != text { nsView.stringValue = text }
            }
        }

        if isFocused {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
            }
        } else if nsView.currentEditor() != nil, nsView.window?.firstResponder === nsView.currentEditor() {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nil) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoteTextField
        init(_ parent: NoteTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }

        /// Enter ve Backspace'i alanın kendi iç editörü tüketmeden önce yakalar.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), parent.text.isEmpty {
                parent.onDeleteEmpty()
                return true
            }
            return false
        }
    }
}
