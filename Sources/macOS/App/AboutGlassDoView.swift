import SwiftUI
import AppKit
import GlassDoKit

// MARK: - Merkezi bağlantı listesi

/// Menü çubuğundaki ve About penceresindeki dış bağlantıların tek kaynağı.
///
/// Şu an hiçbir gerçek URL tanımlı değil (website, destek, gizlilik…
/// henüz yayında değil) — o yüzden liste boş. Sahte/kırık bir bağlantı
/// göstermek yerine bölüm tamamen gizleniyor; gerçek bir adres hazır
/// olduğunda buraya tek satır eklemek yeterli.
struct AppLink: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let url: URL
}

enum AppLinks {
    static let all: [AppLink] = []
}

// MARK: - About penceresi

struct AboutGlassDoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var period: UsagePeriod = .last7Days
    @State private var periodSnapshot: UsageSnapshot = .empty
    @State private var allTimeSnapshot: UsageSnapshot = .empty
    @State private var isLoaded = false
    @State private var isResetting = false
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero

                if !AppLinks.all.isEmpty {
                    quickLinks
                }

                usageSection
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.windowBackground)
        .task {
            await reloadAll()
            isLoaded = true
        }
        .onChange(of: period) { _, newValue in
            _Concurrency.Task { await reloadPeriod(newValue) }
        }
        .confirmationDialog(
            L10n.s("Kullanım Verisini Sıfırla?", "Reset Usage Data?", "Сбросить данные использования?"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.s("Sıfırla", "Reset", "Сбросить"), role: .destructive) {
                _Concurrency.Task { await performReset() }
            }
            Button(L10n.s("İptal", "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.s(
                "Yalnızca kullanım sayaçları silinir. Görevleriniz, klasörleriniz ve uygulama ayarlarınız etkilenmez. Bu işlem geri alınamaz.",
                "Only usage counters are deleted. Your tasks, folders, and app settings are not affected. This cannot be undone.",
                "Удаляются только счётчики использования. Задачи, папки и настройки приложения не затрагиваются. Это действие необратимо."
            ))
        }
    }

    private func reloadAll() async {
        async let period = UsageStore.shared.snapshot(for: period)
        async let allTime = UsageStore.shared.snapshot(for: .allTime)
        let (p, a) = await (period, allTime)
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)) {
            periodSnapshot = p
            allTimeSnapshot = a
        }
    }

    private func reloadPeriod(_ newPeriod: UsagePeriod) async {
        let snapshot = await UsageStore.shared.snapshot(for: newPeriod)
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)) {
            periodSnapshot = snapshot
        }
    }

    private func performReset() async {
        await UsageStore.shared.reset()
        await reloadAll()
    }

    // MARK: - Kimlik

    private var hero: some View {
        VStack(spacing: 14) {
            AppBrandMark(size: 116)

            VStack(spacing: 5) {
                Text("GlassDo")
                    .font(.system(size: 24, weight: .semibold))
                    .kerning(-0.3)

                Text(L10n.s(
                    "Mac'inizin kenarında görevler ve sistem bilgisi",
                    "Tasks and system insights at the edge of your Mac",
                    "Задачи и системная информация на краю экрана"
                ))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(versionString)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            Text(copyrightString)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return L10n.s(
            "Sürüm \(short) (\(build))",
            "Version \(short) (\(build))",
            "Версия \(short) (\(build))"
        )
    }

    private var copyrightString: String {
        let year = Calendar.autoupdatingCurrent.component(.year, from: Date())
        return "© \(String(year)) GlassDo"
    }

    // MARK: - Bağlantılar

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(L10n.s("Bağlantılar", "Links", "Ссылки"))

            VStack(spacing: 0) {
                ForEach(Array(AppLinks.all.enumerated()), id: \.element.id) { index, link in
                    if index > 0 {
                        Divider().overlay(Color.primary.opacity(0.08))
                    }
                    AppLinkRow(link: link)
                }
            }
            .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
        }
    }

    // MARK: - Kullanım

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            usageHeader

            Picker("", selection: $period) {
                ForEach(UsagePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !isLoaded {
                Color.clear.frame(height: 160)
            } else if allTimeSnapshot.isEmpty {
                // Hiç kullanım yok — büyük, açıklayıcı boş durum.
                emptyUsageState
                    .transition(.opacity)
            } else {
                // En az bir kez kullanılmış: liste her zaman sekiz widget'ı
                // birden gösteriyor — hiç dokunulmamış olanlar da sıfırla
                // orada duruyor. Yalnızca "bu dönemde" boşsa (ör. son 7 gün)
                // küçük bir not düşülüyor, koca bir boş ekrana geçilmiyor —
                // kullanıcı zaten geçmişte bir şey yaptığını biliyor.
                VStack(alignment: .leading, spacing: 18) {
                    summaryCards
                    if periodSnapshot.isEmpty {
                        noActivityInPeriodNote
                    } else if hasRecentActivity {
                        miniChart
                    }
                    widgetList
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
            }

            resetFooter
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 1.0),
            value: periodSnapshot.isEmpty
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 1.0),
            value: allTimeSnapshot.isEmpty
        )
    }

    private var noActivityInPeriodNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 10.5))
            Text(L10n.s(
                "Bu dönemde etkinlik yok.",
                "No activity in this period.",
                "В этот период активности не было."
            ))
            .font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
    }

    private var usageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.s("Kullanım", "Usage", "Использование"))
                    .font(.system(size: 19, weight: .semibold))
                    .kerning(-0.2)

                Spacer(minLength: 12)

                if let last = allTimeSnapshot.lastUsedDate, let feature = allTimeSnapshot.lastUsedFeature {
                    Text(lastUsedSummary(feature: feature, date: last))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 14) {
                Label(
                    L10n.s(
                        "\(allTimeSnapshot.totalUses) toplam kullanım",
                        "\(allTimeSnapshot.totalUses) total uses",
                        "Всего использований: \(allTimeSnapshot.totalUses)"
                    ),
                    systemImage: "chart.bar.fill"
                )
                if let mostUsed = allTimeSnapshot.mostUsed {
                    Label(
                        L10n.s(
                            "En çok: \(mostUsed.title)",
                            "Most used: \(mostUsed.title)",
                            "Чаще всего: \(mostUsed.title)"
                        ),
                        systemImage: mostUsed.symbolName
                    )
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(L10n.s(
                "İstatistikler yalnızca bu Mac'te tutulur.",
                "Statistics are kept only on this Mac.",
                "Статистика хранится только на этом Mac."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func lastUsedSummary(feature: UsageFeature, date: Date) -> String {
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        return L10n.s(
            "Son: \(feature.title) · \(relative)",
            "Last: \(feature.title) · \(relative)",
            "Последнее: \(feature.title) · \(relative)"
        )
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var hasRecentActivity: Bool {
        periodSnapshot.dailyTotals.contains { $0.total > 0 }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: L10n.s("Toplam Kullanım", "Total Uses", "Всего"),
                value: "\(periodSnapshot.totalUses)"
            )
            summaryCard(
                title: L10n.s("En Çok Kullanılan", "Most Used", "Чаще всего"),
                value: periodSnapshot.mostUsed?.title ?? "—",
                isNumeric: false
            )
            summaryCard(
                title: L10n.s("Aktif Gün", "Active Days", "Активные дни"),
                value: "\(periodSnapshot.activeDays)"
            )
        }
    }

    private func summaryCard(title: String, value: String, isNumeric: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: isNumeric ? 26 : 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .identity : .numericText())
                // "Most Used" büyük bir sayı değil, adı yazılan bir widget —
                // 16pt'lik metni 26pt'lik rakamların yanına koyunca satır
                // yüksekliği farkı üç kartı eşitsiz boyluyordu. Değer
                // satırına sabit bir yükseklik ayırmak, hangi font boyutu
                // kullanılırsa kullanılsın üçünü aynı hizada tutuyor.
                .frame(height: 31, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
    }

    private var miniChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.s("Son 7 Gün", "Last 7 Days", "Последние 7 дней"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            let maxTotal = max(periodSnapshot.dailyTotals.map(\.total).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(periodSnapshot.dailyTotals) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor.opacity(day.total > 0 ? 0.75 : 0.12))
                            .frame(height: max(4, 44 * CGFloat(day.total) / CGFloat(maxTotal)))
                        Text(Self.weekdayFormatter.string(from: day.day))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        L10n.s(
                            "\(Self.weekdayFormatter.string(from: day.day)): \(day.total) kullanım",
                            "\(Self.weekdayFormatter.string(from: day.day)): \(day.total) uses",
                            "\(Self.weekdayFormatter.string(from: day.day)): использований \(day.total)"
                        )
                    )
                }
            }
            .frame(height: 60, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    private var widgetList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow(L10n.s("Widget'lar", "Widgets", "Виджеты"))

            VStack(spacing: 0) {
                ForEach(Array(periodSnapshot.features.enumerated()), id: \.element.id) { index, usage in
                    if index > 0 {
                        Divider().overlay(Color.primary.opacity(0.08))
                    }
                    UsageBarRow(
                        usage: usage,
                        period: periodSnapshot.period,
                        isTopUsed: usage.count > 0 && index == 0,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
        }
    }

    private var emptyUsageState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(L10n.s("Henüz kullanım kaydedilmedi", "No usage recorded yet", "Использование пока не зафиксировано"))
                .font(.system(size: 13, weight: .medium))

            Text(L10n.s(
                "Etkinliğinizi burada görmek için kenar rayındaki widget'ları açın.",
                "Open widgets from the edge rail to see your activity here.",
                "Откройте виджеты на боковой панели, чтобы увидеть здесь свою активность."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
    }

    private var resetFooter: some View {
        HStack {
            Text(L10n.s(
                "Kullanım istatistikleri bu Mac'te kalır ve asla yüklenmez.",
                "Usage statistics stay on this Mac and are never uploaded.",
                "Статистика использования остаётся на этом Mac и никогда не загружается."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button {
                showResetConfirmation = true
            } label: {
                Text(L10n.s("Kullanım Verisini Sıfırla…", "Reset Usage Data…", "Сбросить данные…"))
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(periodSnapshot.isEmpty && allTimeSnapshot.isEmpty)
        }
        .padding(.top, 4)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

// MARK: - Alt bileşenler

private struct AppLinkRow: View {
    let link: AppLink
    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: link.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(link.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(isHovering ? 0.035 : 0))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Tek bir widget'ın süre içindeki kullanımı: ikon, ad, sayı, oran çubuğu.
///
/// Hiç kullanılmamış bir widget da satır olarak duruyor — yalnızca soluk.
/// Kullanıcı "Battery kaç defa?" diye sorduğunda cevap "0" da olsa görünür
/// olmalı; satırın kaybolması "hiç ölçülmedi" ile "hiç kullanılmadı"yı
/// birbirine karıştırır.
private struct UsageBarRow: View {
    let usage: FeatureUsage
    let period: UsagePeriod
    /// Bu dönemde en çok kullanılan widget mı — küçük bir yıldız rozetiyle
    /// işaretleniyor. Eşitlikte (birden fazla "birinci") rozet yalnızca
    /// listedeki ilk satırda görünür, karışıklık olmasın diye.
    let isTopUsed: Bool
    let reduceMotion: Bool

    private var isUnused: Bool { usage.count == 0 }

    private var percentText: String {
        isUnused ? "—" : "\(Int((usage.fraction * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(usage.feature.tint.opacity(isUnused ? 0.07 : 0.16))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: usage.feature.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isUnused ? AnyShapeStyle(.tertiary) : AnyShapeStyle(usage.feature.tint))
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(usage.feature.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isUnused ? .secondary : .primary)

                    if isTopUsed {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.s("en çok kullanılan", "most used", "самый используемый"))
                    }

                    Spacer(minLength: 8)

                    Text("\(usage.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isUnused ? .tertiary : .secondary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text(percentText)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .trailing)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(usage.feature.tint)
                            .frame(width: max(geo.size.width * usage.fraction, usage.fraction > 0 ? 3 : 0))
                    }
                }
                .frame(height: 7)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0),
                    value: usage.fraction
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isUnused
                ? L10n.s(
                    "\(usage.feature.title), \(period.title.lowercased()) içinde hiç kullanılmadı",
                    "\(usage.feature.title), not used in the \(period.title.lowercased())",
                    "\(usage.feature.title), не использовалось за период «\(period.title)»"
                )
                : L10n.s(
                    "\(usage.feature.title)\(isTopUsed ? ", en çok kullanılan" : ""), \(period.title.lowercased()) içinde \(usage.count) kullanım, yüzde \(Int((usage.fraction * 100).rounded()))",
                    "\(usage.feature.title)\(isTopUsed ? ", most used" : ""), \(usage.count) uses in the \(period.title.lowercased()), \(Int((usage.fraction * 100).rounded())) percent",
                    "\(usage.feature.title)\(isTopUsed ? ", самый используемый" : ""), \(usage.count) использований за период «\(period.title)», \(Int((usage.fraction * 100).rounded())) процентов"
                )
        )
    }
}

// MARK: - Kart zemini

private extension View {
    func aboutCard(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> some View {
        modifier(AboutCardBackground(reduceTransparency: reduceTransparency, contrast: contrast))
    }
}

private struct AboutCardBackground: ViewModifier {
    let reduceTransparency: Bool
    let contrast: ColorSchemeContrast

    private var fillOpacity: Double { reduceTransparency ? 0.09 : 0.045 }
    private var borderOpacity: Double { contrast == .increased ? 0.22 : 0.08 }

    /// Malzemenin üst kenarı hafifçe daha parlak: ışığın camın üstüne
    /// vurduğu izlenimi veriyor. Increase Contrast'ta düz, tek renkli
    /// kenarlığa dönüyor — okunabilirlik incelikten önce gelir.
    private var borderGradient: LinearGradient {
        contrast == .increased
            ? LinearGradient(colors: [Color.primary.opacity(borderOpacity)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [Color.primary.opacity(borderOpacity * 1.8), Color.primary.opacity(borderOpacity * 0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1 : 0.75)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
