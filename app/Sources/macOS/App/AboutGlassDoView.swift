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
    /// Ayarlar penceresinin "Hakkında" bölümünde gömülü çalışırken kendi
    /// kaydırma görünümünü ve pencere zeminini kurmuyor: dıştaki sayfa
    /// zaten kaydırıyor, iç içe iki kaydırma alanı tekerleği bölüyor.
    var isEmbedded = false

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
        Group {
            if isEmbedded {
                content
            } else {
                ScrollView {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.windowBackground)
            }
        }
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

    private var content: some View {
        VStack(alignment: .leading, spacing: isEmbedded ? 22 : 30) {
            hero

            if !AppLinks.all.isEmpty {
                quickLinks
            }

            usageSection
        }
        .padding(.horizontal, isEmbedded ? 0 : 30)
        .padding(.top, isEmbedded ? 0 : 28)
        .padding(.bottom, isEmbedded ? 0 : 24)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.app(size: 24, weight: .semibold))
                    .kerning(-0.3)

                Text(L10n.s(
                    "Mac'inizin kenarında görevler ve sistem bilgisi",
                    "Tasks and system insights at the edge of your Mac",
                    "Задачи и системная информация на краю экрана"
                ))
                .font(.app(.headline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(versionString)
                .font(.app(.body, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            Text(copyrightString)
                .font(.app(.caption))
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
                // En az bir kez kullanılmış: liste her widget'ı gösteriyor
                // — hiç dokunulmamışlar da soluk bir satır ve "—" ile
                // orada duruyor. Yalnızca "bu dönemde" boşsa (ör. son 7 gün)
                // küçük bir not düşülüyor, koca bir boş ekrana geçilmiyor —
                // kullanıcı zaten geçmişte bir şey yaptığını biliyor.
                VStack(alignment: .leading, spacing: 18) {
                    summaryCards
                    if periodSnapshot.isEmpty {
                        noActivityInPeriodNote
                    } else if hasRecentActivity {
                        trendCard
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
            .font(.app(.body))
        }
        .foregroundStyle(.tertiary)
    }

    /// Başlık şeridi.
    ///
    /// Burada eskiden tüm zamanların toplamı ve en çok kullanılanı da
    /// yazıyordu. Hemen altındaki üç kart aynı iki sayıyı dönem için
    /// gösterdiğinden, "Son 7 Gün" seçiliyken ekranda birebir aynı iki
    /// değer iki kez çıkıyordu — üstelik üsttekinin tüm zamanlar olduğunu
    /// hiçbir şey söylemiyordu. Sayılar kartlara bırakıldı.
    ///
    /// Gizlilik notu da buradan kaldırıldı: sıfırlama düğmesinin yanında
    /// zaten aynısı yazıyor ve oraya, "veriyi silme" eyleminin yanına ait.
    private var usageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.s("Kullanım", "Usage", "Использование"))
                .font(.app(size: 19, weight: .semibold))
                .kerning(-0.2)

            Spacer(minLength: 8)

            if let last = allTimeSnapshot.lastUsedDate, let feature = allTimeSnapshot.lastUsedFeature {
                Text(lastUsedSummary(feature: feature, date: last))
                    .font(.app(.body))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
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

    /// Üç özet kartı.
    ///
    /// "En Çok Kullanılan" kartı değer olarak widget'ın adını yazıyordu:
    /// yanındaki iki kart 26 puntoluk rakam gösterirken bu 16 puntoluk bir
    /// metindi, üç kartın değer satırı farklı boylardaydı ve hizayı tutmak
    /// için satıra sabit bir yükseklik verilmişti. Artık üçü de sayı
    /// gösteriyor — en çok kullanılanın kaç kez kullanıldığı — ve adı,
    /// kendi rengindeki simgesiyle birlikte alt satıra iniyor.
    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: L10n.s("Toplam Kullanım", "Total Uses", "Всего"),
                value: "\(periodSnapshot.totalUses)"
            )
            summaryCard(
                title: L10n.s("En Çok Kullanılan", "Most Used", "Чаще всего"),
                value: periodSnapshot.mostUsed == nil ? "—" : "\(periodSnapshot.mostUsedCount)",
                detail: periodSnapshot.mostUsed?.title,
                detailSymbol: periodSnapshot.mostUsed?.symbolName,
                detailTint: periodSnapshot.mostUsed?.tint
            )
            summaryCard(
                title: L10n.s("Aktif Gün", "Active Days", "Активные дни"),
                value: "\(periodSnapshot.activeDays)",
                detail: activeDaysDetail
            )
        }
    }

    /// "6" tek başına bir şey söylemiyordu — altı gün neyin içinde? Dönemin
    /// uzunluğu paydayı veriyor. Tüm zamanlarda payda yok, o yüzden yalnızca
    /// "gün" yazıyor.
    private var activeDaysDetail: String {
        if let window = periodSnapshot.period.dayWindow {
            return L10n.s("\(window) günün içinde", "of \(window) days", "из \(window) дней")
        }
        return L10n.s("gün", "days", "дней")
    }

    private func summaryCard(
        title: String,
        value: String,
        detail: String? = nil,
        detailSymbol: String? = nil,
        detailTint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                // Eşit genişlikli basamak burada yok: hizalanacak bir sütun
                // olmadığında iri puntoda "197" gereksiz gevşek duruyor.
                // Satır sayaçlarında (alt alta dizildikleri yerde) duruyor.
                .font(.app(size: 26, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .identity : .numericText())

            HStack(spacing: 4) {
                if let detailSymbol {
                    Image(systemName: detailSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(detailTint ?? Color.secondary)
                }
                Text(detail ?? "")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Alt satırı olmayan kart da aynı boyda kalsın.
            .frame(height: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
        .accessibilityElement(children: .combine)
    }

    /// Günlük eğilim.
    ///
    /// Üç şey değişti. Sıfır günler eskiden dört puntoluk soluk bir
    /// çubukla çiziliyordu — hiç kullanım olmayan gün, az kullanım olmuş
    /// gibi okunuyordu. Artık her günün arkasında aynı boyda boş bir yuva
    /// var; çubuk yalnızca gerçekten sayı varsa çiziliyor, sıfır gün boş
    /// yuva olarak kalıyor.
    ///
    /// Çubuklar toplama değil en yüksek güne göre ölçekleniyor, yani en
    /// yoğun gün yuvayı dolduruyor ve günler arasındaki fark görünür hâle
    /// geliyor.
    ///
    /// Hiçbir çubuğun üstünde sayı yok: yedi (ya da otuz) sayı kartı
    /// okunmaz hâle getirirdi. Onun yerine tek bir değer, en yüksek gün,
    /// başlığın yanında yazıyor.
    private var trendCard: some View {
        let columns = periodSnapshot.dailyTotals
        let peak = columns.map(\.total).max() ?? 0
        let showsWeekdays = columns.count <= 7

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.s(
                    "Son \(columns.count) gün",
                    "Last \(columns.count) days",
                    "Последние \(columns.count) дн."
                ))
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if peak > 0 {
                    Text(L10n.s("en yüksek \(peak)", "peak \(peak)", "пик \(peak)"))
                        .font(.app(.caption))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(columns) { day in
                    trendColumn(
                        day: day,
                        peak: peak,
                        isToday: day.id == columns.last?.id,
                        showsWeekday: showsWeekdays
                    )
                }
            }

            // Otuz günde her sütuna harf sığmıyor; iki uç tarih grafiğin
            // hangi aralığı kapsadığını söylemeye yetiyor.
            if !showsWeekdays, let first = columns.first {
                HStack(spacing: 0) {
                    Text(Self.shortDateFormatter.string(from: first.day))
                    Spacer(minLength: 8)
                    Text(L10n.s("bugün", "today", "сегодня"))
                }
                .font(.app(.micro, weight: .medium))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .aboutCard(reduceTransparency: reduceTransparency, contrast: contrast)
    }

    /// Çubuk yüksekliğinin tavanı. Kartın içinde sabit: sütun sayısı
    /// değişse de (yedi ↔ otuz) kartın boyu oynamasın.
    private static let trendBarHeight: CGFloat = 52

    private func trendColumn(day: DayCount, peak: Int, isToday: Bool, showsWeekday: Bool) -> some View {
        let weekday = Self.weekdayFormatter.string(from: day.day)

        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                if day.total > 0 {
                    // Yalnızca üst köşeler yuvarlak: çubuk tabana oturuyor,
                    // alt köşeleri de yuvarlatmak onu zeminden koparıyordu.
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous
                    )
                    .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.6))
                    .frame(
                        height: max(3, Self.trendBarHeight * CGFloat(day.total) / CGFloat(max(peak, 1)))
                    )
                }
            }
            .frame(height: Self.trendBarHeight)

            if showsWeekday {
                Text(weekday)
                    .font(.app(.micro, weight: isToday ? .semibold : .medium))
                    .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1.0),
            value: day.total
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.s(
                "\(weekday): \(day.total) kullanım",
                "\(weekday): \(day.total) uses",
                "\(weekday): использований \(day.total)"
            )
        )
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    /// Widget kullanım sıralaması.
    ///
    /// Bölüm başlığı "En çok kullanılan" kartıyla çelişebiliyor: o kart
    /// bütün eylemleri sayıyor (pencere değiştirici, sabitleme…), bu liste
    /// ise yalnızca widget'ları. Başlık bunu söylüyor, yoksa listede
    /// görünmeyen bir şeyin "en çok kullanılan" çıkması soru işareti
    /// bırakıyordu.
    private var widgetList: some View {
        let peak = periodSnapshot.features.map(\.count).max() ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionEyebrow(L10n.s("Widget'lar", "Widgets", "Виджеты"))
                Spacer(minLength: 8)
                Text(L10n.s("kullanım sayısı", "uses", "использований"))
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(periodSnapshot.features.enumerated()), id: \.element.id) { index, usage in
                    if index > 0 {
                        Divider().overlay(Color.primary.opacity(0.06))
                    }
                    UsageBarRow(
                        usage: usage,
                        period: periodSnapshot.period,
                        peak: peak,
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
                .font(.app(.headline, weight: .medium))

            Text(L10n.s(
                "Etkinliğinizi burada görmek için kenar rayındaki widget'ları açın.",
                "Open widgets from the edge rail to see your activity here.",
                "Откройте виджеты на боковой панели, чтобы увидеть здесь свою активность."
            ))
            .font(.app(.body))
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
            .font(.app(.caption))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button {
                showResetConfirmation = true
            } label: {
                Text(L10n.s("Kullanım Verisini Sıfırla…", "Reset Usage Data…", "Сбросить данные…"))
                    .font(.app(.body))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(periodSnapshot.isEmpty && allTimeSnapshot.isEmpty)
        }
        .padding(.top, 4)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.app(.body, weight: .semibold))
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
                    .font(.app(.bodyLarge))
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
/// Sıralamadaki tek satır.
///
/// Eskiden iki satırlıktı: üstte ad + sayı + yüzde, altta tam genişlikte
/// bir çubuk. Üç şey aynı sayıyı anlatıyordu (sayı, yüzde, çubuk) ve on
/// satır ekranı dolduruyordu.
///
/// Şimdi tek satır: kimliği simge ve ad taşıyor, büyüklüğü çubuk, kesin
/// değeri sayı. Yüzde kalktı — çubuk zaten oranı gösteriyor, kesin sayı
/// sağda duruyor ve yüzde ikisinin arasında üçüncü bir okuma olarak
/// yer kaplıyordu. Erişilebilirlik etiketinde duruyor.
private struct UsageBarRow: View {
    let usage: FeatureUsage
    let period: UsagePeriod
    /// Listedeki en yüksek sayı. Çubuklar toplama değil buna göre
    /// ölçekleniyor: `fraction` toplamın payı olduğu için en çok
    /// kullanılan widget bile çubuğun beşte birini dolduruyordu ve on
    /// satır birbirine benzeyen kısa güdükler hâlinde duruyordu.
    let peak: Int
    let reduceMotion: Bool

    /// Çubuk sütununun genişliği. Sabit: satırlar arası karşılaştırma
    /// ancak bütün çubuklar aynı ölçekte çizilince yapılabiliyor, oysa
    /// esnek bir sütun ada göre satırdan satıra kayardı.
    private static let barWidth: CGFloat = 118

    private var isUnused: Bool { usage.count == 0 }

    private var barLength: CGFloat {
        guard peak > 0, usage.count > 0 else { return 0 }
        // En küçük sayı da görünür kalsın: yüzde birlik bir pay yuvarlanıp
        // kaybolmasın diye taban dört punto.
        return max(Self.barWidth * CGFloat(usage.count) / CGFloat(peak), 4)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(usage.feature.tint.opacity(isUnused ? 0.07 : 0.16))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: usage.feature.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isUnused ? AnyShapeStyle(.tertiary) : AnyShapeStyle(usage.feature.tint))
                }

            Text(usage.feature.title)
                .font(.app(.bodyLarge))
                .foregroundStyle(isUnused ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // Çubukların hepsi tek renk. Uzunluk karşılaştırması rengin
            // işi değil; kimlik zaten solda, kendi renginde duruyor. On
            // ayrı renkte on çubuk, hangisinin daha uzun olduğunu
            // okumayı zorlaştırıyordu.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                if barLength > 0 {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: barLength)
                }
            }
            .frame(width: Self.barWidth, height: 6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0),
                value: barLength
            )

            Text(isUnused ? "—" : "\(usage.count)")
                .font(.app(.bodyLarge, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isUnused ? .tertiary : .primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isUnused
                ? L10n.s(
                    "\(usage.feature.title), \(period.title.lowercased()) içinde hiç kullanılmadı",
                    "\(usage.feature.title), not used in the \(period.title.lowercased())",
                    "\(usage.feature.title), не использовалось за период «\(period.title)»"
                )
                : L10n.s(
                    "\(usage.feature.title), \(period.title.lowercased()) içinde \(usage.count) kullanım, yüzde \(Int((usage.fraction * 100).rounded()))",
                    "\(usage.feature.title), \(usage.count) uses in the \(period.title.lowercased()), \(Int((usage.fraction * 100).rounded())) percent",
                    "\(usage.feature.title), \(usage.count) использований за период «\(period.title)», \(Int((usage.fraction * 100).rounded())) процентов"
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
                RoundedRectangle(cornerRadius: Layout.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.Radius.card, style: .continuous)
                            .strokeBorder(borderGradient, lineWidth: contrast == .increased ? 1 : 0.75)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.card, style: .continuous))
    }
}
