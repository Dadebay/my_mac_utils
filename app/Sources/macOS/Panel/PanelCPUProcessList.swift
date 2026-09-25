import SwiftUI
import AppKit
import GlassDoKit

/// İşlemci panelindeki "en çok kullananlar" listesi.
///
/// Çekirdek grafiği yükün *ne kadar* olduğunu gösteriyordu ama *kimin*
/// olduğunu değil — kullanıcı hangi uygulamayı kapatması gerektiğini
/// bilmek için Etkinlik İzleyicisi'ni açmak zorundaydı. Bellek panelindeki
/// listeyle aynı davranış: satırın sağında kapatma, önce onay soruluyor.
struct PanelCPUProcessList: View {
    let reduceMotion: Bool

    @State private var monitor = CPUProcessMonitor.shared
    @State private var pendingQuit: CPUProcessUsage?
    @State private var message: String?

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L10n.s("En çok işlemci kullananlar", "Top CPU processes", "Больше всего нагружают ЦП"))
                    .font(.app(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !monitor.processes.isEmpty {
                    Text("\(monitor.processes.count)")
                        .font(.app(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            if let message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SystemPalette.warning)
                    Text(message)
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { self.message = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SystemPalette.warning.opacity(0.12))
                )
            }

            if !monitor.hasSampled {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L10n.s("Ölçülüyor…", "Measuring…", "Измерение…"))
                        .font(.app(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            } else if monitor.processes.isEmpty {
                Text(L10n.s("İşlemciyi yoran bir süreç yok.", "Nothing is keeping the CPU busy.", "Ничто не нагружает ЦП."))
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 3) {
                    ForEach(monitor.processes) { usage in
                        CPUProcessRow(
                            usage: usage,
                            largest: monitor.processes.first?.percent ?? 1,
                            reduceMotion: reduceMotion,
                            onQuitRequested: { pendingQuit = usage }
                        )
                    }
                }
            }
        }
        .animation(motion, value: monitor.processes)
        .animation(motion, value: message)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .alert(
            pendingQuit.map { L10n.quitAppConfirmTitle($0.name) } ?? "",
            isPresented: Binding(
                get: { pendingQuit != nil },
                set: { if !$0 { pendingQuit = nil } }
            ),
            presenting: pendingQuit
        ) { usage in
            Button(L10n.cancel, role: .cancel) { pendingQuit = nil }
            Button(L10n.quit, role: .destructive) {
                pendingQuit = nil
                quit(usage)
            }
        }
    }

    /// Dock uygulaması nazik yoldan (kaydedilmemiş işi varsa kendisi
    /// soruyor); geri kalanlar `SIGTERM` ile — bellek listesiyle aynı kural.
    private func quit(_ usage: CPUProcessUsage) {
        message = nil
        let succeeded: Bool
        if let app = NSRunningApplication(processIdentifier: usage.id), app.activationPolicy == .regular {
            succeeded = app.terminate()
        } else {
            succeeded = kill(usage.id, SIGTERM) == 0
        }
        if succeeded {
            monitor.remove(usage.id)
        } else {
            message = L10n.processQuitDenied(usage.name)
        }
    }
}

private struct CPUProcessRow: View {
    let usage: CPUProcessUsage
    let largest: Double
    let reduceMotion: Bool
    let onQuitRequested: () -> Void

    @State private var isHovering = false
    @State private var isQuitHovering = false

    private var application: NSRunningApplication? {
        NSRunningApplication(processIdentifier: usage.id)
    }

    /// Korunan süreçler (WindowServer, Dock, Finder…) ve başka kullanıcıya
    /// ait olanlar listede görünür ama kapatılamaz.
    private var canQuit: Bool {
        ProcessSafety.canTerminate(pid: usage.id, name: processName)
    }

    /// Korunan isimler `proc_name` üzerinden tanımlı; görünen ad uygulamanın
    /// yerelleştirilmiş adı olabiliyor.
    private var processName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(usage.id, &buffer, UInt32(buffer.count)) > 0 else { return usage.name }
        return String(cString: buffer)
    }

    var body: some View {
        HStack(spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(usage.name)
                    .font(.app(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(geo.size.width * min(usage.percent / max(largest, 1), 1), 3))
                }
                .frame(height: 2.5)
            }

            Spacer(minLength: 4)

            Text(String(format: "%.1f%%", usage.percent))
                .font(.app(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)

            Button(action: onQuitRequested) {
                Image(systemName: "xmark.circle")
                    .font(.app(size: 12, weight: .medium))
                    .foregroundStyle(
                        canQuit
                            ? (isQuitHovering ? Color.red : Color.secondary)
                            : Color.secondary.opacity(0.35)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canQuit)
            .help(L10n.quitAppHelp(usage.name))
            .accessibilityLabel(L10n.quitAppHelp(usage.name))
            .onHover { isQuitHovering = $0 && canQuit }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.075 : 0.03))
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(usage.name), \(String(format: "%.1f", usage.percent))% CPU")
    }

    /// Bir çekirdeğin yarısını geçen süreç uyarı renginde.
    private var tint: Color {
        usage.percent >= 50 ? SystemPalette.warning : SystemPalette.accent
    }

    @ViewBuilder
    private var icon: some View {
        if let image = application?.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
