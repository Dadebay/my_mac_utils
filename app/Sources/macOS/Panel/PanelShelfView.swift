import AppKit
import GlassDoKit
import SwiftUI

/// Raf — geçici olarak elinin altında tutmak istediğin şeylerin durduğu yer.
///
/// Finder değil: burada klasör hiyerarşisi, yol çubuğu, sütun görünümü yok.
/// Raf tek düzlemli bir yığın — bırak, kullan, kaldır. Kalıcı dosya
/// yönetimi Finder'ın işi; bu yüzden "Raftan Kaldır" dosyayı Çöp'e taşıyıp
/// geri alınabilir bırakıyor, "Sil" ise ayrı ve onaylı bir eylem.
///
/// Aynı görünüm iki yerde yaşıyor: ana pencerede geniş sayfa, kenar
/// panelinde 329 pt'lik dar yüzey. Fark yalnızca ölçülerde (`ShelfMetrics`);
/// bilgi ve eylemler ikisinde de aynı — iki ayrı raf yazılsaydı biri
/// diğerinin gerisinde kalırdı.
struct PanelShelfView: View {
    /// Kenar panelinde `true`, ana pencerede `false`.
    var isCompact = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(PanelSettings.shelfRemovesOnDragKey) private var removesOnDragOut = true
    @AppStorage(PanelSettings.shelfSortKey) private var sortRaw = ShelfSort.recent.rawValue
    @AppStorage(PanelSettings.shelfUsesListLayoutKey) private var usesListLayout = false

    private let dropTargeting = ShelfDropTargeting.shared

    @State private var items: [StorageItem] = []
    @State private var selection: URL?
    @State private var quickLookItem: StorageItem?
    @State private var searchText = ""
    @State private var renaming: StorageItem?
    @State private var renameText = ""
    @State private var deleting: StorageItem?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false
    @State private var isSearching = false

    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool

    private var metrics: ShelfMetrics { isCompact ? .compact : .regular }
    private var palette: ShelfPalette { ShelfPalette() }

    private var sort: ShelfSort {
        get { ShelfSort(rawValue: sortRaw) ?? .recent }
        nonmutating set { sortRaw = newValue.rawValue }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sıralama ve arama tek yerde: ızgara ile liste aynı diziyi görüyor,
    /// yerleşim değiştirince öğelerin sırası kaymıyor.
    private var visibleItems: [StorageItem] {
        let sorted = sort.apply(to: items)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { ShelfFormat.matches($0, query: query) }
    }

    private var selectedItem: StorageItem? {
        items.first { $0.url == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            // `dropTargeting` yalnızca kenar panelinin AppKit köprüsü (bkz.
            // `ShelfDropTargeting`) — ana pencerenin kendi sürükleme algısı
            // yok, o köprüyü okumamalı. Aksi hâlde kenar panelinde biten bir
            // sürüklemenin izi (hata ya da mavi çerçeve) ana penceredeki
            // Raf'ta da görünür kalıyordu.
            if let message = errorMessage ?? (isCompact ? dropTargeting.lastErrorMessage : nil) {
                errorBanner(message)
            }

            Divider().opacity(0.4)

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .shelfSurfaceFrame(isCompact: isCompact)
        // Bırakma hedefi bütün yüzey: kullanıcı dosyayı ızgaranın boşluğuna
        // da bırakabilmeli, yalnızca kartların üstüne değil.
        .onDrop(
            of: ShelfImporter.acceptedTypes,
            isTargeted: $isDropTargeted.animation(motion),
            perform: handleDrop
        )
        .overlay {
            if isDropTargeted || (isCompact && dropTargeting.isTargeted) {
                dropOverlay
            }
        }
        .overlay {
            if let quickLookItem {
                ShelfQuickLook(
                    item: quickLookItem,
                    palette: palette,
                    onCopy: { copy(quickLookItem) },
                    onReveal: { reveal(quickLookItem) },
                    onRemove: {
                        removeFromShelf(quickLookItem)
                        self.quickLookItem = nil
                    },
                    onDelete: {
                        deleting = quickLookItem
                        self.quickLookItem = nil
                    },
                    onClose: { self.quickLookItem = nil }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(motion, value: quickLookItem?.id)
        .task { await reload() }
        // Ekran görüntüsü izleyicisi ve pencere katmanındaki bırakma aynı
        // bildirimi yayınlıyor — raf tek bir yerden tazeleniyor.
        .onReceive(NotificationCenter.default.publisher(for: .glassDoShelfContentsChanged)) { _ in
            _Concurrency.Task { await reload() }
        }
        .background { shortcutSink }
        .alert(L10n.shelfRename, isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField(L10n.shelfRenamePrompt, text: $renameText)
            Button(L10n.shelfRename) { commitRename() }
            Button(L10n.cancel, role: .cancel) { renaming = nil }
        }
        .alert(L10n.shelfDeleteConfirmTitle, isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button(L10n.shelfDeleteForever, role: .destructive) { commitDelete() }
            Button(L10n.cancel, role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.shelfDeleteConfirmBody)
        }
    }

    // MARK: - Araç çubuğu

    /// Tek satır: kimlik solda, denetimler sağda. Dar panelde arama alanı
    /// kendi satırına iniyor — sıkıştırılsaydı üç karakter genişliğinde,
    /// kullanılamaz bir kutuya dönerdi.
    /// Solda kimlik, sağda denetimler. Arama alanı sürekli açık durmuyor:
    /// rafta çoğunlukla bir avuç dosya oluyor ve hep açık bir arama kutusu
    /// başlığın yarısını yiyordu. Büyütece basınca (ya da ⌘F) yerinde
    /// açılıyor.
    @ViewBuilder
    private var toolbar: some View {
        if isCompact {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    titleBlock
                    Spacer(minLength: 6)
                    countLabel
                    layoutToggle
                    sortMenu
                    overflowMenu
                }
                searchField
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 10) {
                titleBlock

                Spacer(minLength: 12)

                if isSearching {
                    searchField
                        .frame(maxWidth: 240)
                        .transition(.opacity)
                } else {
                    countLabel
                    searchButton
                }

                layoutToggle
                sortMenu
                overflowMenu
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSearching)
        }
    }

    /// Ana penceredeki "neredeyim" rozetiyle aynı renk çifti (bkz.
    /// `SidebarEntry.allSystemEntries`, `.folders`) — kenar panelinde o
    /// rozet hiç yok, ikonun kendisi tek kimlik göstergesi, o yüzden gri
    /// değil sayfanın rengini taşıması gerekiyor.
    private static let iconColors: [Color] = [
        Color(red: 0.56, green: 0.61, blue: 0.72),
        Color(red: 0.36, green: 0.41, blue: 0.52),
    ]

    private var titleBlock: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: Self.iconColors, startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 26)
                .overlay {
                    HugeIcon(name: .shelf, size: 14)
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: (Self.iconColors.last ?? .black).opacity(0.35), radius: 3, y: 1)

            Text(L10n.shelfTitle)
                .font(.app(size: metrics.titleSize, weight: .semibold))
        }
    }

    private var countLabel: some View {
        Text(L10n.shelfItemCount(items.count))
            .font(.app(size: 12))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .contentTransition(reduceMotion ? .identity : .numericText())
    }

    private var searchButton: some View {
        iconButton(systemName: "magnifyingglass", help: L10n.shelfSearchPlaceholder) {
            isSearching = true
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField(L10n.shelfSearchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.app(size: 12))
                .focused($searchFocused)
                .onExitCommand(perform: closeSearch)

            Button(action: closeSearch) {
                HugeIcon(name: .close, size: 10)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shelfClearSearch)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            searchFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07),
                            lineWidth: searchFocused ? 1 : 0.5
                        )
                }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: searchFocused)
    }

    /// Izgara ve liste tek bir açma/kapama düğmesi değil, yan yana iki
    /// seçenek: hangi yerleşimde olduğun düğmenin ikonundan değil, hangi
    /// tarafın dolu olduğundan okunuyor.
    private var layoutToggle: some View {
        HStack(spacing: 2) {
            layoutOption(.grid, isOn: !usesListLayout, help: L10n.shelfViewGrid) {
                usesListLayout = false
            }
            layoutOption(.list, isOn: usesListLayout, help: L10n.shelfViewList) {
                usesListLayout = true
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private func layoutOption(
        _ icon: HugeIconName,
        isOn: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HugeIcon(name: icon, size: 13)
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .frame(width: 24, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.primary.opacity(0.10) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.shelfSortLabel, selection: Binding(
                get: { sort },
                set: { sortRaw = $0.rawValue }
            )) {
                ForEach(ShelfSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HugeIcon(name: .sort, size: 14)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.shelfSortLabel)
        .accessibilityLabel(L10n.shelfSortLabel)
    }

    /// "Dosya Ekle" burada: sürükle-bırak rafın asıl yolu, boş durumda da
    /// kendi düğmesi var. Başlıkta sürekli duran bir düğme, en sık
    /// kullanılan eylem olmadığı hâlde en çok yeri kaplıyordu.
    private var overflowMenu: some View {
        Menu {
            Button { addFiles() } label: { Label(L10n.addFiles, huge: .plus) }

            Divider()

            Section(L10n.shelfDragOutSection) {
                Toggle(L10n.shelfRemoveOnDrag, isOn: $removesOnDragOut)
                Text(L10n.shelfRemoveOnDragHint)
            }

            Divider()

            Button(L10n.clearShelf, role: .destructive) { clearShelf() }
                .disabled(items.isEmpty)
            Text(L10n.shelfClearHint)
        } label: {
            HugeIcon(name: .more, size: 14)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func iconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func closeSearch() {
        searchText = ""
        isSearching = false
        searchFocused = false
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            HugeIcon(name: .alert, size: 12)

            Text(message)
                .font(.app(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Button {
                errorMessage = nil
                dropTargeting.lastErrorMessage = nil
            } label: {
                HugeIcon(name: .close, size: 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.cancel)
        }
        .foregroundStyle(SystemPalette.danger)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.danger.opacity(0.12))
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.bottom, 8)
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else if visibleItems.isEmpty {
            noResultsState
        } else {
            ScrollView {
                if usesListLayout {
                    list
                } else {
                    grid
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Kaydırma çubuğu gizli: dar panelde sistem ayarı "her zaman
            // göster" olduğunda kutucukların üstüne biniyor ve sağdaki
            // sütunu kırpıyordu. Kaydırma tekerlek ve trackpad'le zaten
            // çalışıyor.
            // `.hidden` sistemdeki "kaydırma çubuklarını her zaman göster"
            // ayarı açıkken yine çubuk çiziyor; `.never` bunu da bastırıyor.
            .scrollIndicators(.never)
            // Klavye yalnızca liste odaktayken çalışıyor; arama alanındayken
            // boşluk tuşu metne gitmeli.
            .focusable()
            .focused($gridFocused)
            .onKeyPress { handleKeyPress($0) }
            .onExitCommand { selection = nil }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: metrics.cardMinWidth), spacing: metrics.cardSpacing)],
            spacing: metrics.cardSpacing
        ) {
            ForEach(visibleItems) { item in
                ShelfGridCard(
                    item: item,
                    isSelected: selection == item.url,
                    palette: palette,
                    metrics: metrics,
                    reduceMotion: reduceMotion,
                    removesOnDragOut: removesOnDragOut,
                    actions: actions(for: item)
                )
            }
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, metrics.cardSpacing)
        .animation(motion, value: visibleItems.map(\.id))
    }

    private var list: some View {
        LazyVStack(spacing: 2) {
            ForEach(visibleItems) { item in
                ShelfListRow(
                    item: item,
                    isSelected: selection == item.url,
                    palette: palette,
                    reduceMotion: reduceMotion,
                    removesOnDragOut: removesOnDragOut,
                    actions: actions(for: item)
                )
            }
        }
        .padding(.horizontal, metrics.gutter - 4)
        .padding(.vertical, 8)
        .animation(motion, value: visibleItems.map(\.id))
    }

    /// Küçük bir işaret, tek cümlelik başlık, tek cümlelik açıklama ve tek
    /// eylem. Büyük bir karşılama ekranı değil: raf zaten kullanıcının
    /// kendi isteğiyle açtığı bir sayfa.
    private var emptyState: some View {
        VStack(spacing: 10) {
            HugeIcon(name: .drop, size: 26)
                .foregroundStyle(.tertiary)

            Text(L10n.shelfEmptyTitle)
                .font(.app(size: 13, weight: .semibold))

            Text(L10n.shelfEmptyBody)
                .font(.app(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: addFiles) {
                Text(L10n.addFiles)
                    .font(.app(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
            }
            .buttonStyle(.pressScale(reduceMotion ? 1 : 0.97))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    private var noResultsState: some View {
        VStack(spacing: 7) {
            Text(L10n.shelfNoMatches(query))
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(L10n.shelfClearSearch) { searchText = "" }
                .buttonStyle(.plain)
                .font(.app(size: 11.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    /// Sürükleme sırasında yüzeyin tamamını örtmek yerine kenarda bir
    /// çerçeve ve altta küçük bir rozet: altındaki raf görünür kalıyor.
    private var dropOverlay: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)

            HStack(spacing: 7) {
                HugeIcon(name: .drop, size: 13)
                Text(L10n.shelfDropNow)
                    .font(.app(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background { Capsule().fill(Color.accentColor) }
            .foregroundStyle(.white)
            .padding(.bottom, 18)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// ⌘F gibi değiştiricili kısayolların tek sahibi. Görünmez düğmeler
    /// yerine araç çubuğundaki alanlara bağlanamıyor: arama alanı bir
    /// `TextField`, kısayolu yok.
    private var shortcutSink: some View {
        Button("") {
            isSearching = true
            searchFocused = true
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Klavye

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard let item = selectedItem else { return .ignored }

        switch press.key {
        case .space:
            quickLookItem = item
            return .handled
        case .return:
            open(item)
            return .handled
        case .delete, .deleteForward:
            removeFromShelf(item)
            return .handled
        default:
            break
        }

        guard press.modifiers.contains(.command) else { return .ignored }
        switch press.characters {
        case "c":
            copy(item)
            return .handled
        case "o":
            open(item)
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Eylemler

    private func actions(for item: StorageItem) -> ShelfItemActions {
        ShelfItemActions(
            select: { selection = item.url },
            preview: { quickLookItem = item },
            open: { open(item) },
            copy: { copy(item) },
            copyPath: { copyPath(item) },
            reveal: { reveal(item) },
            rename: {
                renameText = item.name
                renaming = item
            },
            removeFromShelf: { removeFromShelf(item) },
            deletePermanently: { deleting = item },
            draggedOut: {
                _Concurrency.Task { await reload() }
            }
        )
    }

    private func reload() async {
        do {
            let service = try ManagedStorageService.default()
            let shelf = try service.prepareShelf()
            let loaded = try await _Concurrency.Task.detached(priority: .userInitiated) {
                try service.contents(of: shelf)
            }.value
            withAnimation(motion) { items = loaded }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        _Concurrency.Task {
            do {
                let accepted = try await ShelfImporter.importDropped(providers)
                if accepted { errorMessage = nil }
            } catch {
                errorMessage = error.localizedDescription
            }
            await reload()
        }
        return true
    }

    /// Varsayılan uygulamada açmak ile raf içinde önizlemek ayrı eylemler:
    /// biri kullanıcıyı uygulamadan çıkarıyor, öteki çıkarmıyor.
    private func open(_ item: StorageItem) {
        NSWorkspace.shared.open(item.url)
    }

    private func copy(_ item: StorageItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }

    private func copyPath(_ item: StorageItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path(percentEncoded: false), forType: .string)
    }

    private func reveal(_ item: StorageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// "Raftan Kaldır" yıkıcı değil: dosya Çöp'e gidiyor, geri alınabilir.
    /// Bu yüzden onay penceresi de yok — akışı kesmeye değmez.
    private func removeFromShelf(_ item: StorageItem) {
        run { service in try service.moveToTrash(item.url) }
    }

    private func commitDelete() {
        guard let deleting else { return }
        run { service in try service.deletePermanently(deleting.url) }
        self.deleting = nil
    }

    private func commitRename() {
        guard let renaming else { return }
        let name = renameText
        run { service in _ = try service.rename(renaming.url, to: name) }
        self.renaming = nil
    }

    private func clearShelf() {
        let urls = items.map(\.url)
        run { service in
            for url in urls {
                try service.moveToTrash(url)
            }
        }
    }

    private func addFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        run { service in
            let shelf = try service.prepareShelf()
            for url in urls {
                _ = try service.importFile(at: url, into: shelf)
            }
        }
    }

    /// Her yıkıcı/eklemeli işlem aynı kabuktan geçiyor: hata tek yerde
    /// yakalanıyor ve liste her durumda tazeleniyor.
    private func run(_ work: @escaping (ManagedStorageService) throws -> Void) {
        do {
            let service = try ManagedStorageService.default()
            try work(service)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        _Concurrency.Task { await reload() }
    }
}

// MARK: - Ölçüler

/// Dar panel ile geniş sayfanın tek farkı. Ölçüler tek yapıda duruyor ki
/// kart büyüdüğünde ona bağlı boşluk ve punto da birlikte büyüsün.
struct ShelfMetrics {
    let gutter: CGFloat
    let cardMinWidth: CGFloat
    let cardSpacing: CGFloat
    let previewHeight: CGFloat
    let titleSize: CGFloat
    let nameSize: CGFloat
    let metaSize: CGFloat

    /// Ana pencere. `cardMinWidth` 180: ~1000 pt'lik içerik genişliğinde
    /// beş sütun çıkıyor, pencere daraldıkça dörde, üçe, ikiye iniyor —
    /// küçülen şey sütun sayısı, küçük resmin kendisi değil.
    static let regular = ShelfMetrics(
        gutter: 16,
        cardMinWidth: 180,
        cardSpacing: 12,
        previewHeight: 112,
        titleSize: 17,
        nameSize: 13,
        metaSize: 11.5
    )

    static let compact = ShelfMetrics(
        gutter: 12,
        cardMinWidth: 132,
        cardSpacing: 10,
        previewHeight: 84,
        titleSize: 13,
        nameSize: 12,
        metaSize: 10.5
    )
}

extension View {
    /// Raf iki yüzeyde yaşıyor: kenar panelinde sabit ölçülü bir pano,
    /// ana pencerede pencereyle birlikte büyüyen bir sayfa.
    @ViewBuilder
    func shelfSurfaceFrame(isCompact: Bool) -> some View {
        if isCompact {
            frame(
                width: PanelSettings.panelWidth,
                height: PanelSettings.effectivePanelHeight,
                alignment: .top
            )
        } else {
            self
        }
    }
}

// MARK: - Sıralama

enum ShelfSort: String, CaseIterable, Identifiable {
    case recent, oldest, name, type, size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: L10n.shelfSortRecent
        case .oldest: L10n.shelfSortOldest
        case .name: L10n.shelfSortName
        case .type: L10n.shelfSortType
        case .size: L10n.shelfSortSize
        }
    }

    @MainActor
    func apply(to items: [StorageItem]) -> [StorageItem] {
        switch self {
        case .recent: items.sorted { $0.modifiedAt > $1.modifiedAt }
        case .oldest: items.sorted { $0.modifiedAt < $1.modifiedAt }
        case .name: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .type: items.sorted { ShelfFormat.typeLabel($0) < ShelfFormat.typeLabel($1) }
        case .size: items.sorted { $0.size > $1.size }
        }
    }
}

// MARK: - Renkler

/// Raf yüzeylerinin renkleri tek yerde. Sabit onaltılık değerler yerine
/// `Color.primary` üzerinden opaklık: uygulama açık temayı da destekliyor,
/// koyu griye çivilenmiş bir kart açık temada kara bir delik olurdu.
struct ShelfPalette {
    var card: Color = Color.primary.opacity(0.05)
    var hover: Color = Color.primary.opacity(0.035)
    var border: Color = Color.primary.opacity(0.07)
    /// Küçük resmin arkasındaki kuyu — kart yüzeyinden bir tık daha derin,
    /// böylece saydam PNG'ler kartın içinde yüzüyormuş gibi durmuyor.
    var well: Color = Color.black.opacity(0.16)
}

// MARK: - Eylem kümesi

/// Bir raf öğesinin bütün eylemleri. Izgara kartı, liste satırı, bağlam
/// menüsü, üzerine gelme çubuğu ve önizleme aynı kümeyi alıyor — beş yerde
/// beş ayrı eylem listesi tutulmuyor.
struct ShelfItemActions {
    var select: () -> Void
    var preview: () -> Void
    var open: () -> Void
    var copy: () -> Void
    var copyPath: () -> Void
    var reveal: () -> Void
    var rename: () -> Void
    var removeFromShelf: () -> Void
    var deletePermanently: () -> Void
    /// Dosya dışarı sürüklenip raftan düştüğünde listeyi tazelemek için.
    var draggedOut: () -> Void
}

/// macOS'un kendi sağ tık menüsü düzeni: önce açma, sonra kopyalama, sonra
/// düzenleme, en altta yıkıcı olanlar.
///
/// "Raftan Kaldır" ile "Sil" kasıtlı olarak ayrı: ilki dosyayı Çöp'e taşıyor
/// (geri alınabilir), ikincisi diskten siliyor (alınamaz). Tek bir "sil"
/// olsaydı kullanıcı rafını toparlarken dosyasını kaybederdi.
private struct ShelfContextMenu: View {
    let actions: ShelfItemActions

    var body: some View {
        Button { actions.open() } label: { Label(L10n.open, huge: .open) }
        Button { actions.preview() } label: { Label(L10n.shelfPreview, huge: .eye) }

        Divider()

        Button { actions.copy() } label: { Label(L10n.shelfCopy, huge: .copy) }
        Button { actions.copyPath() } label: { Label(L10n.shelfCopyPath, huge: .link) }
        Button { actions.reveal() } label: { Label(L10n.revealInFinder, huge: .folder) }

        Divider()

        Button { actions.rename() } label: { Label(L10n.shelfRename, huge: .rename) }

        Divider()

        Button { actions.removeFromShelf() } label: { Label(L10n.removeFromShelf, huge: .trash) }
        Button(role: .destructive) { actions.deletePermanently() } label: {
            Label(L10n.shelfDeleteForever, huge: .trash)
        }
    }
}

/// Üzerine gelince küçük resmin köşesinde beliren çubuk. Bağlam menüsünün
/// tamamı burada tekrarlanmıyor: en sık ikisi görünür, gerisi sağ tıkta.
private struct ShelfHoverBar: View {
    let actions: ShelfItemActions

    var body: some View {
        HStack(spacing: 2) {
            button(.eye, help: L10n.shelfPreview, action: actions.preview)
            button(.copy, help: L10n.shelfCopy, action: actions.copy)

            Menu {
                ShelfContextMenu(actions: actions)
            } label: {
                HugeIcon(name: .more, size: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(.black.opacity(0.5))
        }
        .foregroundStyle(.white)
    }

    private func button(
        _ icon: HugeIconName,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HugeIcon(name: icon, size: 12)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Küçük resim

/// Görsel/PDF/video öğelerde gerçek içeriğin küçük resmi, diğerlerinde
/// türünün ikonu.
///
/// Küçük resim kırpılmıyor (`.fit`): rafa atılan bir ekran görüntüsünün
/// kenarları kesilirse kart neyi gösterdiğini söylemekten çıkıyor. Kabın
/// yüksekliği sabit kaldığı için ızgaranın ritmi de bozulmuyor.
struct ShelfThumbnail: View {
    let item: StorageItem
    var height: CGFloat
    var cornerRadius: CGFloat = 8
    var symbolSize: CGFloat = 24
    var inset: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.16))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(inset)
            } else {
                HugeIcon(name: item.kind.hugeIcon, size: symbolSize)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: item.id) { await load() }
    }

    private func load() async {
        guard [.image, .pdf, .video].contains(item.kind) else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        image = await ThumbnailProvider.shared.thumbnail(for: item, size: 512, scale: scale)
    }
}

// MARK: - Biçimlendirme

/// Raf öğelerinin metin karşılıkları. Izgara, liste ve önizleme aynı yazıyı
/// gösteriyor — üç yerde üç ayrı biçimlendirme yazılsaydı biri diğerinden
/// kayardı.
@MainActor
enum ShelfFormat {
    /// Okunur ad. İki şey yapıyor:
    ///
    /// 1. Uzantıyı atıyor — tür zaten künyede yazıyor.
    /// 2. Ekran görüntülerindeki tarih damgasını atıyor. macOS dosyayı
    ///    "Screenshot 2026-09-19 at 19.18.19" diye adlandırıyor; rafta
    ///    duran her ekran görüntüsünün adı aynı yerden kesildiği için
    ///    liste "Screenshot 2026-09-1…" satırlarına dönüyordu. Tarih
    ///    "eklendi" bilgisiyle zaten var; ayırt eden kısım saat.
    static func displayName(_ item: StorageItem) -> String {
        let base = item.url.deletingPathExtension().lastPathComponent
        guard !base.isEmpty else { return item.name }
        return stripDateStamp(from: base)
    }

    /// "Screenshot 2026-09-19 at 19.18.19" → "Screenshot 19.18.19"
    /// "Ekran Resmi 2026-09-19 19.18.19"  → "Ekran Resmi 19.18.19"
    ///
    /// Tarihi tanımadığı adlara dokunmuyor: kullanıcının kendi koyduğu
    /// isimde geçen bir sayı yanlışlıkla silinmemeli.
    private static func stripDateStamp(from base: String) -> String {
        let tokens = base.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return base }

        let filtered = tokens.filter { token in
            !isISODate(token) && token.lowercased() != "at"
        }
        // Yalnızca gerçekten bir tarih bulunduysa değiştiriliyor.
        guard filtered.count < tokens.count, !filtered.isEmpty else { return base }
        return filtered.joined(separator: " ")
    }

    /// 2026-09-19 biçimi — ekran görüntüsü adlarındaki damganın tamamı.
    private static func isISODate(_ token: String) -> Bool {
        let parts = token.split(separator: "-")
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Kısa tür etiketi: "PNG". Sistemin uzun adı ("PNG görüntüsü") künyeye
    /// sığmıyor ve üç öğe yan yana geldiğinde satırı taşırıyordu.
    static func typeLabel(_ item: StorageItem) -> String {
        let ext = item.url.pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        if !item.typeDescription.isEmpty { return item.typeDescription }
        return L10n.shelfTitle
    }

    /// "PNG · 48 KB · 2 dk önce"
    static func metadata(_ item: StorageItem) -> String {
        [typeLabel(item), SystemFormat.bytes(item.size), relative(item.modifiedAt)]
            .joined(separator: " · ")
    }

    static func relative(_ date: Date) -> String {
        let formatter = Self.relativeFormatter
        formatter.locale = Locale(identifier: L10n.language.rawValue)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Ad ve tür üzerinden arama. Yol aranmıyor: rafta dizin yapısı yok,
    /// eşleşme yalnızca kullanıcının gördüğü metinle olmalı.
    static func matches(_ item: StorageItem, query: String) -> Bool {
        displayName(item).localizedCaseInsensitiveContains(query)
            || item.name.localizedCaseInsensitiveContains(query)
            || typeLabel(item).localizedCaseInsensitiveContains(query)
    }

    /// `RelativeDateTimeFormatter` Sendable değil; yalnızca görünümlerden
    /// (ana aktör) çağrıldığı için tek örnek yeterli.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

// MARK: - Izgara kartı

/// Rafın varsayılan görünümü. Kartın ağırlık merkezi görselin kendisi;
/// ad ve künye altında ince bir şerit — kullanıcı rafta dosya adı değil
/// "şu resim" arıyor.
private struct ShelfGridCard: View {
    let item: StorageItem
    let isSelected: Bool
    let palette: ShelfPalette
    let metrics: ShelfMetrics
    let reduceMotion: Bool
    let removesOnDragOut: Bool
    let actions: ShelfItemActions

    @State private var isHovering = false

    private var cornerRadius: CGFloat { 10 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ShelfThumbnail(
                    item: item,
                    height: metrics.previewHeight,
                    cornerRadius: cornerRadius - 2,
                    symbolSize: metrics.previewHeight * 0.28
                )

                if isHovering {
                    ShelfHoverBar(actions: actions)
                        .padding(5)
                        .transition(.opacity)
                }
            }
            .padding(3)

            VStack(alignment: .leading, spacing: 2) {
                Text(ShelfFormat.displayName(item))
                    .font(.app(size: metrics.nameSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(ShelfFormat.metadata(item))
                    .font(.app(size: metrics.metaSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 9)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isHovering ? palette.card.opacity(1) : palette.hover)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.8) : palette.border,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        // Üzerine gelince kart yüzeyden bir tık kalkıyor: sürüklenebilir
        // olduğunu söyleyen tek ipucu bu.
        .shadow(color: .black.opacity(isHovering ? 0.22 : 0), radius: isHovering ? 7 : 0, y: isHovering ? 3 : 0)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(count: 2, perform: actions.preview)
        .onTapGesture(perform: actions.select)
        .onDrag {
            let provider = ShelfDragHandoff.provider(for: item, removesOnDragOut: removesOnDragOut)
            if removesOnDragOut {
                _Concurrency.Task { @MainActor in actions.draggedOut() }
            }
            return provider
        } preview: {
            ShelfThumbnail(item: item, height: metrics.previewHeight)
                .frame(width: metrics.cardMinWidth)
        }
        .contextMenu { ShelfContextMenu(actions: actions) }
        .help(item.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ShelfFormat.displayName(item)), \(ShelfFormat.metadata(item))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Liste satırı

/// Çok sayıda dosya biriktiğinde ızgara yerine: aynı bilgiler sütunlarda,
/// tek bakışta taranabilir.
private struct ShelfListRow: View {
    let item: StorageItem
    let isSelected: Bool
    let palette: ShelfPalette
    let reduceMotion: Bool
    let removesOnDragOut: Bool
    let actions: ShelfItemActions

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ShelfThumbnail(item: item, height: 30, cornerRadius: 6, symbolSize: 14, inset: 3)
                .frame(width: 42)

            Text(ShelfFormat.displayName(item))
                .font(.app(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if isHovering {
                ShelfHoverBar(actions: actions)
                    .transition(.opacity)
            } else {
                Text(ShelfFormat.typeLabel(item))
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Text(SystemFormat.bytes(item.size))
                    .font(.app(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .trailing)

                Text(ShelfFormat.relative(item.modifiedAt))
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 84, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovering ? palette.card : .clear))
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: actions.preview)
        .onTapGesture(perform: actions.select)
        .onDrag {
            let provider = ShelfDragHandoff.provider(for: item, removesOnDragOut: removesOnDragOut)
            if removesOnDragOut {
                _Concurrency.Task { @MainActor in actions.draggedOut() }
            }
            return provider
        }
        .contextMenu { ShelfContextMenu(actions: actions) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ShelfFormat.displayName(item)), \(ShelfFormat.metadata(item))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Hızlı önizleme

/// Sayfanın içinde açılan önizleme. Ayrı bir pencere ya da sistemin genel
/// iletişim kutusu yerine burada duruyor: görüntü büyük ve kırpılmamış,
/// altında dosyanın kimliği ve iki sık eylem.
private struct ShelfQuickLook: View {
    let item: StorageItem
    let palette: ShelfPalette
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            // Arkadaki raf görünür ama geri planda: tıklayınca kapanıyor.
            Rectangle()
                .fill(.black.opacity(0.45))
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                preview
                Divider().opacity(0.4)
                footer
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.card)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.38), radius: 28, y: 10)
            .padding(24)
        }
        .task(id: item.id) { await load() }
        // Esc ile kapanıyor — macOS'ta bir örtünün kapanma yolu budur.
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Label(L10n.shelfBackToShelf, huge: .back, size: 12)
                    .font(.app(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: onCopy) { HugeIcon(name: .copy, size: 13) }
                .buttonStyle(.plain)
                .help(L10n.shelfCopy)

            Menu {
                Button { onReveal() } label: { Label(L10n.revealInFinder, huge: .folder) }
                Divider()
                Button { onRemove() } label: { Label(L10n.removeFromShelf, huge: .trash) }
                Button(role: .destructive) { onDelete() } label: {
                    Label(L10n.shelfDeleteForever, huge: .trash)
                }
            } label: {
                HugeIcon(name: .more, size: 13)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button(action: onClose) { HugeIcon(name: .close, size: 13) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(L10n.close)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var preview: some View {
        ZStack {
            palette.well

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
            } else {
                VStack(spacing: 8) {
                    HugeIcon(name: item.kind.hugeIcon, size: 44)
                        .foregroundStyle(.tertiary)
                    Text(ShelfFormat.typeLabel(item))
                        .font(.app(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.app(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(ShelfFormat.metadata(item))
                    .font(.app(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(L10n.shelfCopy, action: onCopy)
                .controlSize(.small)
            Button(L10n.revealInFinder, action: onReveal)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func load() async {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        image = await ThumbnailProvider.shared.thumbnail(for: item, size: 1024, scale: scale)
    }
}
