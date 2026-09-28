import SwiftUI
import GlassDoKit

// MARK: - Ortak ölçüler

/// Ayarlar penceresinin ölçü sistemi.
///
/// Aynı sayı üç ayrı dosyada elle tekrarlandığında zamanla ayrışıyor:
/// kenar çubuğu bir hizada, sağdaki içerik başka bir hizada başlıyor.
/// Buradaki her değer bir kere tanımlanıp her iki sütunda da okunuyor.
enum SettingsMetrics {
    /// Kenar boşlukları işlemci panosuyla (`SystemMetricPage`) birebir
    /// aynı: iki sayfa aynı pencerede, aynı kenar çubuğunun yanında açılıyor
    /// ve kartları aynı çizgide başlamalı. Eskiden ayarlar 28 pt içerideydi,
    /// sayfa değiştirince bütün içerik yana kayıyordu.
    static let contentTopInset: CGFloat = 6
    static let contentHorizontalInset: CGFloat = 16
    static let contentBottomInset: CGFloat = 24

    /// Kartlar arası boşluk — panodaki satırlarla aynı.
    static let sectionSpacing: CGFloat = 16
}

// MARK: - Kart

/// Ayar kartı — işlemci panosundaki kartlarla aynı dil.
///
/// Eskiden başlık kartın dışında, üstünde küçük gri büyük harflerle
/// duruyordu ve kutunun kendisi düz, gölgesiz bir yüzeydi: Sistem
/// Ayarları'nın görünümü. Pano ise başlığı kartın içine, kalın ve okunur
/// bir satır olarak koyuyor, kartı da cam yüzeyle (`dashboardCard`)
/// çiziyor. İki sayfa aynı pencerede yan yana duruyor; biri gösterge
/// panosu, öteki form gibi görünüyordu.
struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.app(.titleLarge, weight: .semibold))
                            if let subtitle {
                                Text(subtitle)
                                    .font(.app(.body))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .dashboardCard()
    }
}

/// İki sütunlu sayfa düzeni — işlemci panosuyla aynı kural.
///
/// Genişlik yetiyorsa kartlar iki sütunda, yetmiyorsa alt alta. Eşik de
/// panoyla aynı (720): iki sütunu korumak için kartları ezmek, tek
/// sütunda ferah durmaktan kötü.
///
/// `alignsHeights` açıkken iki sütunun dipleri hizalanıyor, kısa sütunun
/// kartları uzuyor — panodaki satırlar gibi. Sütunlardan biri
/// ötekinin birkaç katı uzunsa (ör. kısa bir önizleme ile on dört
/// satırlık bir liste) kapatılıyor; yoksa kısa kart boş bir kutuya döner.
struct SettingsColumns<Leading: View, Trailing: View>: View {
    var alignsHeights = true
    let leading: Leading
    let trailing: Trailing

    init(
        alignsHeights: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.alignsHeights = alignsHeights
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            columns
                .frame(minWidth: 720)

            VStack(alignment: .leading, spacing: 16) {
                leading
                trailing
            }
        }
    }

    @ViewBuilder
    private var columns: some View {
        let row = HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) { leading }
                .frame(maxWidth: .infinity, maxHeight: alignsHeights ? .infinity : nil, alignment: .top)
            VStack(alignment: .leading, spacing: 16) { trailing }
                .frame(maxWidth: .infinity, maxHeight: alignsHeights ? .infinity : nil, alignment: .top)
        }
        if alignsHeights {
            row.fixedSize(horizontal: false, vertical: true)
        } else {
            row
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.09))
            .padding(.vertical, 2)
    }
}

// MARK: - Değerli slider

struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Ekranda gösterilecek biçim — "52 pt", "%110" gibi.
    let format: (Double) -> String
    var step: Double = 1

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.app(.headline))
                Spacer(minLength: 12)
                Text(format(value))
                    .font(.app(.bodyLarge, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.08))
                    }
            }

            HStack(spacing: 10) {
                stepButton(systemName: "minus", delta: -step)
                Slider(value: $value, in: range)
                    .controlSize(.small)
                stepButton(systemName: "plus", delta: step)
            }
        }
        .padding(.vertical, 8)
    }

    private func stepButton(systemName: String, delta: Double) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - İkon önizlemeli toggle

struct IconToggleRow: View {
    let systemName: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: 14))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.3))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                        .strokeBorder(Color.white.opacity(isOn ? 0.14 : 0.06), lineWidth: 1)
                }

            Text(label)
                .font(.app(.headline))
                .foregroundStyle(isOn ? .primary : .secondary)

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Segmentli seçici (tema / dil için)

struct SettingsSegmentedRow<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(value: T, title: String)]

    var body: some View {
        // Etiket ile seçici yan yana sığmadığında (ör. dört seçenekli
        // değiştirici tuşu satırı) seçici alt satıra iner. Daha önce
        // `.fixedSize(horizontal: true, …)` ile seçici sıkışmayı tamamen
        // reddediyordu; bu da ayrıntı sütununu şişirip kenar çubuğunu
        // pencerenin dışına itiyordu.
        ViewThatFits(in: .horizontal) {
            HStack {
                labelText
                Spacer(minLength: 12)
                picker
            }

            VStack(alignment: .leading, spacing: 7) {
                labelText
                picker
            }
        }
        .padding(.vertical, 9)
    }

    private var labelText: some View {
        Text(label)
            .font(.app(.headline))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var picker: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Yalnızca dikeyde sabitlemek gerekiyor: `NSSegmentedControl`
        // köprüsü ilk ölçümde ara sıra çok büyük bir "ideal" dikey boyut
        // raporluyor ve satırın altında/üstünde kocaman boşluk bırakıyordu.
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Sıfırla butonu

struct ResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n.resetDefaults)
                    .font(.app(.body, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
