import AppKit
import GlassDoKit
import SwiftData
import SwiftUI

/// Tek bir görevin tüm alanlarını gösteren ayrıntı sayfası: başlık, notlar,
/// bitiş tarihi, öncelik, tekrar, alt görevler ve bağlam (ek dosyalar).
///
/// Değişiklikler doğrudan modele yazılıyor — ayrı bir "Kaydet" yok, çünkü
/// listede de düzenleme aynı şekilde anında işliyor; iki farklı kayıt
/// davranışı aynı veriyi iki ayrı yerde farklı kurallarla yönetirdi.
struct TaskDetailView: View {
    @Bindable var task: Task

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newSubtaskTitle = ""
    @State private var showingShelfPicker = false
    @State private var showingClipboardPicker = false

    private var subtasks: [Task] {
        (task.subtasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    private var attachments: [TaskAttachment] {
        (task.attachments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    notesSection
                    attributesSection
                    subtasksSection
                    contextSection
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 560)
        .sheet(isPresented: $showingShelfPicker) {
            ShelfAttachmentPickerView { url in
                attach(url: url)
            }
        }
        .sheet(isPresented: $showingClipboardPicker) {
            ClipboardAttachmentPickerView { text in
                attach(text: text)
            }
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.taskDetailTitle)
                .font(.app(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)

            Spacer(minLength: 8)

            Button(L10n.close) { dismiss() }
                .buttonStyle(.plain)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Notlar

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(size: 17, weight: .semibold))
                .lineLimit(1...3)

            sectionTitle(L10n.notesSectionTitle)

            TextEditor(text: $task.notes)
                .font(.app(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(8)
                .glassCard()
                .overlay(alignment: .topLeading) {
                    if task.notes.isEmpty {
                        Text(L10n.notesPlaceholder)
                            .font(.app(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Özellikler

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)

                Text(L10n.dueDateLabel)
                    .font(.app(size: 13))

                Spacer(minLength: 8)

                if task.dueDate == nil {
                    Button(L10n.noDueDate) { task.dueDate = .now }
                        .buttonStyle(.plain)
                        .font(.app(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { task.dueDate ?? .now },
                            set: { task.dueDate = $0 }
                        ),
                        displayedComponents: [.date]
                    )
                    .labelsHidden()

                    Button {
                        task.dueDate = nil
                        // Tarih kalkınca tekrar kuralının dayanağı da
                        // kalkıyor — kural yetim bırakılmıyor.
                        task.recurrenceRule = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.app(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: task.priority.symbolName)
                    .font(.app(size: 11))
                    .foregroundStyle(task.priority.tintColor)
                    .frame(width: 18, alignment: .center)

                Text(L10n.priorityLabel)
                    .font(.app(size: 13))

                Spacer(minLength: 8)

                Picker("", selection: $task.priority) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)

                Text(L10n.recurrenceLabel)
                    .font(.app(size: 13))

                Spacer(minLength: 8)

                Picker("", selection: recurrenceBinding) {
                    Text(L10n.recurrenceNone).tag(RecurrenceFrequency?.none)
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(RecurrenceFrequency?.some(frequency))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(task.dueDate == nil)
            }

            if task.dueDate == nil {
                Text(L10n.recurrenceNeedsDueDateHint)
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recurrenceBinding: Binding<RecurrenceFrequency?> {
        Binding(
            get: { task.recurrenceRule?.frequency },
            set: { frequency in
                task.recurrenceRule = frequency.map { RecurrenceRule(frequency: $0) }
            }
        )
    }

    // MARK: - Alt görevler

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.subtasksTitle)

            ForEach(subtasks) { subtask in
                HStack(spacing: 9) {
                    Button {
                        subtask.isCompleted.toggle()
                        subtask.completedAt = subtask.isCompleted ? .now : nil
                    } label: {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.app(size: 14))
                            .foregroundStyle(subtask.isCompleted ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(subtask.title)
                        .font(.app(size: 13))
                        .strikethrough(subtask.isCompleted, color: .secondary)
                        .foregroundStyle(subtask.isCompleted ? .secondary : .primary)

                    Spacer(minLength: 8)

                    Button {
                        context.delete(subtask)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.app(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(L10n.addSubtaskPlaceholder, text: $newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.app(size: 13))
                .onSubmit(addSubtask)
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let subtask = Task(title: title)
        subtask.parentTask = task
        subtask.sortIndex = (subtasks.last?.sortIndex ?? -1) + 1
        context.insert(subtask)
        newSubtaskTitle = ""
    }

    // MARK: - Bağlam

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(L10n.contextSectionTitle)

                Spacer(minLength: 8)

                Menu {
                    Button(L10n.addFileAttachment) { pickFile(chooseDirectories: false) }
                    Button(L10n.addFolderAttachment) { pickFile(chooseDirectories: true) }
                    Button(L10n.addFromShelfAttachment) { showingShelfPicker = true }
                    Button(L10n.addFromClipboardAttachment) { showingClipboardPicker = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.app(size: 10, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.addAttachmentHelp)
            }

            if attachments.isEmpty {
                Text(L10n.noAttachments)
                    .font(.app(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(attachments) { attachment in
                    attachmentRow(attachment)
                }
            }
        }
    }

    private func attachmentRow(_ attachment: TaskAttachment) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName(for: attachment.kind))
                .font(.app(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(attachment.displayName)
                .font(.app(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                context.delete(attachment)
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { reveal(attachment) }
    }

    private func symbolName(for kind: TaskAttachmentKind) -> String {
        switch kind {
        case .file: "doc"
        case .folder: "folder"
        case .screenshot: "photo"
        case .clipboardText: "doc.on.clipboard"
        }
    }

    /// Dosyanın kendisi kopyalanmıyor; yalnızca güvenlik kapsamlı bir
    /// bookmark tutuluyor (bkz. `TaskAttachment`).
    private func pickFile(chooseDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attach(url: url)
    }

    private func attach(url: URL) {
        guard let bookmark = try? TaskAttachment.makeBookmark(for: url) else { return }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let attachment = TaskAttachment(
            displayName: url.lastPathComponent,
            kind: isDirectory ? .folder : .file
        )
        attachment.bookmarkData = bookmark
        attachment.task = task
        context.insert(attachment)
    }

    private func attach(text: String) {
        let attachment = TaskAttachment(
            displayName: String(text.prefix(60)),
            kind: .clipboardText
        )
        attachment.copiedText = text
        attachment.task = task
        context.insert(attachment)
    }

    private func reveal(_ attachment: TaskAttachment) {
        guard let resolved = attachment.resolveBookmark() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([resolved.url])
    }

    // MARK: - Ortak parçalar

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }

    /// Simge sütunu sabit genişlikte: farklı genişlikteki SF sembolleri
    /// satır başlarını birbirinden kaydırmasın.
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.app(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.app(size: 13))
        }
    }
}

/// Öncelik satırındaki küçük nokta için — mevcut sistem paletindeki
/// anlamsal renkleri yeniden kullanıyor, yeni bir renk tanımlamıyor.
private extension Priority {
    var tintColor: Color {
        switch self {
        case .none: .secondary
        case .low: .secondary
        case .medium: SystemPalette.warning
        case .high: SystemPalette.danger
        }
    }
}
