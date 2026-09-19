import GlassDoKit
import SwiftUI

/// Raftaki dosyalardan birini ataşman olarak seçmek için basit bir sheet.
struct ShelfAttachmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL) -> Void

    @State private var items: [StorageItem] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.addFromShelfAttachment)
                    .font(.app(size: 13, weight: .semibold))
                Spacer()
                Button(L10n.close) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Spacer()
                Text(L10n.emptyFolder)
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            Button {
                                onPick(item.url)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind.symbolName)
                                        .foregroundStyle(.secondary)
                                    Text(item.name)
                                        .font(.app(size: 12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, height: 360)
        .task { await load() }
    }

    private func load() async {
        do {
            let service = try ManagedStorageService.default()
            let shelf = try service.prepareShelf()
            items = try service.contents(of: shelf)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Pano geçmişindeki bir metni ataşman olarak seçmek için basit bir sheet.
struct ClipboardAttachmentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    private var textEntries: [ClipboardEntry] {
        ClipboardHistoryStore.shared.entries.filter { $0.kind == .text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.addFromClipboardAttachment)
                    .font(.app(size: 13, weight: .semibold))
                Spacer()
                Button(L10n.close) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if textEntries.isEmpty {
                Spacer()
                Text(L10n.emptyFolder)
                    .font(.app(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(textEntries) { entry in
                            Button {
                                onPick(entry.text ?? "")
                                dismiss()
                            } label: {
                                Text(entry.text ?? "")
                                    .font(.app(size: 12))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, height: 360)
    }
}
