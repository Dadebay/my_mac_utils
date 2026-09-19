import GlassDoKit
import SwiftData
import SwiftUI

/// Bağlama duyarlı Edge Rail ayarları: özelliği açan anahtar, ne
/// okunduğunu açıkça söyleyen gizlilik notu ve tanımlı kuralların listesi.
///
/// Kural **eklemek** buradan yapılmıyor: kurallar bir görevin sağ tık
/// menüsünden doğuyor (bkz. `L10n.contextRuleStartAction`), çünkü kuralın
/// anlamı her zaman belirli bir görevle başlıyor. Burada yalnızca var
/// olanlar görülüp kaldırılabiliyor.
struct ContextAwareSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AppContextRule.sortIndex) private var rules: [AppContextRule]

    @AppStorage(PanelSettings.contextAwareRailEnabledKey) private var isEnabled = false

    private let monitor = ActiveApplicationMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: L10n.s("Bağlama duyarlı ray", "Context-aware rail", "Контекстная панель"),
                subtitle: L10n.s(
                    "Öndeki uygulamaya bağlı görevler rayın üstünde öne çıkar.",
                    "Tasks tied to the frontmost app move to the top of the rail.",
                    "Задачи, привязанные к активному приложению, поднимаются в начало панели."
                )
            ) {
                Toggle(isOn: $isEnabled) {
                    Text(L10n.s("Etkin", "Enabled", "Включено"))
                        .font(.app(size: 12.5))
                }
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { _, newValue in
                    // İzleme yalnızca özellik açıkken kuruluyor; kapatınca
                    // bellekteki uygulama bilgisi de siliniyor.
                    newValue ? monitor.start() : monitor.stop()
                }

                Text(L10n.contextAwarePrivacyNote)
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if isEnabled, let name = monitor.activeApplicationName {
                    FormCardDivider()
                    HStack(spacing: 6) {
                        Text(L10n.contextSuggestedNowLabel)
                            .font(.app(size: 11))
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.app(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                }
            }

            SettingsCard(title: L10n.contextRulesTitle) {
                if rules.isEmpty {
                    Text(L10n.contextRulesEmpty)
                        .font(.app(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rules) { rule in
                        if rule.persistentModelID != rules.first?.persistentModelID {
                            FormCardDivider()
                        }
                        ruleRow(rule)
                    }
                }
            }
        }
        .task {
            if isEnabled { monitor.start() }
        }
    }

    private func ruleRow(_ rule: AppContextRule) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0 }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName ?? rule.bundleIdentifier)
                    .font(.app(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(targetLabel(rule))
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                context.delete(rule)
            } label: {
                Text(L10n.s("Kaldır", "Remove", "Удалить"))
                    .font(.app(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
    }

    private func targetLabel(_ rule: AppContextRule) -> String {
        if let task = rule.task { return task.title }
        if let tag = rule.tag { return L10n.contextRuleTargetTag(tag.name) }
        return "—"
    }
}
