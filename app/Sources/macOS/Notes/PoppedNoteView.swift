import SwiftUI
import AppKit
import SwiftData
import GlassDoKit

/// Notun kendi açık/koyu tercihi. Yalnızca temayı uygulayan ince bir sarmal:
/// içerik ayrı bir görünümde olduğu için `@Environment(\.colorScheme)` ile
/// yürürlükteki şemayı okuyabiliyor (aynı görünümde `preferredColorScheme`
/// ayarlayıp okumak mümkün değil).
struct PoppedNoteView: View {
    /// Bu pencerenin gösterdiği not. Her notun kendi içeriği, kendi rengi
    /// ve kendi penceresi var.
    @Bindable var note: StickyNote
    let onClose: () -> Void

    @AppStorage(NoteAppearance.themeKey) private var themeRaw = AppTheme.dark.rawValue

    var body: some View {
        PoppedNoteContent(note: note, onClose: onClose)
            .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .dark).colorScheme)
    }
}

/// Masaüstünde duran tek bir yapışkan not.
///
/// İçerik notun kendi satırları — ana görev listesi değil. Fark davranışta
/// görünüyor: nottaki bir satıra tik atmak onu listeden düşürmüyor, satır
/// yerinde kalıp üstü çiziliyor. Eskiden not ana listenin ikinci bir
/// görünümüydü ve tik atılan satır notun ortasından kayboluyordu.
private struct PoppedNoteContent: View {
    @Bindable var note: StickyNote

    init(note: StickyNote, onClose: @escaping () -> Void) {
        self.note = note
        self.onClose = onClose
        let id = note.id
        _activeTasks = Query(
            filter: #Predicate<Task> { $0.stickyNote?.id == id },
            sort: [SortDescriptor(\Task.sortIndex)]
        )
    }

    /// Başlık şeridindeki kapatma düğmesi — pencere kenarlıksız olduğu için
    /// sistemin kapatma düğmesi yok, kapatmayı controller yapıyor.
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(NoteAppearance.themeKey) private var themeRaw = AppTheme.dark.rawValue

    private var isDark: Bool { colorScheme == .dark }

    @AppStorage(NoteTint.opacityKey) private var noteOpacity = NoteTint.defaultOpacity
    @AppStorage(NoteAppearance.fontScaleKey) private var fontScale = NoteAppearance.defaultFontScale
    @State private var showsColorPicker = false
    @State private var isHoveringHeader = false
    @State private var confirmingDelete = false
    @State private var deleteResetTask: _Concurrency.Task<Void, Never>?

    /// Renk artık nota ait, uygulamaya değil: masaüstünde yan yana duran
    /// notları birbirinden ayıran şey bu.
    private var tint: NoteTint { NoteTint.current(note.tintRaw) }

    /// Notun bütün satırları — tamamlananlar dahil, yerlerinde.
    ///
    /// İlişki dizisi (`note.blocks`) üzerinden okumak yetmiyor: yeni bir
    /// satır eklendiğinde dizi aynı kare içinde güncellenmiyor ve not boş
    /// görünmeye devam ediyordu. `@Query` deponun kendisini dinliyor,
    /// değişiklik anında geliyor.
    @Query private var activeTasks: [Task]

    /// Yalnızca sayaç için: tamamlanan satırlar belgeden çıkmıyor.
    private var completedTasks: [Task] {
        note.orderedBlocks.filter { $0.isCompleted && $0.kind.isCompletable }
    }

    @State private var newTitle = ""
    @State private var newKind: TaskKind = .todo
    @FocusState private var addFocused: Bool
    /// Enter'la bir satırın altına yeni satır açılınca (ya da Backspace'le
    /// bir satır silinince) odağın taşınacağı görev. `NoteTextField` AppKit
    /// düzeyinde çalıştığı için SwiftUI'ın `@FocusState`'i yerine düz bir
    /// durum değişkeniyle sürülüyor.
    @State private var focusedTaskID: UUID?

    /// Metin seçiminin dokunduğu bloklar. Seçimin kendisi metin
    /// görünümünün işi (sürükleme, ⇧+ok, ⌘A, ⌘C hepsi sistemin); burada
    /// yalnızca biçim çubuğunun hangi bloklara uygulanacağı tutuluyor.
    @State private var selectedBlockIDs: [UUID] = []
    /// İmleç mi yoksa gerçek bir aralık mı seçili — çubuk yalnızca aralıkta
    /// çıkıyor.
    @State private var hasRangeSelection = false

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
        .background { fontScaleShortcuts }
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
    /// Renk seçici açıkken düğmeler görünür kalıyor: imleç popover'a
    /// geçtiği an şerit hover'dan çıkıyor ve panelin dayandığı düğme
    /// gözden kayboluyordu.
    private var showsHeaderControls: Bool { isHoveringHeader || showsColorPicker }

    /// Şeridin düğmeleri yalnızca üzerine gelince görünüyor.
    ///
    /// Not masaüstünde sürekli duran bir kâğıt; üç düğmenin her an ekranda
    /// olması, notun kendi içeriğinden çok dikkat çekiyordu. Gizlerken
    /// `opacity` kullanılıyor, koşullu çizim değil: düğmeler yer kaplamaya
    /// devam ediyor, yoksa ilerleme sayacı imleç girip çıktıkça sağa sola
    /// zıplardı. Erişilebilirlik ağacından da düşmüyorlar — VoiceOver
    /// kullanıcısı için görünürlük fare konumuna bağlı olamaz.
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

            /* Tamamlananları göster/gizle düğmesi kalktı: tamamlanan satır
               artık listeden düşmüyor, yerinde üstü çizili duruyor.
               Yerine, masaüstüne ikinci bir not açan düğme geldi —
               yapışkan notun asıl kullanımı bu. */
            headerButton(systemName: "plus",
                         help: L10n.s("Yeni not", "New note", "Новая заметка")) {
                StickyNotesController.shared.createNote(near: note)
            }

            /* Silme iki adımlı: ilk tıklama düğmeyi kırmızı bir onaya
               çeviriyor, ikincisi siliyor. Notun içeriğiyle birlikte
               gitmesi geri alınamaz; tek tıklamayla olmamalı. Üç saniye
               içinde onaylanmazsa düğme eski hâline dönüyor. */
            headerButton(systemName: confirmingDelete ? "trash.fill" : "trash",
                         help: confirmingDelete
                            ? L10n.s("Silmek için tekrar tıkla", "Click again to delete", "Нажмите ещё раз для удаления")
                            : L10n.s("Notu sil", "Delete note", "Удалить заметку"),
                         tint: confirmingDelete ? .red : nil) {
                if confirmingDelete {
                    StickyNotesController.shared.delete(note)
                } else {
                    withAnimation(Motion.toggle) { confirmingDelete = true }
                    deleteResetTask?.cancel()
                    deleteResetTask = _Concurrency.Task { @MainActor in
                        try? await _Concurrency.Task.sleep(for: .seconds(3))
                        guard !_Concurrency.Task.isCancelled else { return }
                        withAnimation(Motion.toggle) { confirmingDelete = false }
                    }
                }
            }

            Spacer(minLength: 0)

            // Sayaç kalıyor: bu bir denetim değil, tek bakışta okunması
            // gereken bilgi — notun var oluş sebebi.
            Text(L10n.progressSummary(completedTasks.count, total))
                .font(.app(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint.foreground.opacity(0.75))
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(tint.gradient)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHoveringHeader = hovering
            }
        }
    }

    /// ⌘+ ve ⌘− — macOS'ta metin boyutunun standart kısayolu. Görünmez
    /// düğmeler: not penceresinin kendi menüsü yok, kısayolu başka bir
    /// yere bağlayacak yer de.
    private var fontScaleShortcuts: some View {
        ZStack {
            Button("") { changeFontScale(by: NoteAppearance.fontScaleStep) }
                .keyboardShortcut("+", modifiers: .command)
            // Artı tuşuna ⇧'sız basıldığında gelen karakter "=" oluyor.
            Button("") { changeFontScale(by: NoteAppearance.fontScaleStep) }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { changeFontScale(by: -NoteAppearance.fontScaleStep) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { fontScale = NoteAppearance.defaultFontScale }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func changeFontScale(by delta: Double) {
        fontScale = NoteAppearance.clampedFontScale(fontScale + delta)
    }

    /// Şerit üzerinde okunaklı olsun diye tonun parlaklığına göre koyu ya
    /// da açık çizilen düğme (bkz. `NoteTint.foreground`).
    /// `tint` verilirse düğme o renkte çizilir — yalnızca silme onayı
    /// kullanıyor; şeridin geri kalanı tonun kendi ön plan rengini alıyor.
    private func headerButton(
        systemName: String,
        help: String,
        tint accent: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent ?? tint.foreground)
                .frame(width: 19, height: 19)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .opacity(showsHeaderControls ? 1 : 0)
        // Görünmezken tıklanamıyor: boş şeride yapılan tıklama pencereyi
        // sürüklemeye başlamalı, gizli bir düğmeyi tetiklememeli.
        .allowsHitTesting(showsHeaderControls)
    }

    /// Renk kutucukları ve saydamlık kaydırıcısı.
    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.s("Renk", "Color", "Цвет"))
                .font(.app(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(NoteTint.allCases) { option in
                    swatch(option)
                }
            }

            Text(L10n.themeLabel)
                .font(.app(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: $themeRaw) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Text(L10n.noteTextSize)
                .font(.app(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                sizeButton("textformat.size.smaller", help: L10n.noteTextSmaller) {
                    changeFontScale(by: -NoteAppearance.fontScaleStep)
                }
                .disabled(fontScale <= NoteAppearance.fontScaleRange.lowerBound + 0.001)

                Text("\(Int((fontScale * 100).rounded()))%")
                    .font(.app(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 44)

                sizeButton("textformat.size.larger", help: L10n.noteTextLarger) {
                    changeFontScale(by: NoteAppearance.fontScaleStep)
                }
                .disabled(fontScale >= NoteAppearance.fontScaleRange.upperBound - 0.001)

                Spacer(minLength: 0)

                Button(L10n.noteTextSizeReset) { fontScale = NoteAppearance.defaultFontScale }
                    .buttonStyle(.plain)
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
                    .disabled(abs(fontScale - NoteAppearance.defaultFontScale) < 0.001)
            }
            .frame(width: 190)

            Text(L10n.s("Saydamlık", "Opacity", "Прозрачность"))
                .font(.app(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(value: $noteOpacity, in: NoteTint.opacityRange)
                .controlSize(.small)
                .frame(width: 190)
        }
        .padding(14)
    }

    private func sizeButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func swatch(_ option: NoteTint) -> some View {
        let isSelected = option.rawValue == note.tintRaw
        return Button {
            note.tintRaw = option.rawValue
            try? context.save()
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

    /// Notun gövdesi tek bir metin belgesi (bkz. `NoteDocumentView`).
    /// Tamamlananlar belgenin dışında, salt okunur bir bölümde: onlar
    /// düzenlenecek satırlar değil, kapanmış işler.
    private var list: some View {
        VStack(spacing: 0) {
            NoteDocumentView(
                tasks: activeTasks,
                isDark: isDark,
                fontScale: fontScale,
                onEdit: applyEdit,
                onToggle: toggleCompletion,
                onClearMarker: clearMarker,
                onRemoveMarker: removeMarker,
                onSelectionChange: { ids, isRange in
                    selectedBlockIDs = ids
                    hasRangeSelection = isRange
                }
            )
            .overlay(alignment: .top) {
                if hasRangeSelection, !selectedBlockIDs.isEmpty {
                    selectionBar
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.16), value: hasRangeSelection)

            if activeTasks.isEmpty {
                emptyState
            }

        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.app(size: 9.5, weight: .semibold))
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
                .font(.app(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Seçim ve toplu eylemler

    private var selectedTasks: [Task] {
        activeTasks.filter { selectedBlockIDs.contains($0.id) }
    }

    /// Seçilen blokların ortak türü; karışıksa `nil`.
    private var commonKind: TaskKind? {
        let kinds = Set(selectedTasks.map(\.kind))
        return kinds.count == 1 ? kinds.first : nil
    }

    /// Seçimin üstünde beliren biçim çubuğu. Kopyalama düğmesi yok:
    /// seçim gerçek bir metin seçimi olduğu için ⌘C zaten sistemin işi.
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TaskKind.allCases) { kind in
                    Button(kind.displayName) { applyKind(kind) }
                }
            } label: {
                Text(commonKind?.displayName ?? L10n.noteMixedKinds)
                    .font(.app(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 14).opacity(0.4)

            Text(L10n.noteSelectedCount(selectedBlockIDs.count))
                .font(.app(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider().frame(height: 14).opacity(0.4)

            barButton("checkmark.circle", help: L10n.completedTasks) { completeSelection() }
            barButton("trash", help: L10n.delete, isDestructive: true) { deleteSelection() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        }
    }

    private func barButton(
        _ systemName: String,
        help: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : Color.primary.opacity(0.8))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func applyKind(_ kind: TaskKind) {
        for task in selectedTasks { task.kind = kind }
        try? context.save()
    }

    private func completeSelection() {
        for task in selectedTasks where task.kind.isCompletable {
            task.isCompleted = true
            task.completedAt = .now
        }
        try? context.save()
    }

    private func deleteSelection() {
        for task in selectedTasks { context.delete(task) }
        try? context.save()
    }

    /// Boş bir satırda Backspace: blok işaretsiz boş satıra dönüyor.
    private func clearMarker(_ id: UUID) {
        guard let task = activeTasks.first(where: { $0.id == id }) else { return }
        task.kind = .spacer
        task.title = ""
        try? context.save()
    }

    /// Metnin başında Backspace: işaret kalkıyor, yazılan metin duruyor.
    private func removeMarker(_ id: UUID) {
        guard let task = activeTasks.first(where: { $0.id == id }) else { return }
        task.kind = .text
        try? context.save()
    }

    private func toggleCompletion(_ id: UUID) {
        guard let task = activeTasks.first(where: { $0.id == id }) else { return }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        try? context.save()
    }

    // MARK: - Belgeden görevlere

    /// Kullanıcı yazdıkça paragrafları görevlerle eşitler.
    ///
    /// Kimlik paragrafın kendi özniteliğinde taşınıyor. Aynı kimliği ikinci
    /// kez gören paragraf, Enter'la bölünmüş bir satırdır: ilki özgün
    /// görevde kalıyor, ikincisi aynı türde yeni bir görev oluyor. Kimliği
    /// hiç olmayan paragraf yeni yazılmış bir satır. Belgede artık
    /// görünmeyen görevler siliniyor — kullanıcı o satırları silmiştir.
    private func applyEdit(_ paragraphs: [NoteParagraph]) {
        var byID: [UUID: Task] = [:]
        for task in activeTasks { byID[task.id] = task }

        var matched: Set<UUID> = []
        // Yeni bir satır, üstündeki satırın türünü sürdürüyor: onay
        // kutuları arasında Enter'a basınca yeni satır da onay kutusu
        // oluyor. Ama yalnızca **yazı taşıyabilen** türler devrediliyor —
        // ayırıcı ve boşluk devredilemez.
        //
        // Devredilince ne oluyordu: bir ayırıcının hemen altına yazı
        // yapıştırıldığında yeni blok `.divider` olarak doğuyor, yazısı
        // olan ama onay kutusu çizilmeyen bir satıra dönüşüyordu
        // (kullanıcı bildirdi: kopyalanan satır yapıştırılınca tik
        // koymuyordu). Ayırıcı ve boşluk yalnızca alt bölümdeki menüden,
        // bilerek ekleniyor.
        var inheritedKind: TaskKind = .todo

        for (order, paragraph) in paragraphs.enumerated() {
            if let id = paragraph.id, let task = byID[id], !matched.contains(id) {
                matched.insert(id)
                if task.kind.hasText, task.title != paragraph.text {
                    task.title = paragraph.text
                }
                task.sortIndex = order
                if task.kind.hasText { inheritedKind = task.kind }
                continue
            }

            // Buraya düşmek "bu paragraf yeni bir blok" demek. Yeni bir
            // blok hiçbir koşulda ayırıcı ya da boşluk olamaz: ikisi de
            // yalnızca alt bölümdeki menüden, `addBlock` ile ekleniyor.
            //
            // Kimlik yine de ayırıcıya çıkabiliyor — Enter'la doğan boş
            // satır, kimliğini bir önceki bloğun satır ayıracından miras
            // alıyor. O mirası buraya taşımak, yazı yazılınca metni
            // yutulan bir satır üretiyordu (`hasText` olmayan bloğun
            // başlığı güncellenmiyor).
            let resolved = paragraph.id.flatMap { byID[$0]?.kind } ?? inheritedKind
            let kind = resolved.hasText ? resolved : .todo
            let created = Task(title: paragraph.text, kind: kind)
            created.sortIndex = order
            created.stickyNote = note
            context.insert(created)
            if kind.hasText { inheritedKind = kind }
        }

        for task in activeTasks where !matched.contains(task.id) {
            context.delete(task)
        }

        try? context.save()
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
                    .font(.app(size: 12.5))
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
        // Satır ana listeye değil bu nota ait (bkz. `StickyNote`).
        task.stickyNote = note
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
        newTask.stickyNote = note
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
    let isSelected: Bool
    /// Değiştirici tuşlu tıklama — hangi tuşun basılı olduğunu çağıran
    /// yorumluyor (⇧ aralık, ⌘ tek tek).
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onDelete: () -> Void
    /// Metin alanındayken Enter'a basılınca çağrılır — altına yeni bir satır açar.
    let onCreateNext: () -> Void
    /// Satır boşken Backspace'e basılınca çağrılır — satırı siler, odağı
    /// bir öncekine taşır. Metin doluyken normal karakter silmeye karışmaz.
    let onDeleteEmpty: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage(NoteAppearance.fontScaleKey) private var fontScale = NoteAppearance.defaultFontScale
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
                .fill(selectionFill)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        // Düz tıklama metin alanına gidiyor; buraya yalnızca ⇧/⌘ basılıyken
        // ulaşıyor (bkz. `SelectionPassthroughTextField`). Hangi tuşun
        // basılı olduğunu olayın kendisinden okuyoruz — SwiftUI'ın dokunma
        // hareketi değiştiricileri taşımıyor.
        .onTapGesture { onSelect(NSEvent.modifierFlags) }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
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

    private var selectionFill: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        return Color.primary.opacity(isHovering ? 0.06 : 0)
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
                .font(.app(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 1)

        case .heading, .text, .divider, .spacer:
            EmptyView()
        }
    }

    /// Belgeyle aynı ölçek: tamamlananlar bölümü küçük kalırsa aynı
    /// pencerede iki farklı punto olurdu.
    private var nsFont: NSFont {
        NoteDocumentBuilder.font(for: kind, scale: fontScale)
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
