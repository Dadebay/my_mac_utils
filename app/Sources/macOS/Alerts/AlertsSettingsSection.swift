import SwiftUI
import GlassDoKit

/// Ayarlar > Uyarılar. İki bildirim, ikisi de eşikli.
///
/// `SystemAlertSettings` doğrudan `UserDefaults`'a yazdığı için burada
/// `@State` yerel bir kopya tutuyor ve her değişiklikte servise haber
/// veriyor — kapatılan bir izleyicinin bir sonraki yoklamaya kadar açık
/// kalmaması için.
struct AlertsSettingsSection: View {
    @State private var thermalEnabled = SystemAlertSettings.thermalEnabled
    @State private var thermalThreshold = SystemAlertSettings.thermalThreshold
    @State private var trashEnabled = SystemAlertSettings.trashEnabled
    @State private var trashThreshold = SystemAlertSettings.trashThresholdGB
    @State private var trashSize: UInt64?
    @State private var trashReadable = true
    private let processesVisible = TopProcessSampler.canEnumerate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: L10n.s("Isınma", "Heat", "Нагрев")) {
                VStack(alignment: .leading, spacing: 4) {
                    IconToggleRow(
                        systemName: "thermometer.high",
                        label: L10n.s(
                            "Mac ısınınca bildir",
                            "Notify when the Mac heats up",
                            "Уведомлять при нагреве Mac"
                        ),
                        isOn: $thermalEnabled
                    )

                    if thermalEnabled {
                        SettingsRowDivider()

                        ValueSlider(
                            label: L10n.s("Eşik", "Threshold", "Порог"),
                            value: $thermalThreshold,
                            range: 60...100,
                            format: { "\(Int($0))°C" }
                        )

                        Text(L10n.s(
                            "Bildirim, sıcaklık eşiği üst üste iki ölçüm (yaklaşık bir dakika) boyunca geçtiğinde gelir ve en çok işlemci kullanan uygulamanın adını taşır. Tek seferlik sıçramalar (derleme, dizinleme) bildirim üretmez.",
                            "The notification arrives when the temperature stays above the threshold for two consecutive samples (about a minute), and names the app using the most CPU. One-off spikes (a build, indexing) produce nothing.",
                            "Уведомление приходит, когда температура держится выше порога два измерения подряд (около минуты), и называет приложение, потребляющее больше всего процессора. Разовые всплески не уведомляют."
                        ))
                        .font(.app(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                        if !processesVisible {
                            limitationNote(L10n.s(
                                "Bu yapı işlem listesini okuyamıyor (App Sandbox), bu yüzden bildirim yalnızca ısınmayı haber verir; hangi uygulamanın yüklediğini yazamaz.",
                                "This build can't read the process list (App Sandbox), so the notification reports the heat but can't name the app causing it.",
                                "Эта сборка не может читать список процессов (App Sandbox), поэтому уведомление сообщит о нагреве, но не назовёт приложение."
                            ))
                        }
                    }
                }
            }

            SettingsCard(title: L10n.s("Çöp Kutusu", "Trash", "Корзина")) {
                VStack(alignment: .leading, spacing: 4) {
                    IconToggleRow(
                        systemName: "trash",
                        label: L10n.s(
                            "Çöp kutusu şişince bildir",
                            "Notify when the Trash grows large",
                            "Уведомлять, когда корзина разрастается"
                        ),
                        isOn: $trashEnabled
                    )

                    if trashEnabled {
                        SettingsRowDivider()

                        ValueSlider(
                            label: L10n.s("Eşik", "Threshold", "Порог"),
                            value: $trashThreshold,
                            range: 1...100,
                            format: { "\(Int($0)) GB" }
                        )

                        if !trashReadable {
                            // İki ayrı sebep, iki ayrı mesaj: sandbox'ta
                            // hiçbir zaman mümkün değil; sandbox'sız
                            // yapıda ise yalnızca izin eksik ve kullanıcı
                            // onu kendi verebiliyor.
                            if SystemAlertService.isSandboxed {
                                limitationNote(L10n.s(
                                    "Bu yapı çöp kutusunu okuyamıyor (App Sandbox), bu yüzden uyarı çalışmaz.",
                                    "This build can't read the Trash (App Sandbox), so this alert won't fire.",
                                    "Эта сборка не может читать корзину (App Sandbox), поэтому оповещение не сработает."
                                ))
                            } else {
                                limitationNote(L10n.s(
                                    "Çöp kutusunu okumak için Tam Disk Erişimi gerekiyor; verilmeden bu uyarı çalışmaz.",
                                    "Reading the Trash needs Full Disk Access; without it this alert won't fire.",
                                    "Для чтения корзины нужен полный доступ к диску; без него оповещение не сработает."
                                ))

                                Button(L10n.s(
                                    "Tam Disk Erişimi'ni aç",
                                    "Open Full Disk Access",
                                    "Открыть полный доступ к диску"
                                )) {
                                    SystemAlertService.openFullDiskAccessSettings()
                                }
                                .font(.app(size: 11.5))
                                .fixedSize()
                                .padding(.top, 2)
                            }
                        } else if let trashSize {
                            HStack(spacing: 6) {
                                Text(L10n.s(
                                    "Şu an: \(SystemAlertService.formatted(trashSize))",
                                    "Right now: \(SystemAlertService.formatted(trashSize))",
                                    "Сейчас: \(SystemAlertService.formatted(trashSize))"
                                ))
                                .font(.app(size: 11.5))
                                .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                Button(L10n.s("Çöp Kutusunu Aç", "Open Trash", "Открыть корзину")) {
                                    if let url = SystemAlertService.trashURL() {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .font(.app(size: 11.5))
                                .fixedSize()
                            }
                            .padding(.top, 2)
                        }

                        // Silme düğmesi bilerek yok: geri alınamaz bir
                        // işlemi, ne silineceğini görmeden bildirimden tek
                        // tıkla yapmak doğru değil. Bildirimdeki düğme de
                        // Finder'da açıyor.
                        Text(L10n.s(
                            "Bildirim yalnızca haber verir; silme kararı Finder'da sizde kalır. Aynı çöp için yeniden bildirim gelmesi için bir hafta geçmesi ya da boyun yarı yarıya büyümesi gerekir.",
                            "The notification only informs you; the decision to delete stays with you in Finder. A repeat notification for the same Trash needs a week to pass or its size to grow by half.",
                            "Уведомление только информирует; решение об удалении остаётся за вами в Finder. Повторное уведомление требует недели или роста размера на половину."
                        ))
                        .font(.app(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .onChange(of: thermalEnabled) { _, value in
            SystemAlertSettings.thermalEnabled = value
            SystemAlertService.shared.settingsChanged()
        }
        .onChange(of: thermalThreshold) { _, value in
            SystemAlertSettings.thermalThreshold = value
        }
        .onChange(of: trashEnabled) { _, value in
            SystemAlertSettings.trashEnabled = value
            SystemAlertService.shared.settingsChanged()
        }
        .onChange(of: trashThreshold) { _, value in
            SystemAlertSettings.trashThresholdGB = value
        }
        .task {
            trashReadable = SystemAlertService.isTrashReadable
            guard trashReadable, let url = SystemAlertService.trashURL() else { return }
            trashSize = await SystemAlertService.directorySize(at: url)
        }
    }

    /// Özelliğin bu yapıda neden çalışmadığını söyleyen satır. Sessizce
    /// çalışmayan bir anahtar, kapalı bir anahtardan daha kötü: kullanıcı
    /// açtığını sanıp bildirim bekliyor.
    private func limitationNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(text)
                .font(.app(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}
