import SwiftUI
import GlassDoKit

struct SystemMonitorView: View {
    private let controller = SystemMonitorController.shared
    @State private var pendingQuit: RunningAppUsage?
    /// Göstergede seçili dilim: aşağıdaki liste bunu gösteriyor.
    /// Varsayılan "Uygulamalar" — sayfanın asıl sorusu genelde "hangi
    /// uygulama yiyor".
    @State private var selection: MemorySegment.Kind = .apps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static func text(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    /// Çubuk ve gösterge tek bir kaynaktan besleniyor — renk ile değerin
    /// birbirinden ayrı düşmesi mümkün olmasın.
    private var segments: [MemorySegment] {
        let memory = controller.memory
        return [
            MemorySegment(id: .apps, label: L10n.memoryAppsLabel,
                          bytes: controller.appsTotal, color: MemoryPalette.apps),
            MemorySegment(id: .system, label: L10n.memorySystemLabel,
                          bytes: controller.systemTotal, color: MemoryPalette.system),
            MemorySegment(id: .cached, label: L10n.memoryCachedLabel,
                          bytes: memory.cached, color: MemoryPalette.cached),
            MemorySegment(id: .free, label: L10n.memoryFreeLabel,
                          bytes: memory.free, color: MemoryPalette.free),
        ]
    }

    private var barAnimation: Animation? {
        // HIG varsayılanı: kritik sönümlü, taşmasız — 2 saniyede bir gelen
        // veri güncellemesi dikkat çekmeden yerine otursun.
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider().opacity(0.5)
            listSection
        }
        .navigationTitle(L10n.systemMonitorTitle)
        .navigationSubtitle(L10n.systemMonitorSubtitle(controller.apps.count))
        .task { controller.start() }
        .onDisappear { controller.stop() }
        .confirmationDialog(
            pendingQuit.map { L10n.quitAppConfirmTitle($0.name) } ?? "",
            isPresented: Binding(
                get: { pendingQuit != nil },
                set: { isPresented in if !isPresented { pendingQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingQuit {
                Button(L10n.quit, role: .destructive) {
                    controller.quit(pendingQuit)
                    self.pendingQuit = nil
                }
                Button(L10n.cancel, role: .cancel) {
                    self.pendingQuit = nil
                }
            }
        }
    }

    // MARK: - Özet

    /// Ekranın tepesindeki tek baskın bilgi: makinede ne kadar bellek
    /// kullanıldığı. Altındaki çubuk bunun neye gittiğini gösteriyor.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            headline
            breakdownBar
            legend
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var headline: some View {
        let memory = controller.memory
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.memoryUsedLabel)
                    .font(.app(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(Self.text(memory.used))
                        // Büyük metin: negatif tracking ile harfler
                        // dağılmadan tek bir sayı gibi okunur.
                        .font(.app(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.6)
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("/ \(Self.text(memory.total))")
                        .font(.app(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(percentText)
                .font(.app(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .animation(barAnimation, value: controller.memory)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.memoryBreakdownDescription(Self.text(memory.used), Self.text(memory.total))
        )
    }

    private var percentText: String {
        let percent = Int((controller.memory.usedFraction * 100).rounded())
        return "%\(percent)"
    }

    /// Segmentler soldan sağa yığılıyor; kalan boşluk doğrudan "boş"
    /// rayının kendisi — yuvarlama farkı diye çubuğun ucunda hiç boşluk
    /// kalmasın diye.
    private var breakdownBar: some View {
        let total = max(Double(controller.memory.total), 1)
        let used = segments.filter { $0.id != .free }

        return GeometryReader { geo in
            let spacing: CGFloat = 2
            let available = max(geo.size.width - spacing * CGFloat(used.count), 0)

            ZStack(alignment: .leading) {
                Capsule().fill(MemoryPalette.free)

                HStack(spacing: spacing) {
                    ForEach(used) { segment in
                        let fraction = Double(segment.bytes) / total
                        Capsule()
                            .fill(segment.color)
                            // Seçili dilim tam renkte, diğerleri geri
                            // çekiliyor: göstergeye basmak yalnızca listeyi
                            // değil çubuğu da değiştiriyor, yani hangi
                            // bölüme baktığınız çubukta da görünüyor.
                            .opacity(segment.id == selection ? 1 : 0.34)
                            .frame(width: fraction > 0.002 ? max(available * fraction, 4) : 0)
                    }
                }
            }
        }
        .frame(height: 10)
        .animation(barAnimation, value: controller.memory)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(segments) { segment in
                legendItem(segment)
            }
        }
        .animation(barAnimation, value: controller.memory)
    }

    /// Yalnızca süreç listesi olan iki dilim seçilebiliyor: önbellek ve boş
    /// bellek bir sürecin değil, çekirdeğin muhasebesi — onlara basınca
    /// gösterilecek bir liste yok.
    private func isSelectable(_ kind: MemorySegment.Kind) -> Bool {
        kind == .apps || kind == .system
    }

    @ViewBuilder
    private func legendItem(_ segment: MemorySegment) -> some View {
        let isSelected = segment.id == selection
        let selectable = isSelectable(segment.id)

        Button {
            guard selectable else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                selection = segment.id
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(segment.color)
                    .frame(width: 8, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.label)
                        .font(.app(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(Self.text(segment.bytes))
                        .font(.app(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? segment.color.opacity(0.14) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? segment.color.opacity(0.45) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .help(selectable ? segment.label : "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Uygulama listesi

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selection == .system ? L10n.systemProcessesLabel : L10n.runningAppsLabel)
                    .font(.app(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if visibleProcesses.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    /// Seçili dilimin süreçleri, en çok yiyen on tanesi. Daha uzun bir
    /// liste bu sayfada karar vermeye yardım etmiyor: kullanıcı en ağır
    /// birkaçına bakıp kapatıyor.
    private var visibleProcesses: [RunningAppUsage] {
        let source = selection == .system ? controller.systemProcesses : controller.apps
        return Array(source.prefix(10))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(visibleProcesses) { app in
                    AppUsageRow(
                        app: app,
                        fraction: fraction(of: app),
                        valueText: Self.text(app.memoryBytes),
                        onQuit: { pendingQuit = app }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    /// Satırdaki oran çubuğu, **gösterilen** listenin en büyük değerine
    /// göre ölçekleniyor — toplam RAM'e göre olsaydı bütün satırlar görünmez
    /// incelikte kalırdı, uygulama listesinin tepesine göre olsaydı sistem
    /// süreçleri hep silik görünürdü.
    private func fraction(of app: RunningAppUsage) -> Double {
        let largest = visibleProcesses.first?.memoryBytes ?? 0
        guard largest > 0 else { return 0 }
        return Double(app.memoryBytes) / Double(largest)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "memorychip")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.systemMonitorEmpty)
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bellek dağılım çubuğunun ve göstergesinin tek bir satırı.
private struct MemorySegment: Identifiable {
    enum Kind { case apps, system, cached, free }

    let id: Kind
    let label: String
    let bytes: UInt64
    let color: Color
}

/// Listedeki tek uygulama. Arkasındaki dolgu, uygulamanın listedeki en
/// büyük tüketiciye oranını gösteriyor — göz, sayıları okumadan da kimin
/// ağır olduğunu görebilsin diye.
private struct AppUsageRow: View {
    let app: RunningAppUsage
    let fraction: Double
    let valueText: String
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            icon

            Text(app.name)
                .font(.app(size: 13))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(valueText)
                .font(.app(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())

            quitButton
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 26, height: 26)
        }
    }

    /// Yıkıcı eylem: her zaman görünür (yalnızca hover'da beliren bir düğme
    /// klavye ve dokunmatik için keşfedilemez olurdu) ama sessiz — dikkat
    /// çekmesi ancak üzerine gelindiğinde, kırmızıya dönerek.
    private var quitButton: some View {
        Button(action: onQuit) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(isHovering ? Color.red : Color.secondary.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(L10n.quitAppHelp(app.name))
        .accessibilityLabel(L10n.quitAppHelp(app.name))
    }

    private var rowBackground: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0.035))

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                MemoryPalette.apps.opacity(0.28),
                                MemoryPalette.apps.opacity(0.10),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * fraction, 0))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1.0), value: fraction)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
