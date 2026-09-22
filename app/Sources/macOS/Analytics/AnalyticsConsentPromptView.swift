import GlassDoKit
import SwiftUI

/// İlk açılışta bir kez gösterilen kullanım verisi izni sayfası.
/// Metinler burada duruyor çünkü yalnızca bu ekranda geçiyorlar —
/// paylaşılan `L10n` sözlüğüne girseler kullanılmayan anahtarlar olarak
/// birikirdi.
struct AnalyticsConsentPromptView: View {
    /// `true` → izin verildi. Kapatma da bir yanıttır: sheet yalnızca bu
    /// kapanış çağrısıyla kapanıyor, böylece "sorulmadı" durumu geride
    /// kalmıyor.
    let onDecision: (Bool) -> Void

    init(onDecision: @escaping (Bool) -> Void) {
        self.onDecision = onDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.app(size: 34))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.s(
                        "Kullanım verisi paylaşılsın mı?",
                        "Share usage data?",
                        "Отправлять данные об использовании?"
                    ))
                    .font(.app(size: 19, weight: .bold))

                    Text(L10n.s(
                        "GlassDo'yu neyin işe yaradığına bakarak geliştiriyoruz. Bu tamamen isteğe bağlı ve daha sonra Ayarlar'dan değiştirilebilir.",
                        "We improve GlassDo by looking at what actually gets used. This is entirely optional and can be changed later in Settings.",
                        "Мы улучшаем GlassDo, глядя на то, что действительно используется. Это полностью необязательно и может быть изменено позже в настройках."
                    ))
                    .font(.app(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("checkmark.circle", L10n.s(
                    "Yalnızca hangi özelliklerin kaç kez açıldığı ve cihaz modeli gibi teknik bilgiler.",
                    "Only which features were opened how many times, plus technical details like the device model.",
                    "Только то, какие функции и сколько раз открывались, плюс технические данные вроде модели устройства."
                ))
                bullet("lock.circle", L10n.s(
                    "Görev içerikleri, notlar, pano geçmişi ve dosya adları hiçbir zaman gönderilmez.",
                    "Task contents, notes, clipboard history, and file names are never sent.",
                    "Содержимое задач, заметки, история буфера обмена и имена файлов никогда не отправляются."
                ))
                bullet("arrow.uturn.backward.circle", L10n.s(
                    "Kararını istediğin zaman Ayarlar'dan geri alabilirsin.",
                    "You can reverse your choice at any time in Settings.",
                    "Вы можете изменить своё решение в любой момент в настройках."
                ))
            }

            HStack {
                Spacer()

                Button(L10n.s("Şimdi Değil", "Not Now", "Не сейчас")) {
                    onDecision(false)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(L10n.s("Paylaş", "Share", "Отправлять")) {
                    onDecision(true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    /// Simge sütunu sabit genişlikte — farklı genişlikteki SF sembolleri
    /// metin başlangıçlarını birbirinden kaydırmasın diye.
    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.app(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
