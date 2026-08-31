import SwiftUI
import SwiftData
import GlassDoKit

struct PanelQuickAddView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [Task]
    @State private var newTaskTitle = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 23, height: 23)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))

            TextField(L10n.panelQuickAddPlaceholder, text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .onSubmit(addTask)

            if !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.pressScale(reduceMotion ? 1 : 0.92))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 39)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.5)
                }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1.0),
            value: newTaskTitle.isEmpty
        )
    }

    private func addTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Task(title: trimmed)
        task.sortIndex = (tasks.map(\.sortIndex).max() ?? -1) + 1
        context.insert(task)
        try? context.save()
        newTaskTitle = ""
        UsageStore.track(.quickAdd, source: .edgeRail)
    }
}
