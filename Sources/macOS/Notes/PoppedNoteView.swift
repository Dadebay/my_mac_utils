import SwiftUI
import AppKit
import SwiftData
import GlassDoKit

/// Notun kendi açık/koyu tercihi. Yalnızca temayı uygulayan ince bir sarmal:
/// içerik ayrı bir görünümde olduğu için `@Environment(\.colorScheme)` ile
/// yürürlükteki şemayı okuyabiliyor (aynı görünümde `preferredColorScheme`
/// ayarlayıp okumak mümkün değil).
struct PoppedNoteView: View {
    let onClose: () -> Void

    @AppStorage(NoteAppearance.themeKey) private var themeRaw = AppTheme.dark.rawValue

    var body: some View {
        PoppedNoteContent(onClose: onClose)
            .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .dark).colorScheme)
    }
}

/// Ekrana çıkarılmış yapışkan not: tüm görev listesi. İçerik doğrudan
/// görevlerin kendisine bağlı — burada yapılan değişiklik ana pencerede de
/// anında görünür.
private struct PoppedNoteContent: View {
    /// Başlık şeridindeki kapatma düğmesi — pencere kenarlıksız olduğu için
    /// sistemin kapatma düğmesi yok, kapatmayı controller yapıyor.
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(NoteAppearance.themeKey) private var themeRaw = AppTheme.dark.rawValue

    private var isDark: Bool { colorScheme == .dark }

    @AppStorage(NoteTint.storageKey) private var tintRaw = NoteTint.amber.rawValue
    @AppStorage(NoteTint.opacityKey) private var noteOpacity = NoteTint.defaultOpacity
    @State private var showsColorPicker = false

    private var tint: NoteTint { NoteTint.current(tintRaw) }

    @Query(filter: Task.activePredicate(), sort: [SortDescriptor(\Task.sortIndex)])
    private var activeTasks: [Task]

    @Query(filter: Task.completedPredicate(), sort: [SortDescriptor(\Task.sortIndex)])
    private var completedTasks: [Task]

    @State private var newTitle = ""
    @State private var newKind: TaskKind = .todo
    @State private var showsCompleted = false
    @FocusState private var addFocused: Bool
    /// Enter'la bir satırın altına yeni satır açılınca (ya da Backspace'le
    /// bir satır silinince) odağın taşınacağı görev. `NoteTextField` AppKit
    /// düzeyinde çalıştığı için SwiftUI'ın `@FocusState`'i yerine düz bir
    /// durum değişkeniyle sürülüyor.
    @State private var focusedTaskID: UUID?

    /// İlerleme yalnızca gerçek görevleri sayar — başlık, metin ve ayırıcı
    /// blokları "yapılacak iş" değil.
    private var openTodoCount: Int { activeTasks.filter { $0.kind.isCompletable }.count }
    private var total: Int { openTodoCount + completedTasks.count }
    private var progress: Double {
        total == 0 ? 0 : Double(completedTasks.count) / Double(total)
    }

    /// Numaralı blokların sıra numarası — yalnızca kesintisiz numaralı
    /// dizinin içinde sayılır, araya başka bir blok girince baştan başlar.
    private func ordinal(at index: Int, in list: [Task]) -> Int {
        var number = 1
        var cursor = index - 1
        while cursor >= 0, list[cursor].kind == .numbered {
            number += 1
            cursor -= 1
        }
        return number
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            Divider().overlay(Color.primary.opacity(0.08))
            footer
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .opacity(noteOpacity)
    }

    /// Düz tek renk yerine, üstten aşağı hafifçe koyulaşan bir zemin —
    /// kâğıt hissi veren yumuşak bir derinlik.
    private var background: some View {
        LinearGradient(
            colors: isDark
                ? [Color(white: 0.165), Color(white: 0.115)]
                : [Color(white: 1.00), Color(white: 0.945)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Başlık

    /// Notun kendi başlık şeridi: kapatma, renk ve tamamlananlar düğmeleri
    /// tamamen yuvarlatılmış içeriğin İÇİNDE. Şerit aynı zamanda pencerenin
    /// sürükleme alanı (`isMovableByWindowBackground`).
    private var header: some View {
        HStack(spacing: 10) {
            headerButton(systemName: "xmark",
                         help: L10n.s("Notu kapat", "Close note", "Закрыть заметку"),
                         action: onClose)

            headerButton(systemName: "paintpalette.fill",
                         help: L10n.s("Renk ve saydamlık", "Color and opacity", "Цвет и прозрачность")) {
                showsColorPicker.toggle()
            }
            .popover(isPresented: $showsColorPicker, arrowEdge: .bottom) {
                appearancePicker
            }

            headerButton(systemName: showsCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                         help: showsCompleted
                            ? L10n.s("Tamamlananları gizle", "Hide completed", "Скрыть завершённые")
                            : L10n.s("Tamamlananları göster", "Show completed", "Показать завершённые")) {
                withAnimation(.easeOut(duration: 0.16)) { showsCompleted.toggle() }
            }

            Spacer(minLength: 0)

            Text(L10n.progressSummary(completedTasks.count, total))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.5))
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(tint.gradient)
    }

    /// Renkli şerit üzerinde okunaklı olsun diye koyu tonda çizilen düğme.
    private func headerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.62))
                .frame(width: 19, height: 19)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Renk kutucukları ve saydamlık kaydırıcısı.
    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.s("Renk", "Color", "Цвет"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(NoteTint.allCases) { option in
                    swatch(option)
                }
            }

            Text(L10n.themeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: $themeRaw) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Text(L10n.s("Saydamlık", "Opacity", "Прозрачность"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(value: $noteOpacity, in: NoteTint.opacityRange)
                .controlSize(.small)
                .frame(width: 190)
        }
        .padding(14)
    }

    private func swatch(_ option: NoteTint) -> some View {
        let isSelected = option == tint
        return Button {
            tintRaw = option.rawValue
        } label: {
            Circle()
                .fill(option.gradient)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                }
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(L10n.s("Rengi değiştir", "Change color", "Изменить цвет"))
    }

    // MARK: - Liste

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    NoteRow(
                        task: task,
                        ordinal: ordinal(at: index, in: activeTasks),
                        focusedID: $focusedTaskID,
                        onDelete: { delete(task) },
                        onCreateNext: { insertTask(after: task) },
                        onDeleteEmpty: { deleteEmptyAndFocusPrevious(task) }
                    )
                }

                if activeTasks.isEmpty {
                    emptyState
                }

                if showsCompleted, !completedTasks.isEmpty {
                    sectionLabel(L10n.completedTasks)
                    ForEach(completedTasks) { task in
                        NoteRow(task: task, ordinal: 1, focusedID: $focusedTaskID, onDelete: { delete(task) }, onCreateNext: {}, onDeleteEmpty: {})
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 3)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "party.popper")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.emptyTasks)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Alt bölüm (ilerleme + hızlı ekleme)

    private var footer: some View {
        VStack(spacing: 8) {
            progressBar

            HStack(spacing: 8) {
                // Eklenecek bloğun türü. Ayırıcı metin istemediği için
                // seçilir seçilmez doğrudan eklenir.
                Menu {
                    ForEach(TaskKind.allCases) { kind in
                        Button {
                            if kind == .divider {
                                addBlock(kind: .divider, title: "")
                            } else {
                                newKind = kind
                                addFocused = true
                            }
                        } label: {
                            Label(kind.displayName, systemImage: kind.symbolName)
                        }
                    }
                } label: {
                    Image(systemName: newKind.symbolName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color.primary.opacity(0.11)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.s("Blok türü", "Block type", "Тип блока"))

                TextField(L10n.mainWindowQuickAddPlaceholder, text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($addFocused)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        addFocused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.13), value: addFocused)
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Color.primary.opacity(0.04))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.78, blue: 0.45),
                                     Color(red: 0.20, green: 0.62, blue: 0.38)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * progress, progress > 0 ? 4 : 0))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.3), value: progress)
    }

    // MARK: - Eylemler

    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addBlock(kind: newKind, title: trimmed)
        newTitle = ""
        // Başlık ve ayırıcı tek seferlik; ardından yeniden göreve dön ki
        // arka arkaya madde girerken tür sürekli değiştirilmek zorunda
        // kalınmasın, ama liste de yanlışlıkla başlıkla dolmasın.
        if newKind == .heading { newKind = .todo }
    }

    private func addBlock(kind: TaskKind, title: String) {
        let task = Task(title: title, kind: kind)
        task.sortIndex = (activeTasks.map(\.sortIndex).max() ?? -1) + 1
        context.insert(task)
        try? context.save()
    }

    /// Bir satırın içindeyken Enter'a basınca, hemen altına aynı türden
    /// boş bir satır açar ve odağı ona taşır — Notion'daki gibi.
    private func insertTask(after task: Task) {
        // Aradaki tüm görevleri bir kaydırıp yeni satıra yer açıyoruz.
        for other in activeTasks where other.sortIndex > task.sortIndex {
            other.sortIndex += 1
        }
        let newTask = Task(title: "", kind: task.kind)
        newTask.sortIndex = task.sortIndex + 1
        context.insert(newTask)
        try? context.save()
        focusedTaskID = newTask.id
    }

    private func delete(_ task: Task) {
        withAnimation(Motion.toggle) { context.delete(task) }
        try? context.save()
    }

    /// Boş bir satırda Backspace'e basılınca çağrılır: Notion'daki gibi o
    /// satırı silip odağı bir öncekine taşır — Enter'la art arda açılan
    /// boş satırlar geri tuşuyla aynı hızda toparlanabilsin diye.
    private func deleteEmptyAndFocusPrevious(_ task: Task) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = index > 0 ? activeTasks[index - 1] : nil
        context.delete(task)
        try? context.save()
        focusedTaskID = previous?.id
    }
}

// MARK: - Satır

/// Nottaki tek blok. Türüne göre onay kutusu, başlık, madde işareti,
/// sıra numarası ya da yatay çizgi olarak çizilir; metni yerinde
/// düzenlenebilir, sağ tıklamayla türü değiştirilebilir.
private struct NoteRow: View {
    @Bindable var task: Task
    /// Numaralı blokların gösterilecek sırası.
    let ordinal: Int
    @Binding var focusedID: UUID?
    let onDelete: () -> Void
    /// Metin alanındayken Enter'a basılınca çağrılır — altına yeni bir satır açar.
    let onCreateNext: () -> Void
    /// Satır boşken Backspace'e basılınca çağrılır — satırı siler, odağı
    /// bir öncekine taşır. Metin doluyken normal karakter silmeye karışmaz.
    let onDeleteEmpty: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isHovering = false

    private var kind: TaskKind { task.kind }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            marker

            if kind.hasText {
                // SwiftUI'ın `TextField` + `.onKeyPress` ikilisi, alan
                // boşken Backspace'i güvenilir yakalayamıyordu (tuş,
                // `onKeyPress`'e hiç ulaşmadan alanın kendi iç editöründe
                // tükeniyordu). `NoteTextField`, Enter ve Backspace'i AppKit
                // delegesi üzerinden doğrudan yakalayan bir köprü.
                NoteTextField(
                    text: $task.title,
                    font: nsFont,
                    textColor: NSColor(textColor),
                    strikethrough: task.isCompleted,
                    isFocused: Binding(
                        get: { focusedID == task.id },
                        set: { newValue in
                            if newValue {
                                focusedID = task.id
                            } else if focusedID == task.id {
                                focusedID = nil
                            }
                        }
                    ),
                    onSubmit: {
                        try? context.save()
                        onCreateNext()
                    },
                    onDeleteEmpty: onDeleteEmpty
                )
                .frame(height: 18)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(height: 1)
                    .padding(.vertical, 7)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, kind == .heading ? 10 : 5)
        .padding(.bottom, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            ForEach(TaskKind.allCases) { option in
                Button {
                    change(to: option)
                } label: {
                    Label(option.displayName, systemImage: option.symbolName)
                }
            }
            Divider()
            Button(L10n.delete, role: .destructive, action: onDelete)
        }
    }

    /// Satırın soldaki işareti — türe göre onay kutusu, nokta, sayı ya da yok.
    @ViewBuilder
    private var marker: some View {
        switch kind {
        case .todo:
            Button(action: toggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted
                                     ? Color(red: 0.30, green: 0.78, blue: 0.45)
                                     : Color.primary.opacity(isHovering ? 0.55 : 0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

        case .bullet:
            Circle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 4, height: 4)
                .padding(.top, 7)
                .padding(.horizontal, 4.5)

        case .numbered:
            Text("\(ordinal).")
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 1)

        case .heading, .text, .divider:
            EmptyView()
        }
    }

    private var nsFont: NSFont {
        switch kind {
        case .heading: .systemFont(ofSize: 14, weight: .semibold)
        case .text: .systemFont(ofSize: 12)
        default: .systemFont(ofSize: 12.5)
        }
    }

    private var textColor: Color {
        if task.isCompleted { return .secondary }
        return kind == .text ? .secondary : .primary
    }

    private func change(to newKind: TaskKind) {
        withAnimation(.easeOut(duration: 0.14)) {
            task.kind = newKind
            // Yalnızca görevler işaretli kalabilir.
            if !newKind.isCompletable, task.isCompleted {
                task.isCompleted = false
                task.completedAt = nil
            }
        }
        try? context.save()
    }

    private func toggle() {
        withAnimation(Motion.toggle) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? .now : nil
        }
        try? context.save()
    }
}
