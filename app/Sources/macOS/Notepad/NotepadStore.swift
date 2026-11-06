import Foundation
import Observation

/// Notepad penceresindeki tek bir satır: onay kutulu, düz ya da ayırıcı.
struct PadLine: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case check, text, divider }

    var id = UUID()
    var kind: Kind = .check
    var text = ""
    var isChecked = false
}

/// Notepad'deki bağımsız not. Ana görev listesinden ve `StickyNote`
/// kayıtlarından ayrı: kendi satırlarını taşıyor.
struct PadNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var lines: [PadLine] = [PadLine()]
    var tintRaw = 0
    var createdAt = Date()
    var updatedAt = Date()

    /// Dışa aktarma ve kopyalama için düz metin: onay kutuları ☐ / ☑.
    var plainText: String {
        lines.map { line in
            switch line.kind {
            case .check: (line.isChecked ? "☑ " : "☐ ") + line.text
            case .text: line.text
            case .divider: String(repeating: "─", count: 24)
            }
        }.joined(separator: "\n")
    }

    /// Listede görünen başlık: ilk dolu satır.
    var title: String {
        lines.first(where: { $0.kind != .divider && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })?.text
            ?? ""
    }
}

/// Notepad notlarının deposu. SwiftData şemasına dokunmamak için
/// Application Support altında tek bir JSON dosyası; yazım gecikmeli,
/// her tuş vuruşunda diske gitmiyor.
@MainActor
@Observable
final class NotepadStore {
    static let shared = NotepadStore()

    private(set) var notes: [PadNote] = []
    var selectedID: UUID?
    /// Liste sıralaması: son düzenlenen üstte ya da oluşturulma sırası.
    var sortsByCreation = UserDefaults.standard.bool(forKey: "notepad.sortByCreation") {
        didSet { UserDefaults.standard.set(sortsByCreation, forKey: "notepad.sortByCreation") }
    }

    @ObservationIgnored private var saveTask: _Concurrency.Task<Void, Never>?

    private init() {
        load()
        if notes.isEmpty { createNote() }
        selectedID = sortedNotes.first?.id
    }

    var sortedNotes: [PadNote] {
        notes.sorted { sortsByCreation ? $0.createdAt > $1.createdAt : $0.updatedAt > $1.updatedAt }
    }

    var selectedNote: PadNote? {
        notes.first { $0.id == selectedID }
    }

    // MARK: - Düzenleme

    func createNote() {
        let note = PadNote(tintRaw: notes.count % NotepadTint.allCases.count)
        notes.append(note)
        selectedID = note.id
        scheduleSave()
    }

    func deleteNote(_ id: UUID) {
        let order = sortedNotes.map(\.id)
        notes.removeAll { $0.id == id }
        if notes.isEmpty { createNote(); return }
        if selectedID == id {
            let index = order.firstIndex(of: id) ?? 0
            let remaining = sortedNotes.map(\.id)
            selectedID = remaining[min(index, remaining.count - 1)]
        }
        scheduleSave()
    }

    func update(_ id: UUID, _ change: (inout PadNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        change(&note)
        guard note != notes[index] else { return }
        note.updatedAt = Date()
        notes[index] = note
        scheduleSave()
    }

    // MARK: - Kalıcılık

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlassDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("notepad.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([PadNote].self, from: data)
        else { return }
        notes = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .milliseconds(400))
            guard !_Concurrency.Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
