import SwiftUI
import SwiftData
import GlassDoKit

struct TaskListView: View {
    let selection: SmartList

    @Environment(\.modelContext) private var context
    @Environment(PoppedNoteController.self) private var notes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tasks: [Task]
    @State private var searchText = ""
    @State private var newTaskTitle = ""
    @State private var selectedTask: Task?
    @FocusState private var quickAddFocused: Bool
    /// Enter'la bir satırın altına yeni satır açılınca (ya da Backspace'le
    /// bir satır silinince) odağın taşınacağı görev.
    @State private var focusedTaskID: UUID?

    init(selection: SmartList) {
        self.selection = selection
        let predicate = selection == .completed ? Task.completedPredicate() : Task.activePredicate()
        _tasks = Query(filter: predicate, sort: [SortDescriptor(\Task.sortIndex)])
    }

    private var filteredTasks: [Task] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var summary: String {
        selection == .completed
            ? L10n.completedTaskSummary(tasks.count)
            : L10n.activeTaskSummary(tasks.count)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if filteredTasks.isEmpty {
                emptyState
            } else {
                taskList
            }

            if selection != .completed {
                quickAddBar
                    .padding(.bottom, 14)
                    .padding(.horizontal, 18)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { popOutButton }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: L10n.searchPlaceholder)
        .navigationTitle(selection.title)
        .navigationSubtitle(summary)
    }

    /// Tüm görev listesini, Sticky Notes gibi ekranda duran ayrı bir
    /// yapışkan not penceresine çıkarır.
    private var popOutButton: some View {
        Button {
            notes.toggle()
        } label: {
            Image(systemName: notes.isOpen ? "pip.exit" : "pip.enter")
                .foregroundStyle(notes.isOpen ? Color.accentColor : .primary)
        }
        .help(notes.isOpen
              ? L10n.s("Notu kapat", "Close note", "Закрыть заметку")
              : L10n.s("Listeyi ekrana çıkar", "Pop out list", "Открыть список в окне"))
    }

    private var taskList: some View {
        // `selection:` bağlamıyor: macOS bu durumda seçili satırı, verilen
        // `listRowBackground` şeklini yok sayarak köşesiz/keskin bir mavi
        // dikdörtgenle boyuyordu. Seçim artık tamamen TaskRow'un kendi
        // yuvarlak zeminiyle gösteriliyor (bkz. TaskRow.rowBackgroundFill).
        List {
            ForEach(filteredTasks) { task in
                TaskRow(
                    task: task,
                    isSelected: selectedTask == task,
                    focusedID: $focusedTaskID,
                    onToggle: { toggle(task) },
                    onCommit: { save() },
                    onDelete: { delete(task) },
                    onSelect: { selectedTask = task },
                    // Tamamlananlar listesinde yeni satır açmak/boş satır
                    // silmek anlamsız — yalnızca aktif listede etkin.
                    onCreateNext: selection == .completed ? {} : { insertTask(after: task) },
                    onDeleteEmpty: selection == .completed ? {} : { deleteEmptyAndFocusPrevious(task) }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button(L10n.delete, role: .destructive) { delete(task) }
                }
            }

            Color.clear
                .frame(height: selection == .completed ? 8 : 60)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            if let selectedTask { delete(selectedTask) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? emptyIcon : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? emptyMessage : L10n.noSearchResults)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        selection == .completed ? "checkmark.circle" : "party.popper"
    }

    private var emptyMessage: String {
        selection == .completed ? L10n.emptyCompleted : L10n.emptyTasks
    }

    private var quickAddBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))

            TextField(L10n.mainWindowQuickAddPlaceholder, text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($quickAddFocused)
                .onSubmit(addTask)

            if !newTaskTitle.isEmpty {
                Text(L10n.enterHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.065)))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 42)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            quickAddFocused ? Color.accentColor.opacity(0.48) : Color.primary.opacity(0.09),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0),
            value: quickAddFocused
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: newTaskTitle.isEmpty)
    }

    private func addTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = Task(title: trimmed)
        task.sortIndex = (tasks.map(\.sortIndex).max() ?? -1) + 1
        context.insert(task)
        try? context.save()
        newTaskTitle = ""
        UsageStore.track(.quickAdd, source: .mainWindow)
    }

    private func toggle(_ task: Task) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? .now : nil
        }
        try? context.save()
    }

    private func delete(_ task: Task) {
        if selectedTask == task { selectedTask = nil }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)) {
            context.delete(task)
        }
        try? context.save()
    }

    private func save() {
        try? context.save()
    }

    /// Bir satırın içindeyken Enter'a basınca, hemen altına aynı türden
    /// boş bir satır açar ve odağı ona taşır — Notion'daki gibi.
    private func insertTask(after task: Task) {
        // Aradaki tüm görevleri bir kaydırıp yeni satıra yer açıyoruz.
        for other in tasks where other.sortIndex > task.sortIndex {
            other.sortIndex += 1
        }
        let newTask = Task(title: "", kind: task.kind)
        newTask.sortIndex = task.sortIndex + 1
        context.insert(newTask)
        try? context.save()
        focusedTaskID = newTask.id
    }

    /// Boş bir satırda Backspace'e basılınca çağrılır: satırı silip odağı
    /// bir öncekine taşır.
    private func deleteEmptyAndFocusPrevious(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = index > 0 ? tasks[index - 1] : nil
        if selectedTask == task { selectedTask = nil }
        context.delete(task)
        try? context.save()
        focusedTaskID = previous?.id
    }
}
