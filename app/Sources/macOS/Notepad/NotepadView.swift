import GlassDoKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Notun listedeki kart rengi. `NoteTint`'in sakin tonlarıyla aynı aile.
enum NotepadTint: Int, CaseIterable {
    case olive, coral, rose, mint, sky, violet

    var color: Color {
        switch self {
        case .olive: Color(red: 0.64, green: 0.60, blue: 0.47)
        case .coral: Color(red: 0.65, green: 0.45, blue: 0.40)
        case .rose: Color(red: 0.63, green: 0.43, blue: 0.52)
        case .mint: Color(red: 0.35, green: 0.57, blue: 0.51)
        case .sky: Color(red: 0.36, green: 0.50, blue: 0.65)
        case .violet: Color(red: 0.49, green: 0.45, blue: 0.67)
        }
    }

    static func from(_ raw: Int) -> NotepadTint { NotepadTint(rawValue: raw) ?? .olive }
}

/// Sol tarafta not listesi, sağda onay kutulu satır editörü.
struct NotepadView: View {
    @State private var store = NotepadStore.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            editor
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Liste

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    store.sortsByCreation.toggle()
                } label: {
                    Image(systemName: store.sortsByCreation ? "calendar" : "arrow.up.arrow.down")
                }
                .help(store.sortsByCreation
                      ? L10n.s("Oluşturulma sırası", "Sorted by created", "По созданию")
                      : L10n.s("Son düzenlenen üstte", "Sorted by edited", "По изменению"))
                Spacer()
                Button { store.createNote() } label: { Image(systemName: "square.and.pencil") }
                    .help(L10n.s("Yeni not", "New note", "Новая заметка"))
            }
            .buttonStyle(.borderless)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.sortedNotes) { note in
                        noteRow(note)
                    }
                }
                .padding(8)
            }
        }
    }

    private func noteRow(_ note: PadNote) -> some View {
        let isSelected = note.id == store.selectedID
        let tint = NotepadTint.from(note.tintRaw).color
        return Button {
            store.selectedID = note.id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? L10n.s("Yeni not", "New note", "Новая заметка") : note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(Self.timeLabel(note.updatedAt))
                    .font(.system(size: 11))
                    .opacity(0.75)
            }
            .foregroundStyle(isSelected ? Color.white.opacity(0.95) : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.delete, role: .destructive) { store.deleteNote(note.id) }
        }
    }

    private static func timeLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Editör

    @ViewBuilder
    private var editor: some View {
        if let note = store.selectedNote {
            NotepadEditor(noteID: note.id, store: store)
                .id(note.id)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

private struct NotepadEditor: View {
    let noteID: UUID
    let store: NotepadStore
    @FocusState private var focused: UUID?

    private var lines: [PadLine] { store.notes.first { $0.id == noteID }?.lines ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    Button(L10n.s("Ayırıcı çizgi ekle", "Add divider", "Добавить разделитель")) {
                        insertDivider()
                    }
                    Button(L10n.s("Tamamlananları sil", "Delete checked", "Удалить выполненные")) {
                        change { $0.lines.removeAll { $0.isChecked } ; ensureLine(&$0) }
                    }
                    Divider()
                    Button(L10n.s("Metin olarak dışa aktar…", "Export as Text…", "Экспорт в текст…")) {
                        exportText()
                    }
                    Button(L10n.s("Metni kopyala", "Copy as Text", "Копировать текст")) {
                        guard let note = store.notes.first(where: { $0.id == noteID }) else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.plainText, forType: .string)
                    }
                    Divider()
                    Button(L10n.s("Notu sil", "Delete note", "Удалить заметку"), role: .destructive) {
                        store.deleteNote(noteID)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .onAppear { focused = lines.last?.id }
    }

    @ViewBuilder
    private func row(_ line: PadLine) -> some View {
        switch line.kind {
        case .divider:
            Divider().padding(.vertical, 8)
                .contextMenu { Button(L10n.delete, role: .destructive) { remove(line.id) } }
        case .check, .text:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if line.kind == .check {
                    Button {
                        update(line.id) { $0.isChecked.toggle() }
                    } label: {
                        Image(systemName: line.isChecked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 17))
                            .foregroundStyle(line.isChecked ? Color.appAccent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                TextField("", text: binding(for: line.id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .strikethrough(line.isChecked)
                    .foregroundStyle(line.isChecked ? .secondary : .primary)
                    .focused($focused, equals: line.id)
                    .onSubmit { insertLine(after: line.id) }
                    .onKeyPress(.delete) {
                        guard line.text.isEmpty else { return .ignored }
                        remove(line.id)
                        return .handled
                    }
            }
        }
    }

    private func exportText() {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let name = note.title.isEmpty ? L10n.s("Not", "Note", "Заметка") : note.title
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-") + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? note.plainText.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Satır işlemleri

    private func change(_ body: (inout PadNote) -> Void) {
        store.update(noteID, body)
    }

    private func ensureLine(_ note: inout PadNote) {
        if note.lines.isEmpty { note.lines = [PadLine()] }
    }

    private func update(_ id: UUID, _ body: @escaping (inout PadLine) -> Void) {
        change { note in
            if let i = note.lines.firstIndex(where: { $0.id == id }) { body(&note.lines[i]) }
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { lines.first { $0.id == id }?.text ?? "" },
            set: { new in update(id) { $0.text = new.replacingOccurrences(of: "\n", with: " ") } }
        )
    }

    private func insertLine(after id: UUID) {
        let new = PadLine()
        change { note in
            if let i = note.lines.firstIndex(where: { $0.id == id }) {
                note.lines.insert(new, at: i + 1)
            } else {
                note.lines.append(new)
            }
        }
        focused = new.id
    }

    private func insertDivider() {
        change { $0.lines.append(PadLine(kind: .divider)) ; $0.lines.append(PadLine()) }
        focused = lines.last?.id
    }

    private func remove(_ id: UUID) {
        let all = lines
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        let previous = i > 0 ? all[i - 1].id : nil
        change { note in
            note.lines.removeAll { $0.id == id }
            ensureLine(&note)
        }
        focused = previous ?? lines.first?.id
    }
}
