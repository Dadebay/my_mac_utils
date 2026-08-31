import SwiftUI
import AppKit
import GlassDoKit

/// Tıklanınca bir sonraki tuşu dinler ve kod + okunabilir etiketini kaydeder.
/// Sadece Ayarlar penceresi önde ve odaklıyken çalışan yerel bir
/// `NSEvent` monitörü kullanır — global kısayolla (CGEventTap) hiçbir
/// ilgisi yok, bu yüzden ek izin gerektirmez.
struct ShortcutKeyRecorder: View {
    @Binding var keyCode: Int
    @Binding var keyLabel: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? L10n.s("Bir tuşa bas…", "Press a key…", "Нажмите клавишу…") : keyLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 84)
                .background {
                    Capsule().fill(Color.white.opacity(isRecording ? 0.16 : 0.09))
                }
                .overlay {
                    Capsule().strokeBorder(
                        isRecording ? Color.accentColor.opacity(0.7) : .white.opacity(0.12),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyCode = Int(event.keyCode)
            keyLabel = Self.label(for: event)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func label(for event: NSEvent) -> String {
        switch event.keyCode {
        case 48: return "Tab"
        case 49: return L10n.s("Boşluk", "Space", "Пробел")
        case 53: return "Esc"
        case 36: return "Return"
        case 51: return "Delete"
        case 123: return "◀"
        case 124: return "▶"
        case 125: return "▼"
        case 126: return "▲"
        default:
            let chars = event.charactersIgnoringModifiers?.uppercased()
            return (chars?.isEmpty == false) ? chars! : L10n.s("Tuş \(event.keyCode)", "Key \(event.keyCode)", "Клавиша \(event.keyCode)")
        }
    }
}
