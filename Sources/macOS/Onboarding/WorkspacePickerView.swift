import GlassDoKit
import SwiftData
import SwiftUI

/// Hazır çalışma alanı şablonlarının listesi. Hem ilk açılış sayfasında
/// (`WorkspaceOnboardingSheet`) hem Ayarlar'daki Çalışma Alanları
/// bölümünde aynı bileşen kullanılıyor — iki yerde iki ayrı önizleme
/// yazılsaydı biri diğerinden kayardı.
///
/// Şablon uygulamak yıkıcı değil: var olan etiket/görevler korunuyor,
/// yalnızca eksik olanlar ekleniyor (bkz. `WorkspaceTemplateApplier`).
/// Bu yüzden düğme, hiçbir şey eklemeyecekse hiç gösterilmiyor.
struct WorkspacePickerView: View {
    /// Onboarding sayfasında sheet'i kapatmak için. Ayarlar'da kullanılmıyor.
    var onFinished: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Son uygulanan şablon ve sonucu — onay satırı bunu gösteriyor.
    @State private var lastApplied: (kind: WorkspaceTemplateKind, result: WorkspaceApplyResult)?

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : Motion.expand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WorkspaceTemplateKind.allCases) { kind in
                templateCard(kind)
                    .padding(.horizontal, 14)
                    .glassCard()
            }
        }
    }

    private func templateCard(_ kind: WorkspaceTemplateKind) -> some View {
        let preview = WorkspaceTemplateApplier.preview(kind, in: context)
        let justApplied = lastApplied?.kind == kind
        let content = kind.content
        let tint = Color(hex: kind.tintHex)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Image(systemName: kind.symbolName)
                        .font(.app(size: 17))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tint.opacity(0.16))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.app(size: 13.5, weight: .semibold))
                        Text(kind.subtitle)
                            .font(.app(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }

                if !content.projectTags.isEmpty {
                    tagRow(label: L10n.workspaceProjectsLabel, tags: content.projectTags)
                }

                if !content.labelTags.isEmpty {
                    tagRow(label: L10n.workspaceLabelsLabel, tags: content.labelTags)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.workspaceSampleTasksLabel)
                        .font(.app(size: 10.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .kerning(0.3)

                    ForEach(content.sampleTasks, id: \.title) { task in
                        HStack(spacing: 7) {
                            Image(systemName: "circle")
                                .font(.app(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(task.title)
                                .font(.app(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 10)

            FormCardDivider()

            HStack(spacing: 10) {
                if justApplied {
                    Label(
                        L10n.workspaceAppliedConfirmation(
                            newTags: lastApplied?.result.newTagCount ?? 0,
                            newTasks: lastApplied?.result.newTaskCount ?? 0
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.app(size: 11.5, weight: .medium))
                    .foregroundStyle(SystemPalette.positive)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Text(
                        preview.isNoOp
                            ? L10n.workspaceAlreadyApplied
                            : L10n.workspacePreview(newTags: preview.newTagCount, newTasks: preview.newTaskCount)
                    )
                    .font(.app(size: 11.5))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }

                Spacer(minLength: 8)

                if !preview.isNoOp {
                    Button {
                        withAnimation(selectionAnimation) {
                            let result = WorkspaceTemplateApplier.apply(kind, in: context)
                            lastApplied = (kind, result)
                        }
                        onFinished?()
                    } label: {
                        Text(L10n.workspaceApply)
                            .font(.app(size: 12, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(selectionAnimation, value: justApplied)
            .padding(.vertical, 10)
        }
    }

    private func tagRow(label: String, tags: [WorkspaceTagSpec]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.app(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.3)

            // `.adaptive` yerine akan bir HStack yeterli: en fazla 8 etiket,
            // hepsi tek satırda sığmasa da satır kırıp devam ediyor.
            FlowLayoutWrap(spacing: 6) {
                ForEach(tags, id: \.name) { tag in
                    Text(tag.name)
                        .font(.app(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(Color(hex: tag.colorHex).opacity(0.16))
                        }
                        .foregroundStyle(Color(hex: tag.colorHex))
                }
            }
        }
    }
}

/// `StatPillRow`'daki gibi basit bir kayan (flow) düzen — burada ayrı
/// tutuluyor çünkü o türün adı `SystemMonitorDesign`'a özel ve etiket
/// pilleriyle karışmaması için.
private struct FlowLayoutWrap: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
