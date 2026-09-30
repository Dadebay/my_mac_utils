import SwiftUI
import UniformTypeIdentifiers
import GlassDoKit

/// Android telefon sayfası: cihazı tanır ve dosyalarını gezdirir.
///
/// Dosya erişimi `adb` üzerinden (bkz. `AndroidFileService`). Telefonun
/// hangi modda bağlı olduğu en üstte duruyor — yanlış moddayken boş bir
/// dosya listesi göstermek kullanıcıyı uygulamanın bozuk olduğuna
/// inandırırdı.
struct AndroidTransferView: View {
    @State private var monitor = AndroidDeviceMonitor.shared
    /// Her cihaz için ayrı gezgin: telefon değişince liste sıfırlanmalı.
    @State private var browsers: [String: AndroidBrowserModel] = [:]

    var body: some View {
        Group {
            if monitor.isUnavailable {
                message(
                    symbol: "exclamationmark.triangle",
                    title: L10n.androidUSBUnavailableTitle,
                    detail: L10n.androidUSBUnavailableDetail
                )
            } else if let device = monitor.devices.first {
                deviceScreen(device)
            } else {
                emptyState
            }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .pageSubtitle(monitor.devices.first?.displayName ?? L10n.androidNoDeviceTitle)
    }

    // MARK: - Cihaz ekranı

    @ViewBuilder
    private func deviceScreen(_ device: AndroidDevice) -> some View {
        // Yükseklik açıkça pencereye bağlanıyor. Bağlanmayınca yığının
        // ideal yüksekliği dosya sayısıyla büyüyor ve pencereyi aşağı
        // doğru uzatıyordu: kenar çubuğu ekrandan taşıp başlığı ile alt
        // şeridi görünmez oluyordu (kullanıcı bildirdi).
        VStack(spacing: 0) {
            deviceHeader(device)

            Divider().opacity(0.4)

            if !AndroidFileService.isAvailable {
                message(
                    symbol: "wrench.and.screwdriver",
                    title: L10n.androidAdbMissingTitle,
                    detail: L10n.androidAdbMissing
                )
            } else if !device.hasDebugging {
                message(
                    symbol: "lock",
                    title: L10n.androidDebuggingNeededTitle,
                    detail: L10n.androidDebuggingNeededDetail
                )
            } else if let serial = device.serial {
                browser(for: serial)
            } else {
                message(
                    symbol: "questionmark.circle",
                    title: L10n.androidNoSerialTitle,
                    detail: L10n.androidNoSerialDetail
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func browser(for serial: String) -> some View {
        let model = browsers[serial] ?? {
            let created = AndroidBrowserModel(serial: serial)
            // Görünüm kurulurken durum sözlüğünü değiştirmek SwiftUI'da
            // aynı karede yeniden çizim uyarısı veriyor; bir sonraki tura
            // bırakılıyor.
            DispatchQueue.main.async {
                browsers[serial] = created
                created.load()
            }
            return created
        }()
        return AndroidFileBrowser(model: model)
            .id(serial)
    }

    private func deviceHeader(_ device: AndroidDevice) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.app(.title, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    badge(on: device.hasFileTransfer, text: L10n.androidBadgeFileTransfer)
                    badge(on: device.hasDebugging, text: L10n.androidBadgeDebugging)
                }
            }

            Spacer(minLength: 16)

            // Depolama en sık sorulan şey: ne kadar yer var, ne kadar
            // dolabilir. Rakam ve çubuk birlikte — çubuk oranı bir
            // bakışta, rakam kesin değeri veriyor.
            if let storage = browsers[device.serial ?? ""]?.storage {
                storageSummary(storage)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func storageSummary(_ storage: AndroidStorage) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 5) {
                Text(SystemFormat.bytes(storage.free))
                    .font(.app(.title, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
                Text(L10n.androidStorageFreeSuffix)
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
            }

            // Çubuk dolu oranı gösteriyor; dolu kısım doldukça kızarıyor.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(storage.usedFraction > 0.9 ? Color.red : Color.accentColor)
                        .frame(width: max(geo.size.width * storage.usedFraction, 3))
                }
            }
            .frame(width: 190, height: 5)

            Text(L10n.androidStorageUsedOfTotal(
                SystemFormat.bytes(storage.used), SystemFormat.bytes(storage.total)
            ))
            .font(.app(.micro))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }

    private func badge(on: Bool, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 9, weight: .bold))
            Text(text).font(.app(.micro, weight: .medium))
        }
        .foregroundStyle(on ? Color.green : Color.secondary)
    }

    // MARK: - Durum ekranları

    /// Durum ekranları kaydırılabilir bir kabın içinde.
    ///
    /// Sarmalayan görünüm olmadan sayfanın *en küçük* yüksekliği patlıyor:
    /// `fixedSize(vertical:)` taşıyan bir metin, minimum ölçülürken sıfır
    /// genişlik önerisiyle kelime kelime sarılıyor ve yüzlerce piksellik
    /// bir alt sınır bildiriyor. Pencere `.windowResizability(.contentMinSize)`
    /// ile kurulu olduğundan bu alt sınır pencereye dayatılıyor; pencere
    /// büyüyemeyince içerik iki ucundan kırpılıyor — kenar çubuğunun
    /// başlığı üstte, ilerleme şeridi altta kayboluyordu.
    ///
    /// `ScrollView`'ın kendi minimumu küçük olduğu için zincir orada
    /// kesiliyor. Sayfanın geri kalanı (Genel Bakış, Ağ, Ayarlar, Raf)
    /// zaten aynı deseni kullanıyor.
    private func stateScreen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        stateScreen {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.androidNoDeviceTitle)
                .font(.app(.title, weight: .semibold))

            Text(L10n.androidNoDeviceDetail)
                .font(.app(.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Genişlik önce sınırlanıyor, sarma ölçümü sonra.
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        stateScreen {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(title).font(.app(.title, weight: .semibold))
                Text(detail)
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }
}

// MARK: - Dosya gezgini

private struct AndroidFileBrowser: View {
    @Bindable var model: AndroidBrowserModel
    @State private var isDropTarget = false
    /// Yerleşim tercihi kalıcı: fotoğraf klasörlerinde ızgara, belge
    /// klasörlerinde liste isteniyor ve seçim her açılışta sıfırlanmamalı.
    @AppStorage("android.browser.usesGrid") private var usesGrid = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let error = model.errorMessage {
                errorBar(error)
            }

            Divider().opacity(0.4)

            ZStack {
                fileList

                if model.isLoading, model.files.isEmpty {
                    ProgressView().controlSize(.small)
                }
                if let busy = model.busyMessage {
                    busyOverlay(busy)
                }
            }
        }
        // Finder'dan sürüklenen dosyalar bulunulan klasöre yükleniyor.
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            loadURLs(from: providers)
            return true
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: model.goUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(!model.canGoUp)
            .help(L10n.androidGoUp)

            Button { model.load() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L10n.androidRefresh)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(model.breadcrumbs, id: \.path) { crumb in
                        Button(crumb.name) { model.load(path: crumb.path) }
                            .buttonStyle(.plain)
                            .font(.app(.body, weight: crumb.path == model.path ? .semibold : .regular))
                            .foregroundStyle(crumb.path == model.path ? .primary : .secondary)

                        if crumb.path != model.breadcrumbs.last?.path {
                            Text("/").foregroundStyle(.tertiary).font(.app(.body))
                        }
                    }
                }
            }

            Spacer(minLength: 6)

            Text(L10n.shelfItemCount(model.files.count))
                .font(.app(.micro))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            // Izgara/liste: resim klasörlerinde önizleme olmadan hangi
            // dosyanın ne olduğu anlaşılmıyor.
            Picker("", selection: $usesGrid) {
                Image(systemName: "square.grid.2x2").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L10n.androidLayoutHelp)

            Button(action: model.chooseFilesToUpload) {
                Label(L10n.androidSend, systemImage: "arrow.up.doc")
            }
            .help(L10n.androidSendHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .disabled(model.busyMessage != nil)
    }

    private var fileList: some View {
        ScrollView {
            Group {
                if usesGrid {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(model.files) { file in
                            AndroidFileTile(
                                file: file,
                                thumbnail: model.thumbnails[file.path],
                                onOpen: { model.open(file) },
                                onDownload: { model.download(file) }
                            )
                            // Önizleme yalnızca kart ekrana girince
                            // çekiliyor: klasördeki her fotoğrafı peşinen
                            // indirmek telefonu da ağı da boşuna yorardı.
                            .onAppear { model.requestThumbnail(for: file) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(model.files) { file in
                            AndroidFileRow(
                                file: file,
                                onOpen: { model.open(file) },
                                onDownload: { model.download(file) }
                            )
                        }
                    }
                }

                if model.files.isEmpty, !model.isLoading, model.errorMessage == nil {
                    Text(L10n.androidEmptyFolder)
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(8)
        }
    }

    private func errorBar(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(SystemPalette.warning)
            Text(text)
                .font(.app(.micro))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button { model.dismissError() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SystemPalette.warning.opacity(0.12))
    }

    private func busyOverlay(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.app(.body)).foregroundStyle(.secondary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
    }

    /// Sürüklenen öğelerin yollarını çözüp yüklemeye veriyor.
    private func loadURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated { model.upload(urls) }
        }
    }
}

private struct AndroidFileRow: View {
    let file: AndroidFile
    let onOpen: () -> Void
    let onDownload: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 11) {
            // İkon bir rozetin içinde: klasörle dosya arasındaki fark
            // satır listesinde tek bir küçük simgeden okunmuyordu.
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: file.isOpenable ? "folder.fill" : icon(for: file.name))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.app(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.modified)
                    .font(.app(.micro))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            // Boyut sabit genişlikte ve sağa dayalı: sayılar sütun hâlinde
            // hizalanmazsa göz her satırda yeniden yer arıyor.
            Text(file.isOpenable ? "" : SystemFormat.bytes(file.size))
                .font(.app(.micro))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            if file.isOpenable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }

            // İndirme düğmesi yalnızca satırın üstündeyken: her satırda
            // duran bir düğme listeyi düğme tarlasına çevirirdi.
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help(L10n.androidDownloadHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onOpen() }
    }

    /// Klasörler vurgu renginde, dosyalar türüne göre: resim, video, ses
    /// ve arşivler listede birbirinden renkle ayrılıyor.
    private var tint: Color {
        if file.isOpenable { return .accentColor }
        switch (file.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return Color(red: 0.36, green: 0.72, blue: 0.98)
        case "mp4", "mov", "mkv", "avi", "3gp": return Color(red: 0.78, green: 0.48, blue: 0.96)
        case "mp3", "wav", "m4a", "ogg", "flac": return Color(red: 0.98, green: 0.58, blue: 0.32)
        case "zip", "rar", "7z", "tar", "gz": return Color(red: 0.92, green: 0.74, blue: 0.30)
        case "apk": return Color(red: 0.42, green: 0.80, blue: 0.52)
        case "pdf": return Color(red: 0.94, green: 0.40, blue: 0.36)
        default: return .secondary
        }
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": "photo"
        case "mp4", "mov", "mkv", "avi", "3gp": "film"
        case "mp3", "wav", "m4a", "ogg", "flac": "music.note"
        case "pdf": "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz": "doc.zipper"
        case "apk": "shippingbox"
        case "txt", "md", "json", "xml", "csv": "doc.text"
        default: "doc"
        }
    }
}

/// Izgara görünümündeki tek kart: üstte önizleme, altında ad ve boyut.
private struct AndroidFileTile: View {
    let file: AndroidFile
    let thumbnail: NSImage?
    let onOpen: () -> Void
    let onDownload: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                if let thumbnail {
                    // Tamamı görünüyor, kırpılmıyor: telefon ekran
                    // görüntüleri dik ve dar; kareye doldurulunca üstü ile
                    // altı kesiliyor, hangi ekran olduğu anlaşılmıyordu.
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                } else if file.isImage {
                    // Resim çekilene kadar bekleme göstergesi: boş bir kutu
                    // "önizleme yok" gibi okunuyordu.
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: file.isOpenable ? "folder.fill" : icon)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(file.isOpenable ? Color.accentColor : Color.secondary)
                }

                if isHovering, !file.isOpenable {
                    VStack {
                        HStack {
                            Spacer(minLength: 0)
                            Button(action: onDownload) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 15))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                            .help(L10n.androidDownloadHelp)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                }
            }
            .frame(height: 124)
            .clipped()

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.app(.micro, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.isOpenable ? file.modified : SystemFormat.bytes(file.size))
                    .font(.app(.micro))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.name)
    }

    private var icon: String {
        switch (file.name as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "3gp": "film"
        case "mp3", "wav", "m4a", "ogg", "flac": "music.note"
        case "pdf": "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz": "doc.zipper"
        case "apk": "shippingbox"
        case "txt", "md", "json", "xml", "csv": "doc.text"
        default: "doc"
        }
    }
}
