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

    @AppStorage("bugReport.draft.area") private var areaRaw = ""
    @AppStorage("bugReport.draft.severity") private var severityRaw = BugSeverity.annoying.rawValue
    @AppStorage("bugReport.draft.details") private var details = ""
    @AppStorage("bugReport.draft.steps") private var steps = ""
    @AppStorage("bugReport.draft.contact") private var contact = ""
    @AppStorage("bugReport.draft.includeDiagnostics") private var includeDiagnostics = true
    @AppStorage("bugReport.draft.pendingReportID") private var pendingReportID = ""
    @State private var showDiagnostics = false
    @State private var successAppeared = false

    @State private var diagnostics: BugDiagnostics?
    @State private var phase: Phase = .editing

    /// Hangi alanda yazıldığı. Odaktaki alanın çerçevesi vurgulanıyor:
    /// üç alan aynı gri zeminde dururken imlecin nerede olduğu
    /// yalnızca yanıp sönen çizgiden anlaşılıyordu.
    private enum Field: Hashable { case details, steps, contact }
    @FocusState private var focus: Field?

    private enum Phase: Equatable {
        case editing
        case sending(String)
        case queued(String)
        case sent(String)
        case failed(String)
    }

    private var area: BugArea? {
        get { BugArea(rawValue: areaRaw) }
        nonmutating set { areaRaw = newValue?.rawValue ?? "" }
    }

    private var severity: BugSeverity {
        get { BugSeverity(rawValue: severityRaw) ?? .annoying }
        nonmutating set { severityRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .sent(let reportID):
                result(reportID: reportID, queued: false)
                    .transition(.opacity)
            case .queued(let reportID):
                result(reportID: reportID, queued: true)
                    .transition(.opacity)
            default:
                editor
                    .transition(.opacity)
            }
        }
        .frame(width: 460)
        .frame(minHeight: 640)
        .background(.windowBackground)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: resultStage)
        .onAppear {
            phase = pendingReportID.isEmpty ? .editing : .queued(pendingReportID)
            successAppeared = false
        }
        // Tanılama dialog açılırken bir kez toplanıyor, gönderme anında
        // değil: kullanıcı yazarken paneli kapatmışsa hatanın görüldüğü
        // durumu değil, sonrasını kaydetmiş olurduk.
        .task {
            diagnostics = await BugDiagnostics.collect(panel: panelController)
            if case .editing = phase { focus = .details }
            let reportID = pendingReportID
            guard !reportID.isEmpty else { return }
            if let wasSent = await BugReportService.reconcilePending(reportID),
               pendingReportID == reportID {
                if wasSent {
                    clearDraft()
                    phase = .sent(reportID)
                } else {
                    pendingReportID = ""
                    phase = .failed(L10n.s(
                        "Rapor sunucuya ulaşmadı. Taslak korundu; lütfen yeniden deneyin.",
                        "The report did not reach the server. Your draft is saved; please try again.",
                        "Отчёт не дошёл до сервера. Черновик сохранён; попробуйте снова."
                    ))
                }
            }
        }
    }

    private var resultStage: Int {
        switch phase {
        case .queued: 1
        case .sent: 2
        default: 0
        }
    }

    // MARK: - Düzenleme

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            // Önce asıl iş: ne oldu. Sınıflandırma altta kalıyor;
            // konum seçilmeden yanlış bir varsayılan kaydedilmiyor.
            field(L10n.s("Ne oldu?", "What happened?", "Что произошло?")) {
                textArea(
                    placeholder: L10n.s(
                        "Ne yaptınız, ne olmasını bekliyordunuz?",
                        "What did you do, and what did you expect?",
                        "Что вы сделали и чего ожидали?"
                    ),
                    text: $details,
                    height: 92,
                    field: .details
                )
            }

            field(
                L10n.s("Nasıl tekrarlanıyor?", "How can we reproduce it?", "Как воспроизвести?"),
                optional: true
            ) {
                textArea(
                    placeholder: L10n.s(
                        "Adım adım yazın — en çok işe yarayan kısım.",
                        "Step by step — this is the most useful part.",
                        "По шагам — это самая полезная часть."
                    ),
                    text: $steps,
                    height: 62,
                    field: .steps
                )
            }

            // Nerede + ne kadar kötü: iki etiketli açılır menü, yan yana.
            // Önce dört renkli rozet denendi — sabit genişlikte etiketler
            // iki satıra kırılıyor ve seçili rozet dialogdaki tek doygun
            // renk olarak gözü asıl alandan çekiyordu. Açılır menü
            // sistemin kendi dili: kırpılmıyor, hizalanıyor, sessiz.
            HStack(alignment: .top, spacing: 12) {
                field(L10n.s("Nerede", "Where", "Где")) {
                    Picker(selection: Binding(get: { area }, set: { area = $0 })) {
                        Text(L10n.s("Seçin…", "Choose…", "Выберите…"))
                            .tag(nil as BugArea?)
                        ForEach(BugArea.allCases) { area in
                            Text(area.title).tag(area as BugArea?)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                field(L10n.s("Ne kadar kötü", "How bad", "Насколько плохо")) {
                    Picker(selection: Binding(get: { severity }, set: { severity = $0 })) {
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
            .disabled(isSending)

            field(L10n.s("E-posta", "Email", "E-mail"), optional: true) {
                TextField(
                    "",
                    text: $contact,
                    prompt: Text(L10n.s(
                        "Yanıt almak isterseniz",
                        "If you'd like a reply",
                        "Если хотите получить ответ"
                    ))
                )
                .font(.app(.bodyLarge))
                .textFieldStyle(.plain)
                .focused($focus, equals: .contact)
                .onSubmit { if canSend { send() } }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background { inputSurface(isFocused: focus == .contact) }
                .disabled(isSending)
            }

            Label(
                L10n.s("E-posta adresinde @ eksik.", "Email address is missing @.", "В адресе электронной почты нет @."),
                systemImage: "exclamationmark.circle"
            )
            .font(.app(.caption))
            .foregroundStyle(.orange)
            .opacity(emailLooksInvalid ? 1 : 0)
            .accessibilityHidden(!emailLooksInvalid)
            .animation(.easeOut(duration: 0.16), value: emailLooksInvalid)

            diagnosticsRow

            if case .failed(let message) = phase {
                errorBanner(message)
            }

            footer
        }
        .padding(20)
    }

    /// Başlık: kenar çubuğundaki sayfa karolarıyla aynı dil — renkli
    /// yuvarlatılmış kare içinde simge. Dialog uygulamanın parçası gibi
    /// durmalı, sistemden gelen bir uyarı gibi değil.
    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.42, blue: 0.34), Color(red: 0.82, green: 0.22, blue: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: Color(red: 0.82, green: 0.22, blue: 0.18).opacity(0.35), radius: 4, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.s("Hata Bildir", "Report a Bug", "Сообщить об ошибке"))
                    .font(.app(.titleLarge, weight: .semibold))

                Text(L10n.s(
                    "Sürüm ve sistem bilgisi rapora kendiliğinden eklenir.",
                    "Version and system details are attached automatically.",
                    "Сведения о версии и системе прикрепляются автоматически."
                ))
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    /// Bir denetimin üstündeki kalıcı başlık. Yer tutucu yazmaya başlayınca
    /// siliniyor; alanın neyi sorduğu da onunla birlikte kayboluyordu.
    /// İsteğe bağlı alanlar sağda soluk bir etiket taşıyor — hangilerinin
    /// boş bırakılabileceği zorunlu olanın yanında okunuyor.
    private func field<Content: View>(
        _ title: String,
        optional: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                if optional {
                    Text(L10n.s("isteğe bağlı", "optional", "необязательно"))
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Giriş alanlarının ortak zemini. Odaktaki alan vurgu rengiyle
    /// çerçeveleniyor.
    private func inputSurface(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
            .fill(Color.primary.opacity(isFocused ? 0.06 : 0.045))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.10),
                        lineWidth: isFocused ? 1.25 : 0.75
                    )
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
    }

    /// `TextEditor`ın kendi zemini bu düzende yamalı duruyor; saydam
    /// bırakılıp ortak zemine oturtuluyor. Yer tutucu da elle çiziliyor —
    /// `TextEditor`ın yerleşik bir `prompt`'u yok.
    private func textArea(
        placeholder: String,
        text: Binding<String>,
        height: CGFloat,
        field: Field
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.app(.bodyLarge))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }

            TextEditor(text: text)
                .font(.app(.bodyLarge))
                .scrollContentBackground(.hidden)
                // Boş alanda bile sağda gri bir kaydırma çubuğu çiziliyordu;
                // yazı sığmadığında tekerlek ve izleme dörtgeni zaten
                // kaydırıyor.
                .scrollIndicators(.never)
                .focused($focus, equals: field)
                .frame(height: height)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .disabled(isSending)
        }
        .padding(3)
        .background { inputSurface(isFocused: focus == field) }
        // Alanın her yerine tıklamak imleci oraya koymalı, yalnızca metin
        // satırlarına değil.
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
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
                    .font(.app(.body))
            }
            .toggleStyle(.checkbox)
            .disabled(isSending)

            if includeDiagnostics, diagnostics != nil {
                Button {
                    showDiagnostics = true
                } label: {
                    Text(L10n.s("neler gidiyor?", "what's included?", "что войдёт?"))
                        .font(.app(.body))
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
            .font(.app(.body))
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
            // Çok satırlı alanda Return satır ekliyor; göndermek için
            // ⌘↩. Kısayol yalnızca gönderilebilir olduğunda ipucu olarak
            // görünüyor.
            if canSend {
                Text(L10n.s("⌘↩ ile gönder", "⌘↩ to send", "⌘↩ — отправить"))
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            Button(L10n.s("Vazgeç", "Cancel", "Отмена")) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                send()
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    }
                    Text(isSending
                         ? L10n.s("Gönderiliyor…", "Sending…", "Отправка…")
                         : L10n.s("Gönder", "Send", "Отправить"))
                }
                .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: canSend)
    }

    private var canSend: Bool {
        !isSending && area != nil && !emailLooksInvalid
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    private var emailLooksInvalid: Bool {
        let email = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        return !email.isEmpty && !email.contains("@")
    }

    private func send() {
        guard canSend, let area else { return }
        do {
            let reportID = try BugReportService.enqueue(
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
            ) { completedID, errorMessage in
                guard pendingReportID == completedID else { return }
                if let errorMessage {
                    pendingReportID = ""
                    phase = .failed(errorMessage)
                } else {
                    clearDraft()
                    phase = .sent(completedID)
                }
            }
            pendingReportID = reportID
            phase = .sending(reportID)
            _Concurrency.Task { @MainActor in
                try? await _Concurrency.Task.sleep(for: .seconds(8))
                if phase == .sending(reportID) {
                    phase = .queued(reportID)
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func clearDraft() {
        pendingReportID = ""
        areaRaw = ""
        severityRaw = BugSeverity.annoying.rawValue
        details = ""
        steps = ""
        contact = ""
        includeDiagnostics = true
    }

    // MARK: - Sonuç

    private func result(reportID: String, queued: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: queued ? "clock.arrow.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(queued ? Color.accentColor : .green)
                .scaleEffect(queued || reduceMotion || successAppeared ? 1 : 0.94)
                .opacity(queued || successAppeared ? 1 : 0)
                .onAppear {
                    if !queued {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.82)) {
                            successAppeared = true
                        }
                    }
                }

            Text(queued
                 ? L10n.s("Rapor sıraya alındı", "Report queued", "Отчёт в очереди")
                 : L10n.s("Rapor gönderildi", "Report sent", "Отчёт отправлен"))
                .font(.app(.title, weight: .semibold))

            Text(queued
                 ? L10n.s(
                    "Sunucu henüz onaylamadı. Rapor cihazda kaydedildi; bağlantı kurulduğunda gönderilecek. Taslağı yeniden gönderirseniz ikinci bir rapor oluşur.",
                    "The server has not confirmed it yet. Your report is saved on this Mac and will send when connected. Resending the draft creates a second report.",
                    "Сервер пока не подтвердил получение. Отчёт сохранён на Mac и отправится при подключении. Повторная отправка черновика создаст второй отчёт."
                 )
                 : L10n.s(
                    "Teşekkürler. Aynı hatayı bildiren cihaz sayısı öncelik sırasını belirliyor.",
                    "Thank you. The number of devices reporting the same bug sets the priority.",
                    "Спасибо. Число устройств с той же ошибкой определяет приоритет."
                 ))
            .font(.app(.body))
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

            HStack(spacing: 10) {
                if queued {
                    Button(L10n.s("Taslağa dön", "Return to draft", "Вернуться к черновику")) {
                        pendingReportID = ""
                        phase = .editing
                        focus = .details
                    }
                }

                Button(L10n.s("Kapat", "Close", "Закрыть")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(message)
                .font(.app(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }
}
