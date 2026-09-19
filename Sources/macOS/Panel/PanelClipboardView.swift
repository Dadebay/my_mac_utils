import AppKit
import GlassDoKit
import SwiftUI

/// Kenar panelindeki pano geçmişi. Bir girdiye tıklamak onu sisteme geri
/// kopyalıyor — yapıştırmayı kullanıcı kendi uygulamasında yapıyor, panel
/// başka bir uygulamaya tuş göndermiyor.
struct PanelClipboardView: View {
    private let store = ClipboardHistoryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.entries) { entry in
                            ClipboardRow(entry: entry, reduceMotion: reduceMotion)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task { store.startMonitoring() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.clipboardTitle)
                .font(.app(size: 12, weight: .medium))

            Spacer(minLength: 8)

            if !store.entries.isEmpty {
                Button {
                    store.clearAll()
                } label: {
                    Text(L10n.s("Temizle", "Clear", "Очистить"))
                        .font(.app(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "doc.on.clipboard")
                .font(.app(size: 22, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.clipboardEmptyHint)
                .font(.app(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
    }
}

/// Tek bir pano girdisi. Görsel girdilerde küçük bir önizleme, metin
/// girdilerinde ilk iki satır gösteriliyor — panelin genişliğinde daha
/// fazlası okunmuyor, yalnızca satırı uzatıyordu.
private struct ClipboardRow: View {
    let entry: ClipboardEntry
    var reduceMotion: Bool

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var justCopied = false

    private var style: ClipboardContentStyle {
        ClipboardContentStyle.detect(kind: entry.kind, text: entry.text)
    }

    private var lines: [String] {
        (entry.text ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            preview

            VStack(alignment: .leading, spacing: 4) {
                if entry.kind == .text {
                    Text(lines.prefix(2).joined(separator: "\n"))
                        .font(.system(size: 11.5, design: style.usesMonospace ? .monospaced : .default))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    Text(style.label)
                        .font(.app(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    if lines.count > 2 {
                        Text(L10n.clipboardMoreLines(lines.count - 2))
                            .font(.app(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)

                    Text(Self.relativeText(for: entry.createdAt))
                        .font(.app(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.07 : 0.035))
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovering)
        .onTapGesture { copy() }
        .contextMenu {
            Button(L10n.s("Sil", "Delete", "Удалить"), role: .destructive) {
                ClipboardHistoryStore.shared.remove(entry)
            }
        }
        .task(id: entry.id) { await loadThumbnailIfNeeded() }
    }

    /// Satırın solundaki tek simge hem içerik türünü söylüyor hem de
    /// eylemi: üzerine gelince kopyalama ikonuna, kopyalandıktan sonra
    /// kısa süre tike dönüyor. Önceden sağda ayrı bir kopyalama ikonu
    /// vardı — satırın tamamı zaten tıklanınca kopyaladığı için o ikon
    /// ikinci bir düğme sanılıyor, üstelik dar panelde metinden yer
    /// çalıyordu.
    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if isHovering || justCopied {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.black.opacity(0.55))
                            .overlay {
                                HugeIcon(name: justCopied ? .check : .copy, size: 15)
                                    .foregroundStyle(.white)
                            }
                    }
                }
        } else {
            HugeIcon(name: displayedIcon, size: 15)
                .foregroundStyle(iconTint)
                .frame(width: 18, alignment: .center)
        }
    }

    private var displayedIcon: HugeIconName {
        if justCopied { return .check }
        return isHovering ? .copy : style.hugeIcon
    }

    private var iconTint: Color {
        if justCopied { return SystemPalette.positive }
        return isHovering ? Color.accentColor : .secondary
    }

    /// Kopyalandığı an tikle onaylanıyor: tıklamanın görünür bir sonucu
    /// yoksa kullanıcı ikinci kez tıklıyordu.
    private func copy() {
        ClipboardHistoryStore.shared.copyToPasteboard(entry)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { justCopied = true }
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(1.2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { justCopied = false }
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard entry.kind == .image, let url = ClipboardHistoryStore.shared.imageURL(for: entry) else {
            return
        }
        thumbnail = NSImage(contentsOf: url)
    }
}


// MARK: - Göreli zaman

private extension ClipboardRow {
    /// Kısa göreli zaman: "8 dk", "3 sa", "dün".
    ///
    /// Önceki `Text(date, style: .relative)` saniyeye kadar iniyordu
    /// ("8 min, 3 secs") — pano girdisinde saniye bilgi değil gürültü, üstelik
    /// her saniye yeniden çiziliyordu.
    ///
    /// Dil uygulamanın kendi seçiminden geliyor, sistem yerelinden değil:
    /// kullanıcı uygulamayı Türkçe kullanırken tarihin İngilizce yazması
    /// tutarsız olurdu.
    static func relativeText(for date: Date) -> String {
        let formatter = Self.relativeFormatter
        formatter.locale = Locale(identifier: L10n.language.rawValue)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// `RelativeDateTimeFormatter` Sendable değil; yalnızca görünümlerden
    /// (ana aktör) çağrıldığı için tek örnek yeterli — `SystemFormat` ile
    /// aynı gerekçe.
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

// MARK: - İçerik türü

/// Panodaki metnin ne olduğuna dair kaba bir tahmin.
///
/// Modelde böyle bir alan yok ve olması da gerekmiyor: bu tamamen bir
/// sunum kararı — hangi simgenin çizileceği ve metnin eşaralıklı yazılıp
/// yazılmayacağı. Tahmin yanılırsa kaybedilen tek şey simgenin isabeti,
/// içerik olduğu gibi duruyor.
enum ClipboardContentStyle {
    case image, link, command, code, text

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .link: "link"
        case .command: "terminal"
        case .code: "curlybraces"
        case .text: "text.alignleft"
        }
    }

    /// Panel satırlarında kullanılan Hugeicons karşılığı. `symbolName`
    /// (SF Symbols) duruyor: boş durum ve erişilebilirlik hâlâ onu
    /// kullanıyor.
    var hugeIcon: HugeIconName {
        switch self {
        case .image: .image
        case .link: .link
        case .command: .terminal
        case .code: .code
        case .text: .text
        }
    }

    var usesMonospace: Bool {
        self == .command || self == .code
    }

    var label: String {
        switch self {
        case .image: L10n.clipboardKindImage
        case .link: L10n.clipboardKindLink
        case .command: L10n.clipboardKindCommand
        case .code: L10n.clipboardKindCode
        case .text: L10n.clipboardKindText
        }
    }

    /// Kabukta en sık kopyalanan komutların ilk kelimeleri. Tam bir liste
    /// değil, olması da gerekmiyor — eşleşmeyen bir komut yalnızca düz
    /// metin simgesi alıyor.
    private static let commandVerbs: Set<String> = [
        "sudo", "grep", "docker", "git", "npm", "npx", "yarn", "pnpm", "brew",
        "ssh", "scp", "curl", "wget", "cd", "ls", "cat", "echo", "find", "kill",
        "chmod", "chown", "systemctl", "service", "ps", "top", "tail", "head",
        "mkdir", "rm", "cp", "mv", "tar", "unzip", "python", "python3", "node",
        "swift", "xcodebuild", "pod", "make", "awk", "sed", "which", "open",
        "defaults", "launchctl", "killall", "ping", "dig", "nano", "vim",
    ]

    static func detect(kind: ClipboardEntry.Kind, text: String?) -> ClipboardContentStyle {
        guard kind == .text else { return .image }

        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if let url = URL(string: trimmed), url.scheme != nil, !trimmed.contains(" ") {
            return .link
        }

        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        // "$ " ya da "user@host:~$ " gibi bir istem varsa komut kesin.
        let withoutPrompt = firstLine.contains("$ ")
            ? String(firstLine[firstLine.range(of: "$ ")!.upperBound...])
            : firstLine
        let firstWord = withoutPrompt
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""

        if commandVerbs.contains(firstWord) || firstLine.contains("$ ") {
            return .command
        }

        let isMultiline = trimmed.contains("\n")
        if isMultiline, trimmed.contains("{") || trimmed.contains(";") || trimmed.contains("=>") {
            return .code
        }

        return .text
    }
}
