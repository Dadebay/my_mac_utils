import AppKit
import GlassDoKit
import ImageCaptureCore
import SwiftUI

/// iPhone'daki fotoğraf ve videoları (DCIM) Mac'e aktaran gezgin.
///
/// iPhone, Android gibi `adb`/MTP ile açılmıyor: Apple yalnızca kamera
/// rulosunu PTP üzerinden ImageCaptureCore ile paylaşıyor. Telefonun kilidi
/// açık olmalı ve "Bu Bilgisayara Güven" onaylanmış olmalı.
/// `ICCameraFile` Sendable değil; indirme yalnızca bu dosyayı ImageCaptureCore'a veriyor.
struct UncheckedFile: @unchecked Sendable { let file: ICCameraFile }

@MainActor
@Observable
final class IPhoneBrowserModel: NSObject {
    private(set) var files: [ICCameraFile] = []
    private(set) var statusText = ""
    private(set) var isReady = false
    private(set) var isLocked = false
    private(set) var errorMessage: String?
    private(set) var progress: (done: Int, total: Int)?
    private(set) var lastDestination: URL?
    var selection: Set<ICCameraFile> = []

    struct Folder: Identifiable, Hashable {
        let id: String
        let name: String
        let symbol: String
        let files: [ICCameraFile]
    }

    /// Açık klasör; `nil` ise kök (klasör listesi) gösteriliyor.
    var openFolderID: String? {
        didSet { selection = [] }
    }

    static func isVideo(_ file: ICCameraFile) -> Bool {
        let name = (file.name ?? "").lowercased()
        return [".mov", ".mp4", ".m4v"].contains { name.hasSuffix($0) }
    }

    /// Kök klasörler: tüm fotoğraflar, tüm videolar ve ay ay gruplar.
    var folders: [Folder] {
        let photos = files.filter { !Self.isVideo($0) }
        let videos = files.filter(Self.isVideo)
        var result: [Folder] = []
        if !photos.isEmpty {
            result.append(Folder(id: "photos", name: L10n.s("Tüm Fotoğraflar", "All Photos", "Все фото"), symbol: "photo.on.rectangle", files: photos))
        }
        if !videos.isEmpty {
            result.append(Folder(id: "videos", name: L10n.s("Tüm Videolar", "All Videos", "Все видео"), symbol: "video", files: videos))
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: files) { file -> Date in
            let date = file.creationDate ?? .distantPast
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
        for month in grouped.keys.sorted(by: >) {
            result.append(Folder(
                id: "m-\(month.timeIntervalSince1970)",
                name: month.formatted(.dateTime.month(.wide).year()),
                symbol: "folder",
                files: grouped[month] ?? []
            ))
        }
        return result
    }

    var openFolder: Folder? { folders.first { $0.id == openFolderID } }

    private(set) var thumbnails: [ICCameraFile: NSImage] = [:]
    private var pendingThumbnails: Set<ICCameraFile> = []

    func requestThumbnail(for file: ICCameraFile) {
        guard thumbnails[file] == nil, !pendingThumbnails.contains(file) else { return }
        pendingThumbnails.insert(file)
        file.requestThumbnail()
    }

    private var camera: ICCameraDevice?
    private let browser = ICDeviceBrowser()

    func start() {
        guard browser.delegate == nil else { return }
        statusText = L10n.s("iPhone aranıyor…", "Looking for iPhone…", "Поиск iPhone…")
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        ) ?? .camera
        browser.start()
    }

    func stop() {
        browser.stop()
        browser.delegate = nil
        camera?.requestCloseSession()
        camera = nil
    }

    fileprivate func attach(_ device: ICCameraDevice) {
        guard camera == nil else { return }
        camera = device
        device.delegate = self
        statusText = L10n.s("Bağlanıyor…", "Connecting…", "Подключение…")
        device.requestOpenSession()
    }

    // MARK: - Aktarma

    func importSelected() { runImport(Array(selection)) }

    private func runImport(_ items: [ICCameraFile]) {
        guard !items.isEmpty, progress == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.s("Buraya kaydet", "Save here", "Сохранить сюда")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        errorMessage = nil
        progress = (0, items.count)
        _Concurrency.Task { @MainActor in
            var failed = 0
            for (index, file) in items.enumerated() {
                if await Self.download(UncheckedFile(file: file), to: destination) == false { failed += 1 }
                progress = (index + 1, items.count)
            }
            progress = nil
            lastDestination = destination
            if failed > 0 {
                errorMessage = L10n.s(
                    "\(failed) dosya aktarılamadı.",
                    "\(failed) files could not be transferred.",
                    "Не удалось перенести файлов: \(failed)."
                )
            }
            NSWorkspace.shared.open(destination)
        }
    }

    /// `requestDownload` tamamlanma bloğunu arka plan kuyruğunda çağırıyor;
    /// ana aktöre bağlı bir blok orada çalışınca uygulama çöküyordu.
    /// Bu yüzden bu fonksiyon hiçbir aktöre bağlı değil.
    private nonisolated static func download(_ box: UncheckedFile, to directory: URL) async -> Bool {
        let file = box.file
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: directory,
                .overwrite: true,
            ]
            file.requestDownload(options: options) { @Sendable _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func refreshState(_ device: ICCameraDevice) {
        files = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        isLocked = device.isAccessRestrictedAppleDevice
        if files.isEmpty {
            statusText = isLocked
                ? L10n.s(
                    "iPhone'un kilidini açın ve “Bu Bilgisayara Güven”e dokunun.",
                    "Unlock your iPhone and tap “Trust This Computer”.",
                    "Разблокируйте iPhone и нажмите «Доверять этому компьютеру»."
                )
                : L10n.s("Fotoğraflar okunuyor…", "Reading photos…", "Чтение фото…")
        }
    }
}

extension IPhoneBrowserModel: @preconcurrency ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        do { self.attach(camera) }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        do {
            guard self.camera === device else { return }
            self.camera = nil
            self.files = []
            self.isReady = false
        }
    }
}

extension IPhoneBrowserModel: @preconcurrency ICCameraDeviceDelegate {
    func didRemove(_ device: ICDevice) {}

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        do {
            if let error { self.errorMessage = error.localizedDescription }
            if let camera = device as? ICCameraDevice { self.refreshState(camera) }
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {}

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        do { self.refreshState(camera) }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        do { self.refreshState(camera) }
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {
        guard let thumbnail, let file = item as? ICCameraFile else { return }
        thumbnails[file] = NSImage(cgImage: thumbnail, size: .zero)
    }
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        do { self.refreshState(camera) }
    }
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        do {
            self.isReady = true
            self.refreshState(device)
            if self.files.isEmpty, !self.isLocked {
                self.statusText = L10n.s(
                    "Bu iPhone'da fotoğraf veya video bulunamadı.",
                    "No photos or videos found on this iPhone.",
                    "На этом iPhone нет фото или видео."
                )
            }
        }
    }
    func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        do {
            if let camera = device as? ICCameraDevice { self.refreshState(camera) }
        }
    }
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        do {
            if let camera = device as? ICCameraDevice { self.refreshState(camera) }
        }
    }
}

struct IPhoneTransferView: View {
    let deviceName: String
    @State private var model = IPhoneBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let error = model.errorMessage {
                Text(error).font(.app(.micro)).foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }

            Divider().opacity(0.4)

            if model.files.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: model.isLocked ? "lock" : "iphone.gen3")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(model.statusText)
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let folder = model.openFolder {
                mediaGrid(folder)
            } else {
                folderGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - Araç çubuğu

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let folder = model.openFolder {
                Button { model.openFolderID = nil } label: { Image(systemName: "chevron.left") }
                    .disabled(model.progress != nil)
                Text(L10n.s("Telefon", "Phone", "Телефон")).foregroundStyle(.secondary)
                Text("/").foregroundStyle(.tertiary)
                Text(folder.name).fontWeight(.semibold).lineLimit(1)

                Spacer(minLength: 8)

                if let progress = model.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 140)
                    Text("\(progress.done)/\(progress.total)")
                        .font(.app(.micro)).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(L10n.s("\(model.selection.count) seçili", "\(model.selection.count) selected", "Выбрано: \(model.selection.count)"))
                        .font(.app(.micro)).monospacedDigit().foregroundStyle(.tertiary)

                    let allSelected = model.selection.count == folder.files.count
                    Button(allSelected
                        ? L10n.s("Seçimi kaldır", "Deselect all", "Снять выбор")
                        : L10n.s("Tümünü seç", "Select all", "Выбрать все")) {
                        model.selection = allSelected ? [] : Set(folder.files)
                    }

                    Button {
                        model.importSelected()
                    } label: {
                        Label(L10n.s("Mac'e aktar", "Export to Mac", "Экспорт на Mac"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selection.isEmpty)
                }
            } else {
                Text(L10n.s("Telefon", "Phone", "Телефон")).fontWeight(.semibold)
                Spacer()
                Text(L10n.shelfItemCount(model.files.count))
                    .font(.app(.micro)).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .font(.app(.body))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Klasörler

    private var folderGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(model.folders) { folder in
                    Button { model.openFolderID = folder.id } label: {
                        VStack(spacing: 8) {
                            Image(systemName: folder.symbol)
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Color.accentColor)
                                .frame(height: 50)
                            Text(folder.name)
                                .font(.app(.body, weight: .medium))
                                .lineLimit(1)
                            Text(L10n.shelfItemCount(folder.files.count))
                                .font(.app(.micro))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Klasör içi

    private func mediaGrid(_ folder: IPhoneBrowserModel.Folder) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(folder.files, id: \.self) { file in
                    let selected = model.selection.contains(file)
                    Button {
                        if selected { model.selection.remove(file) } else { model.selection.insert(file) }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Color.primary.opacity(0.08)
                                if let image = model.thumbnails[file] {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Image(systemName: IPhoneBrowserModel.isVideo(file) ? "video" : "photo")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                            }

                            if IPhoneBrowserModel.isVideo(file) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10))
                                    .padding(4)
                                    .foregroundStyle(.white)
                                    .background(Capsule().fill(.black.opacity(0.55)))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    .padding(5)
                            }

                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(selected ? Color.accentColor : .white.opacity(0.8))
                                .shadow(radius: 2)
                                .padding(6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onAppear { model.requestThumbnail(for: file) }
                }
            }
            .padding(10)
        }
    }
}
