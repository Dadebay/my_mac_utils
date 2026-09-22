import SwiftUI
import AppKit
import GlassDoKit

/// "Hata Bildir" dialogu. Menü çubuğundan açılıyor.
///
/// Kasıtlı olarak tek ekran, kaydırmasız ve sabit boyutlu: bir dialog
/// kadar kısa olmalı. Kart içinde kart, üç ayrı metin kutusu ve kaydırma
/// çubuğu olan uzun bir form doldurulmama riskini artırıyordu — hiç
/// gönderilmeyen ayrıntılı bir rapor, gönderilen kısa bir rapordan daha az
/// işe yarıyor.
///
/// Tek satırlık özet alanı ayrıca sorulmuyor; açıklamanın ilk satırı özet
/// olarak kaydediliyor (bkz. `submit`). Kullanıcıya iki kez aynı şeyi
/// yazdırmanın karşılığı yok.
struct BugReportView: View {
    let panelController: EdgePanelController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var area: BugArea = .panel
    @State private var severity: BugSeverity = .annoying
    @State private var details = ""
    @State private var steps = ""
    @State private var contact = ""
    @State private var includeDiagnostics = true
    @State private var showDiagnostics = false

    @State private var diagnostics: BugDiagnostics?
    @State private var phase: Phase = .editing

    @FocusState private var detailsFocused: Bool

    private enum Phase: Equatable {
        case editing
        case sending
        case sent(String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .sent(let reportID):
                success(reportID: reportID)
            default:
                editor
            }
        }
        .frame(width: 460)
        .background(.windowBackground)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.3, dampingFraction: 1.0),
            value: phase
        )
        // Tanılama dialog açılırken bir kez toplanıyor, gönderme anında
        // değil: kullanıcı yazarken paneli kapatmışsa hatanın görüldüğü
        // durumu değil, sonrasını kaydetmiş olurduk.
        .task {
            diagnostics = await BugDiagnostics.collect(panel: panelController)
            detailsFocused = true
        }
    }

    // MARK: - Düzenleme

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // Nerede + ne kadar kötü: iki etiketli açılır menü, yan yana.
            // Önce dört renkli rozet denendi — sabit genişlikte etiketler
            // iki satıra kırılıyor ve seçili rozet dialogdaki tek doygun
            // renk olarak gözü asıl alandan (ne oldu?) çekiyordu. Açılır
            // menü sistemin kendi dili: kırpılmıyor, hizalanıyor, sessiz.
            HStack(alignment: .top, spacing: 12) {
                labeledField(L10n.s("Nerede", "Where", "Где")) {
                    Picker(selection: $area) {
                        ForEach(BugArea.allCases) { area in
                            Text(area.title).tag(area)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                labeledField(L10n.s("Ne kadar kötü", "How bad", "Насколько плохо")) {
                    Picker(selection: $severity) {
                        ForEach(BugSeverity.allCases) { option in
                            // Renk yalnızca küçük bir nokta: sıralamayı
                            // okunur kılıyor, dialogun rengini bozmuyor.
                            Label {
                                Text(option.title)
                            } icon: {
                                Circle()
                                    .fill(option.tint)
                                    .frame(width: 7, height: 7)
                            }
                            .tag(option)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                }
            }
            .disabled(phase == .sending)

            textArea(
                placeholder: L10n.s(
                    "Ne oldu? Ne olmasını bekliyordunuz?",
                    "What happened? What did you expect?",
                    "Что произошло? Чего вы ожидали?"
                ),
                text: $details,
                height: 76
            )
            .focused($detailsFocused)

            textArea(
                placeholder: L10n.s(
                    "Nasıl tekrarlanıyor? (isteğe bağlı, en çok işe yarayan kısım)",
                    "How do we reproduce it? (optional, the most useful part)",
                    "Как это воспроизвести? (необязательно, самая полезная часть)"
                ),
                text: $steps,
                height: 46
            )

            TextField(
                L10n.s("E-posta (isteğe bağlı)", "Email (optional)", "E-mail (необязательно)"),
                text: $contact
            )
            .font(.app(size: 12))
            .textFieldStyle(.roundedBorder)
            .disabled(phase == .sending)

            diagnosticsRow

            if case .failed(let message) = phase {
                errorBanner(message)
            }

            footer
        }
        .padding(18)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 15))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.s("Hata Bildir", "Report a Bug", "Сообщить об ошибке"))
                    .font(.app(size: 14, weight: .semibold))

                Text(L10n.s(
                    "Sürüm ve sistem bilgisi rapora kendiliğinden eklenir.",
                    "Version and system details are attached automatically.",
                    "Сведения о версии и системе прикрепляются автоматически."
                ))
                .font(.app(size: 10.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    /// Bir denetimin üstündeki küçük başlık. Dialogda dört alan var ve
    /// ikisi açılır menü — başlıksız bırakıldığında "Kenar Paneli / Ray"
    /// yazan bir menünün neyi sorduğu ancak tıklayınca anlaşılıyordu.
    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `TextEditor`ın kendi zemini bu düzende yamalı duruyor; saydam
    /// bırakılıp kendi çerçevesine oturtuluyor. Yer tutucu da elle
    /// çiziliyor — `TextEditor`ın yerleşik bir `prompt`'u yok.
    private func textArea(placeholder: String, text: Binding<String>, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.app(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }

            TextEditor(text: text)
                .font(.app(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: height)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .disabled(phase == .sending)
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                }
        }
    }

    // MARK: - Tanılama

    /// Tek satır: anahtar + "neler gidiyor" bağlantısı. Ayrıntı listesi
    /// dialogu uzatmasın diye açılır pencerede — ama yine tek tıkla
    /// görülebiliyor: gönderilecek veriyi birebir göstermek, onay istemenin
    /// en dürüst biçimi.
    private var diagnosticsRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $includeDiagnostics) {
                Text(L10n.s("Teknik bilgileri ekle", "Attach technical details", "Прикрепить техническую информацию"))
                    .font(.app(size: 11.5))
            }
            .toggleStyle(.checkbox)
            .disabled(phase == .sending)

            if includeDiagnostics, diagnostics != nil {
                Button {
                    showDiagnostics = true
                } label: {
                    Text(L10n.s("neler gidiyor?", "what's included?", "что войдёт?"))
                        .font(.app(size: 11))
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) {
                    diagnosticsPopover
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var diagnosticsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.s(
                "Görev başlığı, dosya adı, not metni ya da pano içeriği gönderilmez.",
                "No task titles, file names, note text, or clipboard contents are sent.",
                "Названия задач, имена файлов, текст заметок и буфер обмена не отправляются."
            ))
            .font(.app(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let diagnostics {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(diagnostics.humanReadableSummary, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 330)
    }

    // MARK: - Gönder

    private var footer: some View {
        HStack(spacing: 10) {
            if phase == .sending {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 8)

            Button(L10n.s("Vazgeç", "Cancel", "Отмена")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(phase == .sending)

            Button {
                _Concurrency.Task { await send() }
            } label: {
                Text(L10n.s("Gönder", "Send", "Отправить"))
                    .frame(minWidth: 52)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        phase != .sending && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        phase = .sending
        do {
            let reportID = try await BugReportService.submit(
                area: area,
                severity: severity,
                // Özet ayrı sorulmuyor: açıklamanın ilk satırı liste
                // görünümünde başlık olarak yeterli.
                summary: details
                    .split(separator: "\n", maxSplits: 1)
                    .first
                    .map(String.init) ?? "",
                details: details,
                steps: steps,
                contact: contact,
                diagnostics: includeDiagnostics ? diagnostics : nil
            )
            phase = .sent(reportID)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Sonuç

    private func success(reportID: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.green)

            Text(L10n.s("Rapor gönderildi", "Report sent", "Отчёт отправлен"))
                .font(.app(size: 14, weight: .semibold))

            Text(L10n.s(
                "Teşekkürler. Aynı hatayı bildiren cihaz sayısı öncelik sırasını belirliyor.",
                "Thank you. The number of devices reporting the same bug sets the priority.",
                "Спасибо. Число устройств с той же ошибкой определяет приоритет."
            ))
            .font(.app(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            // Kimlik kopyalanabiliyor: kullanıcı sonradan yazarsa "hangi
            // rapor" sorusu tek hamlede çözülüyor.
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reportID, forType: .string)
            } label: {
                HStack(spacing: 5) {
                    Text(reportID)
                        .font(.system(size: 10.5, design: .monospaced))
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(L10n.s("Rapor kimliğini kopyala", "Copy report ID", "Копировать идентификатор"))

            Button(L10n.s("Kapat", "Close", "Закрыть")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(message)
                .font(.app(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }
}
