import AppKit
import GlassDoKit
import SwiftUI

/// Kenar panelindeki ses karıştırıcı: sistem çıkışı, çıkış/giriş cihazı
/// seçimi ve o anda ses çalan uygulamaların kendi seviyeleri.
///
/// Uygulama başına seviye macOS'un normal ses sisteminde yok; Core Audio'nun
/// process tap API'siyle kuruluyor (bkz. `PerAppVolumeController`). Bu
/// yüzden bir uygulamanın kaydırıcısı ilk kez oynatıldığında o uygulamaya
/// özel bir ses yolu kuruluyor — kullanıcıya da `volumePerAppNote` ile
/// açıkça söyleniyor.
struct PanelVolumeMixerView: View {
    private let controller = AudioDeviceController.shared
    private let perApp = PerAppVolumeController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            systemOutput
            devicePickers
            playingApps
        }
        .task { controller.start() }
        .onDisappear { controller.stop() }
    }

    // MARK: - Sistem çıkışı

    private var systemOutput: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.volumeOutputLabel)

            if let volume = controller.outputVolume {
                HStack(spacing: 9) {
                    Button {
                        controller.setOutputMuted(!controller.isOutputMuted)
                    } label: {
                        Image(systemName: controller.isOutputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.app(size: 12))
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(controller.isOutputMuted ? L10n.volumeUnmute : L10n.volumeMute)

                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { controller.setOutputVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    .disabled(controller.isOutputMuted)

                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.app(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            } else {
                // Dijital çıkışlarda seviye cihazda ayarlanıyor; sahte bir
                // kaydırıcı göstermek yerine sebebi yazılıyor.
                Text(L10n.volumeNotAdjustable)
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cihazlar

    private var devicePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !controller.outputDevices.isEmpty {
                devicePicker(
                    label: L10n.volumeOutputLabel,
                    devices: controller.outputDevices,
                    select: { controller.selectOutputDevice($0) }
                )
            }

            if !controller.inputDevices.isEmpty {
                devicePicker(
                    label: L10n.volumeMicrophoneLabel,
                    devices: controller.inputDevices,
                    select: { controller.selectInputDevice($0) }
                )
            }
        }
    }

    private func devicePicker(
        label: String,
        devices: [AudioDevice],
        select: @escaping (AudioDevice) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.app(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Menu(devices.first(where: \.isDefault)?.name ?? "—") {
                ForEach(devices) { device in
                    Button {
                        select(device)
                    } label: {
                        if device.isDefault {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.app(size: 11.5, weight: .medium))
        }
    }

    // MARK: - Uygulamalar

    private var playingApps: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.volumePlayingNowLabel)

            if controller.playingApps.isEmpty {
                Text(L10n.volumeNothingPlaying)
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(controller.playingApps) { app in
                    appRow(app)
                }

                Text(L10n.volumePerAppNote)
                    .font(.app(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appRow(_ app: AudioPlayingApp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(app.name)
                    .font(.app(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if perApp.isControlled(app.id) {
                    Button {
                        perApp.resetVolume(for: app.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.app(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.volumeResetToSystem)
                }
            }

            Slider(
                value: Binding(
                    get: { perApp.volume(for: app.id) },
                    set: { perApp.setVolume($0, for: app) }
                ),
                in: 0...1
            )
            .controlSize(.small)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}
