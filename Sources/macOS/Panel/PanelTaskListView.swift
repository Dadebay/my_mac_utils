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
        let predicate = showCompleted ? Task.completedPredicate() : Task.activePredicate()
        _tasks = Query(filter: predicate, sort: [SortDescriptor(\Task.sortIndex)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(tasks) { task in
                        row(task)
                            .transition(rowTransition)
                    }
                    if tasks.isEmpty { emptyState }
                }
                .animation(listAnimation, value: tasks.map(\.id))
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
            .gesture(
                DragGesture(minimumDistance: 6)
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
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 0)

            Text("\(tasks.count)")
                .font(.system(size: 11, weight: .semibold))
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

        return HStack(spacing: 10) {
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
                .animation(checkAnimation, value: isChecked)
            }
            .buttonStyle(.pressScale(reduceMotion ? 1 : 0.92))

            Text(task.title)
                .font(.system(size: 13.5, weight: .medium))
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? .secondary : .primary)
                .lineLimit(1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isChecked)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
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
                .font(.system(size: 11.5, weight: .medium))
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

    private var scrollEdgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
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
