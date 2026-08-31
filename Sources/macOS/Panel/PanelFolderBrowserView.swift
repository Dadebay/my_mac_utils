import AVKit
import AppKit
import GlassDoKit
import SwiftUI
import UniformTypeIdentifiers

/// Yönetilen bir klasörün panel içindeki tarayıcısı.
///
/// Panelin kendisi yer değiştirmiyor: bu görünüm klasör listesiyle aynı
/// çerçeveyi dolduruyor, yalnızca içerik kayarak değişiyor. Hiçbir eylem
/// başka bir uygulama açmıyor — önizleme de, oynatma da panelin içinde.
struct PanelFolderBrowserView: View {
    let folder: FolderBookmark
    /// Kenar panelinde sabit panel ölçüsü, ana pencerede kullanılabilir alan.
    var isCompact = true
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var items: [StorageItem] = []
    @State private var selection: StorageItem?
    @State private var previewItem: StorageItem?
    @State private var pendingTrash: StorageItem?
    @State private var errorMessage: String?
    @State private var isTargeted = false
    @State private var importedCount = 0
    @State private var importTotal = 0

    private var directory: URL { URL(fileURLWithPath: folder.path) }

    /// Kritik sönümlü: liste kendiliğinden değişiyor, kullanıcının taşıdığı
    /// bir momentum yok. Reduce Motion açıkken yalnızca kısa bir sönümlenme.
    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.36, dampingFraction: 1.0)
    }

    /// Satır giriş/çıkışı: yerinde belirip yerinde sönüyor, liste boşluğu
    /// yayla kapatıyor. Reduce Motion'da ölçek kalkıyor, yalnızca sönümlenme.
    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var isImporting: Bool { importTotal > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isImporting {
                importProgress
            }

            if let errorMessage {
                errorBanner(errorMessage)
            }

            Divider().opacity(0.25)

            content
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
        .overlay {
            if let previewItem {
                FilePreviewOverlay(item: previewItem, reduceMotion: reduceMotion) {
                    withAnimation(motion) { self.previewItem = nil }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .task(id: folder.path) { await reload() }
        .alert(
            pendingTrash.map { L10n.trashConfirmTitle($0.name) } ?? "",
            isPresented: Binding(
                get: { pendingTrash != nil },
                set: { if !$0 { pendingTrash = nil } }
            ),
            presenting: pendingTrash
        ) { item in
            Button(L10n.cancel, role: .cancel) { pendingTrash = nil }
            Button(L10n.moveToTrash, role: .destructive) {
                pendingTrash = nil
                _Concurrency.Task { await moveToTrash(item) }
            }
        } message: { _ in
            Text(L10n.trashConfirmMessage)
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.folders)

            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(L10n.fileCountLabel(items.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            Spacer(minLength: 4)

            Button(action: pickFiles) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text(L10n.addFiles)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .help(L10n.addFiles)
        }
    }

    private var importProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.copyingFiles)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ProgressView(value: Double(importedCount), total: Double(max(importTotal, 1)))
                .progressViewStyle(.linear)
                .controlSize(.small)
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
        .transition(rowTransition)
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(items) { item in
                        FileRow(
                            item: item,
                            isSelected: selection == item,
                            reduceMotion: reduceMotion,
                            onOpen: { open(item) },
                            onSelect: { select(item) },
                            onReveal: { reveal(item) },
                            onTrash: { pendingTrash = item }
                        )
                        .transition(rowTransition)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Panel odak alabildiğinde boşluk seçili dosyayı önizler.
            .focusable()
            .onKeyPress(.space) {
                guard let selection else { return .ignored }
                open(selection)
                return .handled
            }
            .animation(motion, value: items)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.emptyFolder)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(L10n.dropFilesHere)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
    }

    // MARK: - Eylemler

    private func select(_ item: StorageItem) {
        selection = item
        // Resimde tek tık doğrudan önizleme açıyor: küçük bir küçük resimden
        // fotoğrafın ne olduğu anlaşılmıyor.
        if item.kind == .image {
            withAnimation(motion) { previewItem = item }
        }
    }

    private func open(_ item: StorageItem) {
        withAnimation(motion) { previewItem = item }
    }

    /// Finder'da göstermek ayrı bir eylem: kullanıcı isteyerek çağırıyor,
    /// dosyaya dokununca kendiliğinden olmuyor.
    private func reveal(_ item: StorageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func moveToTrash(_ item: StorageItem) async {
        let service = ManagedStorageService(root: (try? ManagedStorageService.applicationSupportRoot()) ?? directory)
        let failure = await _Concurrency.Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try service.moveToTrash(item.url)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        if let failure {
            withAnimation(motion) { errorMessage = failure }
            return
        }
        if selection == item { selection = nil }
        if previewItem == item { previewItem = nil }
        await reload()
    }

    private func pickFiles() {
        // Sistem sheet'i; Finder uygulamasına geçiş yok.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        _Concurrency.Task { await importFiles(urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        _Concurrency.Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await provider.loadFileURL() { urls.append(url) }
            }
            guard !urls.isEmpty else { return }
            await importFiles(urls)
        }
        return true
    }

    // MARK: - Veri

    private func reload() async {
        let directory = self.directory
        let service = ManagedStorageService(
            root: (try? ManagedStorageService.applicationSupportRoot()) ?? directory
        )

        // Dizin okuma ana iş parçacığında yapılmıyor: klasör kalabalıksa
        // panel donardı.
        let loaded = await _Concurrency.Task.detached(priority: .userInitiated) {
            (try? service.contents(of: directory)) ?? []
        }.value

        withAnimation(motion) { items = loaded }
    }

    private func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        let directory = self.directory
        let service = ManagedStorageService(
            root: (try? ManagedStorageService.applicationSupportRoot()) ?? directory
        )

        withAnimation(motion) {
            errorMessage = nil
            importTotal = urls.count
            importedCount = 0
        }

        var failures: [String] = []
        for url in urls {
            let failure = await _Concurrency.Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try service.importFile(at: url, into: directory)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            if let failure, !failures.contains(failure) { failures.append(failure) }
            importedCount += 1
        }

        await reload()

        withAnimation(motion) {
            importTotal = 0
            importedCount = 0
            // Sessizce başarısız olmuyor: klasör bırakıldığında da,
            // kopyalama patladığında da sebebi yazıyor.
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }
}

// MARK: - Satır

private struct FileRow: View {
    let item: StorageItem
    let isSelected: Bool
    let reduceMotion: Bool
    let onOpen: () -> Void
    let onSelect: () -> Void
    let onReveal: () -> Void
    let onTrash: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    private static let thumbnailSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.14), value: isHovering)
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(L10n.preview, action: onOpen)
            Button(L10n.revealInFinder, action: onReveal)
            Divider()
            Button(L10n.moveToTrash, role: .destructive, action: onTrash)
        }
        .task(id: item.id) { await loadThumbnail() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(subtitle)")
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.primary.opacity(isHovering ? 0.075 : 0.03)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .overlay {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var subtitle: String {
        let size = SystemFormat.bytes(item.size)
        let detail = item.typeDescription.isEmpty
            ? item.modifiedAt.formatted(date: .abbreviated, time: .shortened)
            : item.typeDescription
        return "\(size) • \(detail)"
    }

    private func loadThumbnail() async {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = await ThumbnailProvider.shared.thumbnail(
            for: item,
            size: Self.thumbnailSize,
            scale: scale
        )
        // Simgeyle temsil edilen türlerde küçük resim üretilmiş olsa bile
        // sistem simgesi daha okunur; yalnızca görsel/video/PDF'te kullanılıyor.
        guard [.image, .video, .pdf].contains(item.kind) else { return }
        thumbnail = image
    }
}

// MARK: - Önizleme

/// Panel içi önizleme. Quick Look penceresi yerine burada çiziliyor: kenar
/// paneli etkinleşmeyen (nonactivating) bir `NSPanel` ve `QLPreviewPanel`
/// anahtar pencerenin yanıtlayıcı zincirini istiyor. Önizlemeyi panelin
/// içinde tutmak hem çalışıyor hem de "başka uygulama açılmasın" kuralına
/// uyuyor.
private struct FilePreviewOverlay: View {
    let item: StorageItem
    let reduceMotion: Bool
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            // Modal bir iş: arkası karartılıyor, panel geri plana itiliyor.
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L10n.cancel)
                }

                body(for: item)

                Text(SystemFormat.bytes(item.size))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .padding(14)
        }
        .task(id: item.id) { await prepare() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private func body(for item: StorageItem) -> some View {
        switch item.kind {
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ProgressView().controlSize(.small).frame(height: 120)
            }

        case .audio, .video:
            if let player {
                VideoPlayer(player: player)
                    .frame(height: item.kind == .audio ? 90 : 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ProgressView().controlSize(.small).frame(height: 90)
            }

        default:
            // Diğer türlerde büyük küçük resim: PDF'in ilk sayfası, metin
            // dosyasının önizlemesi buradan geliyor.
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func prepare() async {
        switch item.kind {
        case .audio, .video:
            // Yürütücü yalnızca kullanıcı önizlemeyi açtığında kuruluyor;
            // listedeki her satır için oynatıcı ayırmanın anlamı yok.
            player = AVPlayer(url: item.url)
        default:
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            image = await ThumbnailProvider.shared.thumbnail(for: item, size: 512, scale: scale)
        }
    }
}

// MARK: - Sürükleme yardımcısı

/// `NSItemProvider` Sendable değil. Sağlayıcı ana aktörde kalıyor, yalnızca
/// geri çağırmadan dönen `URL` (Sendable) sınır geçiyor.
@MainActor
extension NSItemProvider {
    /// `NSItemProvider`'ın geri çağırmalı API'sini bekleyebilir hâle getirir.
    func loadFileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
