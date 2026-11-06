import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import libwebp

/// Dönüştürülebilen çıktı biçimleri.
///
/// WebP dışındakileri ImageIO yazıyor; WebP'yi macOS yazamadığı için
/// libwebp'in kodlayıcısı kullanılıyor (okumak ImageIO ile mümkün).
enum ConverterFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, heic, avif, tiff, gif, bmp

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    /// Kalite ayarı anlamlı mı. PNG/GIF/BMP/TIFF kayıpsız ya da paletli.
    var supportsQuality: Bool {
        switch self {
        case .jpeg, .webp, .heic, .avif: true
        default: false
        }
    }

    /// Saydamlığı taşıyamayan biçimler: şeffaf alan beyaza oturtuluyor,
    /// yoksa siyah çıkıyor.
    var flattensAlpha: Bool { self == .jpeg || self == .bmp }

    var utType: UTType? {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: nil
        case .heic: .heic
        case .avif: UTType("public.avif")
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        }
    }
}

enum ImageConverterError: LocalizedError {
    case unreadable(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "\(name) okunamadı."
        case .encodeFailed(let name): "\(name) dönüştürülemedi."
        }
    }
}

enum ImageConverterService {
    /// Uzantısı bu listede olan dosyalar kaynak olarak kabul ediliyor.
    static let sourceExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "tiff", "tif", "gif", "bmp", "avif", "ico",
    ]

    /// Tek dosyayı dönüştürüp yazılan dosyanın adresini döndürür.
    /// `quality` 0...1.
    nonisolated static func convert(
        _ source: URL, to format: ConverterFormat, quality: Double, lossless: Bool = false, in directory: URL
    ) throws -> URL {
        let name = source.lastPathComponent
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw ImageConverterError.unreadable(name) }

        let output = uniqueURL(
            directory.appending(path: source.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(format.fileExtension)
        )

        if format == .webp {
            let data = try encodeWebP(image, quality: quality, lossless: lossless, name: name)
            try data.write(to: output)
            return output
        }

        guard let type = format.utType,
              let destination = CGImageDestinationCreateWithURL(
                output as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImageConverterError.encodeFailed(name) }

        let drawn = format.flattensAlpha ? flattened(image) ?? image : image
        var options: [CFString: Any] = [:]
        if format.supportsQuality {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, drawn, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageConverterError.encodeFailed(name)
        }
        return output
    }

    /// Aynı adda dosya varsa üzerine yazmak yerine "(2)" ekler.
    private nonisolated static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent()
                .appending(path: url.deletingPathExtension().lastPathComponent + " (\(counter))")
                .appendingPathExtension(url.pathExtension)
            counter += 1
        }
        return candidate
    }

    /// Şeffaf alanı beyaza oturtur.
    private nonisolated static func flattened(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private nonisolated static func encodeWebP(
        _ image: CGImage, quality: Double, lossless: Bool, name: String
    ) throws -> Data {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageConverterError.encodeFailed(name) }

        // Bağlam çarpılmış (premultiplied) alfa üretiyor, WebP düz alfa bekliyor.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(min(Int(pixels[index + channel]) * 255 / alpha, 255))
            }
        }

        var encoded: UnsafeMutablePointer<UInt8>?
        let stride = Int32(width * 4)
        let size = pixels.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return lossless
                ? WebPEncodeLosslessRGBA(base, Int32(width), Int32(height), stride, &encoded)
                : WebPEncodeRGBA(base, Int32(width), Int32(height), stride, Float(quality * 100), &encoded)
        }
        guard size > 0, let encoded else { throw ImageConverterError.encodeFailed(name) }
        defer { WebPFree(encoded) }
        return Data(bytes: encoded, count: size)
    }
}
