import SwiftUI
import AppKit
import GlassDoKit

struct TaskRow: View {
    @Bindable var task: Task
    var isSelected: Bool = false
    @Binding var focusedID: UUID?
    let onToggle: () -> Void
    let onCommit: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void
    /// Metin alanındayken Enter'a basılınca çağrılır — altına yeni bir satır açar.
    let onCreateNext: () -> Void
    /// Satır boşken Backspace'e basılınca çağrılır — satırı siler, odağı
    /// bir öncekine taşır. Metin doluyken normal karakter silmeye karışmaz.
    let onDeleteEmpty: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sistemin liste seçim rengi tam satır sınırlarında, köşesiz çiziliyor
    /// ve `listRowBackground`'a verilen yuvarlak şekli yok sayıyor — bu
    /// yüzden seçimi tamamen burada, kendi yuvarlak zeminimizle gösteriyoruz.
    private var rowBackgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.13) }
        if isHovering { return Color.primary.opacity(0.045) }
        return .clear
    }

    private var rowBorderColor: Color {
        isSelected ? Color.accentColor.opacity(0.22) : .clear
    }


    var body: some View {
        HStack(spacing: 11) {
            // Başlık/metin/ayırıcı blokları işaretlenemez — onay kutusu
            // yalnızca gerçek görevlerde çizilir (bkz. TaskKind).
            if task.kind.isCompletable {
                checkbox
            }

            if task.kind.hasText {
                // SwiftUI'ın `TextField` + `.onKeyPress` ikilisi, alan
                // boşken Backspace'i güvenilir yakalayamıyordu (tuş,
                // `onKeyPress`'e hiç ulaşmadan alanın kendi iç editöründe
                // tükeniyordu). `NoteTextField`, Enter ve Backspace'i AppKit
                // delegesi üzerinden doğrudan yakalayan bir köprü.
                NoteTextField(
                    text: $task.title,
                    font: task.kind == .heading
                        ? .systemFont(ofSize: 14, weight: .semibold)
                        : .systemFont(ofSize: 13.5),
                    textColor: NSColor(task.isCompleted || task.kind == .text ? Color.secondary : Color.primary),
                    strikethrough: task.isCompleted,
                    isFocused: Binding(
                        get: { focusedID == task.id },
                        set: { newValue in
                            if newValue {
                                focusedID = task.id
                            } else if focusedID == task.id {
                                focusedID = nil
                            }
                        }
                    ),
                    onSubmit: {
                        onCommit()
                        onCreateNext()
                    },
                    onDeleteEmpty: onDeleteEmpty
                )
                .frame(height: 18)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
                    .padding(.vertical, 8)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    focusedID = task.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.055)))
                }
                .buttonStyle(.borderless)
                .help(L10n.editTask)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.82))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.red.opacity(0.075)))
                }
                .buttonStyle(.borderless)
                .help(L10n.delete)
            }
            .opacity(isHovering ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: 0.75)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0),
            value: isSelected
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture().onEnded(onSelect))
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            ZStack {
                if task.isCompleted {
                    Circle()
                        .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(
                            Color.secondary.opacity(isHovering ? 0.72 : 0.48),
                            lineWidth: 1.4
                        )
                }
            }
            .frame(width: 19, height: 19)
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1.0),
                value: task.isCompleted
            )
        }
        .buttonStyle(.pressScale(reduceMotion ? 1 : 0.9))
    }
}
