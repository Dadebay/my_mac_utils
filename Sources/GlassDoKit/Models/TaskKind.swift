import Foundation

/// Bir satırın türü. Notion'daki blok mantığının küçük, kasıtlı olarak
/// sınırlı bir alt kümesi: not tutmaya yetecek kadar çeşit, tam bir metin
/// editörüne dönüşmeyecek kadar az.
public enum TaskKind: Int, CaseIterable, Sendable, Identifiable {
    case todo = 0
    case heading = 1
    case text = 2
    case bullet = 3
    case numbered = 4
    case divider = 5

    public var id: Int { rawValue }

    public var symbolName: String {
        switch self {
        case .todo: "checkmark.square"
        case .heading: "textformat.size.larger"
        case .text: "text.alignleft"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .divider: "minus"
        }
    }

    public var displayName: String {
        switch self {
        case .todo: L10n.s("Görev", "To-do", "Задача")
        case .heading: L10n.s("Başlık", "Heading", "Заголовок")
        case .text: L10n.s("Metin", "Text", "Текст")
        case .bullet: L10n.s("Madde", "Bulleted", "Маркированный список")
        case .numbered: L10n.s("Numaralı", "Numbered", "Нумерованный список")
        case .divider: L10n.s("Ayırıcı", "Divider", "Разделитель")
        }
    }

    /// Yalnızca görevler işaretlenebilir ve ilerleme yüzdesine sayılır —
    /// başlıklar, metinler ve ayırıcılar "yapılacak iş" değil.
    public var isCompletable: Bool { self == .todo }

    /// Ayırıcının yazılabilir metni yok.
    public var hasText: Bool { self != .divider }
}
