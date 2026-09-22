import GlassDoKit
import SwiftUI

/// İlk açılışta bir kez gösterilen çalışma alanı seçim sayfası.
/// `AnalyticsConsentPromptView` ile aynı sunum deseni: tek eylemli bir
/// sheet, kapanınca bir daha görünmez.
struct WorkspaceOnboardingSheet: View {
    let onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.workspaceOnboardingTitle)
                        .font(.app(size: 20, weight: .bold))
                    Text(L10n.workspaceOnboardingSubtitle)
                        .font(.app(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                // Spec'in açık isteği: bu düğme şablon kartlarıyla eşit
                // görünürlükte olmalı — kullanıcı hiçbir şablon seçmeden
                // de eşit rahatlıkla devam edebilmeli, küçük bir bağlantı
                // olarak gizlenmemeli.
                Button(L10n.workspaceOnboardingContinueEmpty) {
                    onFinished()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            ScrollView {
                WorkspacePickerView(onFinished: onFinished)
            }
            .frame(maxHeight: 380)
        }
        .padding(28)
        .frame(width: 560)
    }
}
