import AppKit
import GlassDoKit
import SwiftUI
import UniformTypeIdentifiers

/// Resim dönüştürücü: dosyaları bırak ya da seç, biçimi seç, dönüştür.
@MainActor
@Observable
final class ImageConverterModel {
    struct Item: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var size: Int64 {
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
    }

    var items: [Item] = []
    var format: ConverterFormat = .webp
    var lossless = false
    var quality = 0.85
    var saveNextToOriginals = true
    private(set) var progress: (done: Int, total: Int)?
    private(set) var resultMessage: String?
    private(set) var failures: [String] = []

    var isBusy: Bool { progress != nil }

    func add(_ urls: [URL]) {
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                while let child = contents?.nextObject() as? URL { found.append(child) }
            } else {
                found.append(url)
            }
        }
        let accepted = found.filter {
            ImageConverterService.sourceExtensions.contains($0.pathExtension.lowercased())
        }
        for url in accepted where !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url))
        }
        resultMessage = nil
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func remove(_ item: Item) { items.removeAll { $0 == item } }
    func clear() { items = []; resultMessage = nil; failures = [] }

    func convert() {
        guard !items.isEmpty, !isBusy else { return }
        var folder: URL?
        if !saveNextToOriginals {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = L10n.s("Buraya kaydet", "Save here", "Сохранить сюда")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            folder = url
        }

        let sources = items.map(\.url)
        let format = format, quality = quality, lossless = lossless
        progress = (0, sources.count)
        failures = []
        resultMessage = nil

        _Concurrency.Task { @MainActor in
            var converted: [URL] = []
            for (index, source) in sources.enumerated() {
                let directory = folder ?? source.deletingLastPathComponent()
                let outcome = await _Concurrency.Task.detached(priority: .userInitiated) {
                    Result {
                        try ImageConverterService.convert(source, to: format, quality: quality, lossless: lossless, in: directory)
                    }
                }.value
                switch outcome {
                case .success(let url): converted.append(url)
                case .failure(let error): failures.append(error.localizedDescription)
                }
                progress = (index + 1, sources.count)
            }
            progress = nil
            resultMessage = L10n.s(
                "\(converted.count) dosya \(format.title) olarak kaydedildi.",
                "\(converted.count) files saved as \(format.title).",
                "Сохранено файлов (\(format.title)): \(converted.count)."
            )
            if !converted.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(converted) }
        }
    }
}

struct ImageConverterView: View {
    @State private var model = ImageConverterModel()
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider().opacity(0.4)

            if model.items.isEmpty {
                dropZone
            } else {
                fileList
            }

            if let message = model.resultMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.app(.micro)).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            if !model.failures.isEmpty {
                Text(model.failures.joined(separator: "\n"))
                    .font(.app(.micro)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    _Concurrency.Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6).allowsHitTesting(false)
            }
        }
        .pageSubtitle(L10n.s("PNG, JPEG, WebP, HEIC…", "PNG, JPEG, WebP, HEIC…", "PNG, JPEG, WebP, HEIC…"))
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.s("Biçim", "Format", "Формат")).foregroundStyle(.secondary)
                Picker("", selection: $model.format) {
                    ForEach(ConverterFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 12) {
                if model.format.supportsQuality, !(model.format == .webp && model.lossless) {
                    Text(L10n.s("Kalite", "Quality", "Качество")).foregroundStyle(.secondary)
                    Slider(value: $model.quality, in: 0.1...1)
                        .frame(maxWidth: 200)
                    Text("%\(Int(model.quality * 100))").monospacedDigit().frame(width: 44, alignment: .leading)
                }

                if model.format == .webp {
                    Toggle(L10n.s("Kayıpsız", "Lossless", "Без потерь"), isOn: $model.lossless)
                }

                Spacer(minLength: 8)

                Toggle(
                    L10n.s("Orijinalin yanına kaydet", "Save next to originals", "Сохранять рядом"),
                    isOn: $model.saveNextToOriginals
                )

                Button(L10n.s("Dosya seç", "Choose files", "Выбрать")) { model.chooseFiles() }

                if let progress = model.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 110)
                } else {
                    Button {
                        model.convert()
                    } label: {
                        Label(L10n.s("Dönüştür", "Convert", "Конвертировать"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.items.isEmpty)
                }
            }
        }
        .font(.app(.body))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.s("Resimleri buraya bırak", "Drop images here", "Перетащите изображения сюда"))
                .font(.app(.title, weight: .semibold))
            Text(L10n.s(
                "PNG, JPEG, WebP, HEIC, AVIF, TIFF, GIF, BMP — klasör de bırakabilirsin.",
                "PNG, JPEG, WebP, HEIC, AVIF, TIFF, GIF, BMP — folders work too.",
                "PNG, JPEG, WebP, HEIC, AVIF, TIFF, GIF, BMP — можно и папки."
            ))
            .font(.app(.body)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.shelfItemCount(model.items.count))
                    .font(.app(.micro)).foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.s("Temizle", "Clear", "Очистить")) { model.clear() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            List(model.items) { item in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().frame(width: 22, height: 22)
                    Text(item.url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Text(SystemFormat.bytes(UInt64(max(item.size, 0))))
                        .monospacedDigit().foregroundStyle(.tertiary)
                    Button { model.remove(item) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
                .font(.app(.body))
            }
        }
    }
}
