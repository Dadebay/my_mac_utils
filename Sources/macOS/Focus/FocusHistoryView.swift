import GlassDoKit
import SwiftData
import SwiftUI

/// Kapanmış odak oturumlarının özeti: bugün/son 7 gün toplamı ve görev
/// başına dağılım. Aktif oturum burada görünmez — geçmiş yalnızca bitmiş
/// oturumları sayar (bkz. `FocusSession.actualMinutes`).
struct FocusHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]

    private var finished: [FocusSession] {
        sessions.filter { !$0.isActive }
    }

    private var perTaskTotals: [(task: Task, minutes: Int)] {
        FocusSessionService.perTaskTotals(in: context)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.focusHistoryTitle)
                .font(.app(size: 15, weight: .semibold))

            if finished.isEmpty {
                emptyState
            } else {
                totals
                perTaskBreakdown
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: some View {
        HStack(spacing: 10) {
            totalTile(
                title: L10n.s("Bugün", "Today", "Сегодня"),
                minutes: FocusSessionService.todayMinutes(in: context)
            )
            totalTile(
                title: L10n.s("Son 7 gün", "Last 7 days", "За 7 дней"),
                minutes: FocusSessionService.last7DaysMinutes(in: context)
            )
        }
    }

    private func totalTile(title: String, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(size: 11))
                .foregroundStyle(.secondary)
            Text(minuteLabel(minutes))
                .font(.app(size: 17, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard()
    }

    private var perTaskBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.focusPerTaskLabel)
                .font(.app(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(perTaskTotals.enumerated()), id: \.offset) { pair in
                HStack(spacing: 8) {
                    Text(pair.element.task.title)
                        .font(.app(size: 12.5))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(minuteLabel(pair.element.minutes))
                        .font(.app(size: 12.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 60 dakikanın altında yalnızca dakika; üstünde saat + dakika — ham
    /// "185 dk" okunması gereken bir sayıya dönüşüyordu.
    private func minuteLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) \(L10n.s("dk", "min", "мин"))" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourLabel = "\(hours) \(L10n.s("sa", "h", "ч"))"
        return rest == 0 ? hourLabel : "\(hourLabel) \(rest) \(L10n.s("dk", "min", "мин"))"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.app(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.focusNoHistory)
                .font(.app(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
