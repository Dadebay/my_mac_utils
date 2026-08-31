import AppKit
import GlassDoKit
import SwiftData
import SwiftUI

/// Klasör rafı — panelin içindeki küçük dosya alanının giriş ekranı.
///
/// İki durumu var: klasör listesi ve açılmış bir klasörün tarayıcısı.
/// İkisi de aynı çerçeveyi dolduruyor, yani panel klasör açılırken yerinden
/// oynamıyor; yalnızca içerik yana kayıyor. Liste sola çıkıp soldan geri
/// geliyor, tarayıcı sağdan girip sağa çıkıyor — bir şey nereye gittiyse
/// oradan dönüyor.
struct PanelFolderShelfView: View {
    /// Kenar panelinde `true` (sabit 329 pt yüzey), ana pencerede `false`
    /// (pencere genişliğine uyan, okunur genişlikte sınırlanan sayfa).
    var isCompact = true

    @Query(sort: [SortDescriptor(\FolderBookmark.sortIndex)]) private var folders: [FolderBookmark]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var openedFolderID: UUID?
    @State private var isCreating = false
    @State private var draftName = ""
    @State private var renamingID: UUID?
    @State private var renameDraft = ""
    @State private var summaries: [UUID: FolderSummary] = [:]
    @State private var pendingRemoval: FolderBookmark?
    @State private var errorMessage: String?
    @State private var isTargeted = false
    @FocusState private var isDraftFocused: Bool

    private var openedFolder: FolderBookmark? {
        folders.first { $0.id == openedFolderID }
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.36, dampingFraction: 1.0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let openedFolder {
                PanelFolderBrowserView(folder: openedFolder, isCompact: isCompact) {
                    withAnimation(motion) { openedFolderID = nil }
                }
                .transition(
                    reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
                )
            } else {
                shelf
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
                    )
            }
        }
        .folderSurfaceFrame(isCompact: isCompact)
        // Kayan görünümler yüzeyin dışına taşmasın.
        .clipped()
        .animation(motion, value: openedFolderID)
        .navigationTitle(L10n.folders)
    }

    // MARK: - Liste

    private var shelf: some View {
        VStack(alignment: .leading, spacing: Layout.tightGutter) {
            header

            if let errorMessage {
                errorBanner(errorMessage)
            }

            Divider().opacity(0.25)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(folders) { folder in
                        row(folder)
                            .transition(
                                reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
                            )
                    }
                    if folders.isEmpty, !isCreating { emptyState }
                }
                .animation(motion, value: folders.count)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .padding(14)
        .folderSurfaceFrame(isCompact: isCompact)
        .background {
            if isTargeted {
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted.animation(motion), perform: handleDrop)
        .task(id: folders.count) { await refreshSummaries() }
        .alert(
            pendingRemoval.map {
                $0.isManagedStorage
                    ? L10n.trashConfirmTitle($0.name)
                    : L10n.removeLinkConfirmTitle($0.name)
            } ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { folder in
            Button(L10n.cancel, role: .cancel) { pendingRemoval = nil }
            Button(
                folder.isManagedStorage ? L10n.moveToTrash : L10n.removeLink,
                role: .destructive
            ) {
                pendingRemoval = nil
                remove(folder)
            }
        } message: { folder in
            Text(folder.isManagedStorage ? L10n.trashConfirmMessage : L10n.removeLinkConfirmMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }

            Text(L10n.folders)
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 4)

            Text("\(folders.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())

            Menu {
                Button(L10n.linkExistingFolder, action: linkExistingFolder)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .accessibilityLabel(L10n.linkExistingFolder)
        }
    }

    private func row(_ folder: FolderBookmark) -> some View {
        FolderRow(
            folder: folder,
            summary: summaries[folder.id],
            isRenaming: renamingID == folder.id,
            renameDraft: $renameDraft,
            reduceMotion: reduceMotion,
            onOpen: { open(folder) },
            onCommitRename: { commitRename(folder) },
            onCancelRename: { renamingID = nil },
            onStartRename: {
                renameDraft = folder.name
                renamingID = folder.id
            },
            onReveal: { reveal(folder) },
            onRemove: { pendingRemoval = folder }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.emptyFoldersHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    @ViewBuilder
    private var footer: some View {
        if isCreating {
            createRow
                .transition(
                    reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
                )
        } else {
            Button {
                withAnimation(motion) {
                    draftName = ""
                    isCreating = true
                }
                isDraftFocused = true
            } label: {
                HStack(spacing: Layout.tightGutter) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(L10n.addFolder)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, Layout.tightGutter)
                .padding(.vertical, 6)
            }
            .buttonStyle(.pressScale)
            .transition(.opacity)
        }
    }

    /// Klasör oluşturma panelin içinde: Finder'a ya da bir açma paneline
    /// gitmek, "yeni klasör" gibi küçük bir iş için kullanıcıyı uygulamadan
    /// çıkarmak olurdu.
    private var createRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)

            TextField(L10n.folderNameLabel, text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isDraftFocused)
                .onSubmit(createFolder)
                .onExitCommand(perform: cancelCreate)

            Button(action: createFolder) {
                Text(L10n.create)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.pressScale)
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(action: cancelCreate) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.cancel)
            .accessibilityLabel(L10n.cancel)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(SystemPalette.warning)

            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                withAnimation(motion) { errorMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SystemPalette.warning.opacity(0.12))
        }
        .transition(.opacity)
    }

    // MARK: - Eylemler

    private func open(_ folder: FolderBookmark) {
        guard folder.isManagedStorage else {
            // Bağlanmış klasör uygulamanın alanının dışında; içeriğine
            // buradan dokunulmuyor, Finder'da gösteriliyor.
            reveal(folder)
            return
        }
        withAnimation(motion) { openedFolderID = folder.id }
    }

    private func reveal(_ folder: FolderBookmark) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
    }

    private func createFolder() {
        do {
            let service = try ManagedStorageService.default()
            let created = try service.createFolder(named: draftName)

            let bookmark = FolderBookmark(
                path: created.url.path,
                name: created.name,
                isManagedStorage: true
            )
            bookmark.sortIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
            context.insert(bookmark)
            try context.save()

            withAnimation(motion) {
                draftName = ""
                isCreating = false
                errorMessage = nil
            }
        } catch {
            withAnimation(motion) { errorMessage = error.localizedDescription }
        }
    }

    private func cancelCreate() {
        withAnimation(motion) {
            isCreating = false
            draftName = ""
        }
    }

    private func commitRename(_ folder: FolderBookmark) {
        defer { renamingID = nil }
        do {
            // Dizin adı UUID olduğu için yeniden adlandırma diskte hiçbir
            // şeyi taşımıyor; yalnızca görünen ad değişiyor.
            folder.name = try ManagedStorageService.sanitized(folderName: renameDraft)
            try context.save()
        } catch {
            withAnimation(motion) { errorMessage = error.localizedDescription }
        }
    }

    /// Yönetilen klasör Çöp Kutusu'na taşınıyor; bağlanmış klasör yalnızca
    /// listeden çıkıyor — kullanıcının kendi diskindeki klasöre dokunmak
    /// bu düğmenin işi değil.
    private func remove(_ folder: FolderBookmark) {
        if folder.isManagedStorage {
            let path = folder.path
            do {
                let service = try ManagedStorageService.default()
                try service.moveToTrash(URL(fileURLWithPath: path))
            } catch {
                withAnimation(motion) { errorMessage = error.localizedDescription }
                return
            }
        }

        if openedFolderID == folder.id { openedFolderID = nil }
        context.delete(folder)
        try? context.save()
    }

    private func linkExistingFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        link(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _Concurrency.Task {
            guard let url = await provider.loadFileURL(), url.hasDirectoryPath else { return }
            link(url)
        }
        return true
    }

    private func link(_ url: URL) {
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        let bookmark = FolderBookmark(path: url.path, name: url.lastPathComponent)
        bookmark.sortIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        context.insert(bookmark)
        try? context.save()
    }

    /// Dosya sayısı ve boyut diskten okunuyor; ana iş parçacığında değil.
    private func refreshSummaries() async {
        let managed: [(id: UUID, path: String)] = folders
            .filter(\.isManagedStorage)
            .map { (id: $0.id, path: $0.path) }
        guard !managed.isEmpty, let service = try? ManagedStorageService.default() else { return }

        let result = await _Concurrency.Task.detached(priority: .utility) {
            var output: [UUID: FolderSummary] = [:]
            for folder in managed {
                let summary = service.summary(of: URL(fileURLWithPath: folder.path))
                output[folder.id] = FolderSummary(count: summary.count, size: summary.size)
            }
            return output
        }.value

        summaries = result
    }
}

struct FolderSummary: Sendable, Equatable {
    let count: Int
    let size: UInt64
}

// MARK: - Satır

private struct FolderRow: View {
    let folder: FolderBookmark
    let summary: FolderSummary?
    let isRenaming: Bool
    @Binding var renameDraft: String
    let reduceMotion: Bool
    let onOpen: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onStartRename: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                Image(systemName: folder.isManagedStorage ? "folder.fill" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(folder.isManagedStorage ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }

                if isRenaming {
                    TextField("", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .focused($isRenameFocused)
                        .onSubmit(onCommitRename)
                        .onExitCommand(perform: onCancelRename)
                        .task { isRenameFocused = true }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if folder.isManagedStorage, !isRenaming {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.075 : 0.03))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale(0.98))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.14), value: isHovering)
        .contextMenu {
            Button(L10n.open, action: onOpen)
            Button(L10n.rename, action: onStartRename)
            Button(L10n.revealInFinder, action: onReveal)
            Divider()
            Button(
                folder.isManagedStorage ? L10n.moveToTrash : L10n.removeLink,
                role: .destructive,
                action: onRemove
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name), \(subtitle)")
    }

    private var subtitle: String {
        guard folder.isManagedStorage else {
            // Bağlanmış klasörde dosya sayısı okunmuyor: dizin uygulamanın
            // alanının dışında ve her açılışta taramak pahalı olurdu.
            return L10n.linkExistingFolder
        }
        guard let summary else { return L10n.fileCountLabel(0) }
        guard summary.count > 0 else { return L10n.emptyFolder }
        return "\(L10n.fileCountLabel(summary.count)) • \(SystemFormat.bytes(summary.size))"
    }
}

// MARK: - Yüzey ölçüsü

extension View {
    /// Klasör yüzeyi iki yerde yaşıyor: kenar panelinde sabit 329 pt'lik bir
    /// pano, ana pencerede pencereyle birlikte büyüyen bir sayfa. Ölçü kararı
    /// tek yerde duruyor ki iki görünüm birbirinden kaymasın.
    @ViewBuilder
    func folderSurfaceFrame(isCompact: Bool) -> some View {
        if isCompact {
            frame(
                width: PanelSettings.panelWidth,
                height: PanelSettings.effectivePanelHeight,
                alignment: .top
            )
        } else {
            // Geniş pencerede satırlar sayfanın karşı ucuna kadar uzayıp
            // okunmaz hâle gelmesin.
            frame(maxWidth: 620, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
