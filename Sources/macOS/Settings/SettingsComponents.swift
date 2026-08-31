import SwiftUI
import GlassDoKit

// MARK: - Ortak ölçüler

/// Ayarlar penceresinin ölçü sistemi.
///
/// Aynı sayı üç ayrı dosyada elle tekrarlandığında zamanla ayrışıyor:
/// kenar çubuğu bir hizada, sağdaki içerik başka bir hizada başlıyor.
/// Buradaki her değer bir kere tanımlanıp her iki sütunda da okunuyor.
enum SettingsMetrics {
    /// Başlık çubuğunun altından sayfa başlığına. Tüm bölümler aynı
    /// `detail` kabuğunu paylaştığı için bu değer hepsinde aynı — sayfa
    /// değiştirirken başlığın yeri oynamıyor.
    static let contentTopInset: CGFloat = 14
    static let contentHorizontalInset: CGFloat = 28
    static let contentBottomInset: CGFloat = 32

    /// Okunabilirlik sınırı: geniş ekranda satırlar pencerenin karşı
    /// ucuna kadar uzamıyor, içerik sola yaslı kalıyor.
    static let contentMaxWidth: CGFloat = 740

    /// Sayfa başlığı ile ilk bölüm, ve bölümlerin kendi araları.
    static let sectionSpacing: CGFloat = 24
}

// MARK: - Kart

struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(0.4)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    }
            }
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
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Text(format(value))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: 14))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.3))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(isOn ? 0.14 : 0.06), lineWidth: 1)
                }

            Text(label)
                .font(.system(size: 13))
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
            .font(.system(size: 13))
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
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
