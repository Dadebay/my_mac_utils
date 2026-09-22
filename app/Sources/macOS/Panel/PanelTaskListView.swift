import SwiftUI
import SwiftData
import GlassDoKit

struct PanelTaskListView: View {
    @Query private var tasks: [Task]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showCompleted: Bool

    /// Tik anında görünür, kısa bir geri alma aralığından sonra satır doğal
    /// yerinden ayrılır. Rastgele parçacık yerine konumsal olarak tutarlı
    /// opacity/scale kullanılır.
    @State private var pendingCompletions: Set<UUID> = []
    @State private var departingTasks: Set<UUID> = []
    @State private var hoveredTaskID: UUID?
    private static let completionDelay: Double = 0.65
    private static let departureDuration: Double = 0.22

    /// Basılı tutup sürükleyerek kaydırma için: listenin o anki dikey
    /// kaydırma konumu ve sürükleme başladığındaki değeri.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var currentScrollY: CGFloat = 0
    @State private var dragStartScrollY: CGFloat?

    init(showCompleted: Bool) {
        self.showCompleted = showCompleted
        // Rail rozetiyle aynı yüzey, aynı sayım: başlık/metin/ayırıcı/boşluk
        // blokları panele hiç girmiyor (bkz. `activeTodoPredicate`).
        let predicate = showCompleted ? Task.completedTodoPredicate() : Task.activeTodoPredicate()
        _tasks = Query(filter: predicate, sort: [SortDescriptor(\Task.sortIndex)])
    }

    /// Panelde yalnızca gerçekten bir şey yazan satırlar görünüyor.
    ///
    /// Not editöründe bırakılan boş satırlar veri tarafında başlığı boş
    /// birer `.todo` kaydı; predicate onları eleyemiyor. Notta grupları
    /// ayıran bir boşluk olarak anlamlılar, ama dar panelde kendi onay
    /// kutusu olan boş bir satıra dönüşüp listeyi seyreltiyorlar.
    /// Ayrılmış not görünümü bu süzgeci kullanmıyor; orada boşluklar
    /// olduğu gibi duruyor.
    private var visibleTasks: [Task] {
        tasks.filter(\.title.hasVisibleContent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visibleTasks) { task in
                        row(task)
                            .transition(rowTransition)
                    }
                    if visibleTasks.isEmpty { emptyState }
                }
                // Kenar solması listenin en üstündeki satırı karartıyordu.
                // Bu pay, durağan hâlde solmanın satıra değil boşluğa
                // denk gelmesini sağlıyor.
                .padding(.vertical, 8)
                .animation(listAnimation, value: visibleTasks.map(\.id))
                .background(SlimScrollers())
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                // Sürükleme sırasında kendi hedefimizi yazıyoruz; geri
                // beslemeyi önlemek için yalnızca boştayken senkronla.
                if dragStartScrollY == nil { currentScrollY = newValue }
            }
            // Kaydırma tekerine ek olarak: listeye basılı tutup yukarı/aşağı
            // sürükleyince de kayar (dokunmatik alışkanlığı).
            // Eşik 6 pikselken fare tıklaması sırasındaki en küçük
            // titreme bile sürüklemeyi başlatıyor ve içerideki düğmenin
            // basılmasını iptal ediyordu — onay kutusu "bazen çalışan" bir
            // şeye dönüşüyordu. 14 piksel, kasıtlı sürüklemeyi hâlâ
            // yakalıyor ama tıklamayı çalmıyor.
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        let base = dragStartScrollY ?? currentScrollY
                        if dragStartScrollY == nil { dragStartScrollY = base }
                        currentScrollY = base - value.translation.height
                        scrollPosition.scrollTo(y: currentScrollY)
                    }
                    .onEnded { _ in dragStartScrollY = nil }
            )
            .mask(scrollEdgeMask)
            if !showCompleted {
                PanelQuickAddView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: PanelSettings.panelWidth, height: PanelSettings.effectivePanelHeight, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: showCompleted ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(showCompleted ? SystemPalette.positive : Color.accentColor)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            (showCompleted ? SystemPalette.positive : Color.accentColor)
                                .opacity(0.14)
                        )
                }

            Text(showCompleted ? L10n.completedTasks : L10n.activeTasks)
                .font(.app(size: 15, weight: .semibold))

            Spacer(minLength: 0)

            Text("\(visibleTasks.count)")
                .font(.app(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.065)))
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }

    private func row(_ task: Task) -> some View {
        let isChecked = task.isCompleted || pendingCompletions.contains(task.id)
        let isDeparting = departingTasks.contains(task.id)
        let isHovered = hoveredTaskID == task.id

        // Üstten hizalı: başlık iki satıra taştığında onay kutusu ortada
        // asılı kalmasın, ilk satırın yanında dursun.
        return HStack(alignment: .top, spacing: 10) {
            Button { toggle(task) } label: {
                ZStack {
                    Circle()
                        .fill(isChecked ? SystemPalette.positive : Color.clear)
                    Circle()
                        .strokeBorder(
                            isChecked ? SystemPalette.positive : Color.secondary.opacity(0.72),
                            lineWidth: 1.4
                        )

                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 20, height: 20)
                // Tıklama alanı çizilen daireden bağımsız olarak tanımlı.
                //
                // İşaretsiz haldeki daire yalnızca `strokeBorder` + saydam
                // dolgu; bu şekil üzerinden isabet denemesi, kullanıcının
                // 1.4 piksellik halkayı tam tutturmasını bekliyordu.
                // Ayrıca 20 piksel, fare hedefi olarak küçük — görünen
                // boyut aynı kalıyor, dokunulabilir alan büyütülüyor.
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .animation(checkAnimation, value: isChecked)
            }
            .buttonStyle(.pressScale(reduceMotion ? 1 : 0.92))

            Text(task.title)
                .font(.app(size: 13.5, weight: .medium))
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? .secondary : .primary)
                // Dar panelde tek satır çoğu başlığı ortasından kesiyordu.
                // İki satır, satır sayısını patlatmadan başlığın anlaşılır
                // olmasına yetiyor; daha uzunları yine üç nokta ile biter.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                // Onay kutusunun tıklama alanı çizilen daireden büyük;
                // metni ilk satırda daireyle aynı hizaya getiren pay.
                .padding(.top, 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isChecked)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        // İki satırlık başlıklar kendiliğinden uzuyor; alt sınır tek
        // satırlık satırların eskisi gibi durmasını sağlıyor.
        .padding(.vertical, 4)
        .frame(minHeight: 38)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color.primary.opacity(
                        isHovered ? 0.075 : (isChecked ? 0.025 : 0.042)
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.07 : 0.035), lineWidth: 0.5)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                hoveredTaskID = inside ? task.id : nil
            }
        }
        .opacity(isDeparting ? 0 : 1)
        .scaleEffect(isDeparting ? 0.98 : 1, anchor: .leading)
        .offset(x: isDeparting && !reduceMotion ? 8 : 0)
        .animation(listAnimation, value: isDeparting)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: showCompleted ? "checkmark.circle" : "checklist")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(showCompleted ? L10n.emptyCompleted : L10n.emptyTasks)
                .font(.app(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .transition(.opacity)
    }

    private var checkAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1.0)
    }

    private var listAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 1.0)
    }

    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
    }

    /// Kenarlarda içeriğin belirip kaybolduğu kısa solma.
    ///
    /// Eskiden yüzdeyle tanımlıydı (%3): panel yükseldikçe solma da
    /// büyüyor, uzun panelde en üstteki satırın üstünü yiyordu. Sabit
    /// piksel her boyda aynı kalıyor.
    private var scrollEdgeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0), .black],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 10)

            Color.black

            LinearGradient(
                colors: [.black, .black.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 10)
        }
    }

    private func toggle(_ task: Task) {
        // Tamamlanmayı beklerken tekrar tıklanırsa iptal et.
        if pendingCompletions.contains(task.id) {
            _ = withAnimation(checkAnimation) {
                pendingCompletions.remove(task.id)
            }
            return
        }

        guard !task.isCompleted else {
            withAnimation(listAnimation) {
                task.isCompleted = false
                task.completedAt = nil
                try? context.save()
            }
            return
        }

        _ = withAnimation(checkAnimation) {
            pendingCompletions.insert(task.id)
        }

        let taskID = task.id
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(Self.completionDelay))
            guard pendingCompletions.contains(taskID) else { return }

            _ = withAnimation(listAnimation) {
                departingTasks.insert(taskID)
            }
            try? await _Concurrency.Task.sleep(for: .seconds(Self.departureDuration))

            guard let target = tasks.first(where: { $0.id == taskID }) else { return }
            target.isCompleted = true
            target.completedAt = .now
            try? context.save()

            pendingCompletions.remove(taskID)
            departingTasks.remove(taskID)
        }
    }
}

/// Paneldeki kaydırma çubuğunu ince, üste binen biçime zorlar.
///
/// macOS'ta "Kaydırma çubuklarını göster" ayarı *Her zaman* olduğunda
/// SwiftUI'ın `ScrollView`'ı klasik kalın çubuğa düşüyor ve dar panelde
/// içeriğin yanında koca bir şerit kaplıyor. Sistem ayarını değiştirmek
/// kullanıcının kararı; burada yalnızca bu panelin kendi kaydırma
/// görünümü üste binen ince biçime alınıyor.
///
/// SwiftUI bu ayarı doğrudan açmıyor, bu yüzden görünüm ağacındaki
/// `NSScrollView`'a erişmek için görünmez bir köprü kullanılıyor.
private struct SlimScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        // Görünüm henüz bir üst görünüme eklenmemiş olabilir; bir sonraki
        // döngüde `enclosingScrollView` çözülüyor.
        DispatchQueue.main.async { apply(from: probe) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.autohidesScrollers = true
    }
}
