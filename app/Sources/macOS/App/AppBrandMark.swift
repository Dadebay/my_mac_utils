import AppKit
import SwiftUI

/// Uygulamanın kimlik rozeti.
///
/// Projede henüz bir ikon varlığı yok; bu durumda `NSApp.applicationIconImage`
/// macOS'un jenerik "boş uygulama" ikonunu döndürüyor ve Ayarlar ile Hakkında
/// pencerelerinde bozuk bir yer tutucu gibi görünüyordu. Gerçek bir ikon
/// paketlendiği anda o kullanılıyor; paketlenmediğinde uydurma bir yer tutucu
/// yerine uygulamanın kendi işaretini çiziyor.
///
/// Bilerek kenar çubuğu satırlarındaki sakin, tintli karolardan daha doygun:
/// kimlik hiyerarşinin tepesinde durur, gezinme satırlarıyla aynı ağırlıkta
/// olursa aralarındaki fark kaybolur.
struct AppBrandMark: View {
    var size: CGFloat = 28

    /// Uygulama paketinde gerçekten bir ikon var mı? İkisinden biri yeterli:
    /// varlık kataloğundan gelen `CFBundleIconName` ya da klasik
    /// `CFBundleIconFile`.
    private var hasBundledIcon: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil
            || Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
    }

    /// Görevler listesinin tonuyla aynı mavi: uygulamanın birincil kimliği
    /// bir yapılacaklar listesi, sistem ölçerlerinin moru değil.
    private static let brand = Color(red: 0.24, green: 0.58, blue: 1.0)
    private static let brandDeep = Color(red: 0.11, green: 0.40, blue: 0.92)

    private var radius: CGFloat { size * 0.235 }

    var body: some View {
        Group {
            if hasBundledIcon, let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                drawnMark
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var drawnMark: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Self.brand, Self.brandDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Image(systemName: "checklist")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    // SF Symbol'ün optik merkezi geometrik merkezin biraz
                    // altında; düzeltilmezse karoda yukarı kaçmış görünüyor.
                    .padding(.bottom, size * 0.03)
            }
            .overlay {
                // Üst kenar bir tık daha parlak: ışığın yüzeye vurduğu
                // izlenimi, karoyu düz bir renk lekesi olmaktan çıkarıyor.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: Self.brandDeep.opacity(0.28), radius: size * 0.11, y: size * 0.05)
    }
}
