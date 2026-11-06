import GlassDoKit
import SwiftUI

/// Kenar panelindeki klavye temizleme aracı. Bkz. `KeyboardCleanController`.
struct PanelKeyboardCleanView: View {
    private let controller = KeyboardCleanController.shared
    private let backlight = KeyboardBacklight.shared

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.keyboardCleanTitle)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.4)

            Text(controller.isActive ? L10n.keyboardCleanActiveHint : L10n.keyboardCleanHint)
                .font(.app(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.keyboardCleanBlockTrackpad, isOn: $controller.blockTrackpad)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(controller.isActive)

            Picker(L10n.s("Süre", "Duration", "Длительность"), selection: $controller.duration) {
                ForEach(KeyboardCleanController.durationOptions, id: \.self) { seconds in
                    Text(seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .disabled(controller.isActive)

            if controller.isActive {
                Text(L10n.s("Hemen bitirmek için Esc tuşuna 3 kez hızlıca bas.",
                            "Press Esc 3 times quickly to finish now.",
                            "Чтобы завершить сейчас, быстро нажмите Esc 3 раза."))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                controller.toggle()
            } label: {
                Label(
                    controller.isActive
                        ? "\(L10n.keyboardCleanStop) (\(controller.secondsRemaining)s)"
                        : L10n.keyboardCleanStart,
                    systemImage: controller.isActive ? "lock.open" : "keyboard"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if backlight.isAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.keyboardBacklight)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .kerning(0.4)
                    HStack(spacing: 10) {
                        Button { backlight.step(-0.0625) } label: { Image(systemName: "light.min") }
                            .buttonStyle(.borderless)
                        Slider(
                            value: Binding(get: { backlight.level }, set: { backlight.set($0) }),
                            in: 0...1
                        )
                        .controlSize(.small)
                        Button { backlight.step(0.0625) } label: { Image(systemName: "light.max") }
                            .buttonStyle(.borderless)
                    }
                }
                .onAppear { backlight.refresh() }
            }

            if controller.needsPermission {
                Text(L10n.keyboardCleanPermission)
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L10n.keyboardCleanEscapeNote)
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
