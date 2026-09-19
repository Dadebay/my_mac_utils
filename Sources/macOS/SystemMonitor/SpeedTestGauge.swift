import GlassDoKit
import SwiftUI

/// Hız testinin dairesel kadranı. `SpeedTestSection`'ın sayı + çubuk
/// sunumunun yanında, geniş yerleşimlerde kullanılan büyük gösterge.
///
/// Ölçüleri `diameter`'a oranlı: kadran farklı boyutlarda çizildiğinde
/// yazıların birbirine göre dengesi bozulmasın diye sabit punto yok.
struct SpeedTestGauge: View {
    /// Test sürerken canlı, bittiğinde son ölçüm.
    var bitsPerSecond: Double
    /// 0...1. Test sürmüyorken yay tam dolu çizilir.
    var progress: Double
    var isRunning: Bool
    /// Kadranın altındaki açıklama — evre adı ya da son test zamanı.
    var caption: String
    var diameter: CGFloat = 148
    var accent: Color = Color(red: 0.36, green: 0.64, blue: 0.98)
    /// Kadranın kendisi düğme: üzerine gelince ortadaki sayının yerine ne
    /// olacağını söyleyen yazı geçiyor, tıklayınca da o oluyor. Ayrı bir
    /// düğme koymak, gözün zaten baktığı yerden eylemi uzaklaştırıyordu.
    var actionTitle: String = ""
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var arrived = false
    @State private var isHovering = false

    private let arrivalSpring = Animation.spring(response: 0.3, dampingFraction: 0.62)

    /// Henüz hiç ölçüm yoksa sayı yerine tire gösteriliyor; yazı da
    /// büyüyor, çünkü tek karakter küçük puntoda kaybolmuş görünüyordu.
    private var hasReading: Bool { bitsPerSecond > 0 }

    private var trackWidth: CGFloat { diameter * 0.075 }

    var body: some View {
        VStack(spacing: diameter * 0.06) {
            if let action {
                Button(action: action) { dial }
                    .buttonStyle(.plain)
                    .help(actionTitle)
                    .accessibilityLabel(actionTitle)
            } else {
                dial
            }
        }
        .onHover { isHovering = $0 }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isRunning) { _, running in
            startPulseIfNeeded()
            playArrival(!running)
        }
        .onChange(of: reduceMotion) { _, _ in startPulseIfNeeded() }
    }

    /// Ölçek kaç çentikten oluşuyor. Sayı çapa bağlı değil: çentikler
    /// küçüldükçe incelip sıklaşmıyor, hep aynı ritimde duruyorlar.
    private static let tickCount = 60

    private var dial: some View {
        ZStack {
            // Tek bir kalın yay yerine çentikler: dolan kısım burada bir
            // çizginin uzaması değil, tek tek yanan işaretler — ilerlemenin
            // kendisi sayılabilir hâle geliyor.
            ticks
            readout
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // Üzerine gelince kadran bir tık büyüyor: tıklanabilir olduğunu
        // söyleyen ikinci ipucu, yazının yanında.
        .scaleEffect(arrived ? 1.04 : (isHovering && !isRunning ? 1.02 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }

    private var ticks: some View {
        let filled = isRunning ? max(min(progress, 1), 0) : 1

        return ZStack {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                let isLit = Double(index) / Double(Self.tickCount) < filled

                Capsule()
                    .fill(
                        isLit
                            ? accent.opacity(isRunning && pulse ? 1 : 0.9)
                            : Color.primary.opacity(0.10)
                    )
                    .frame(width: trackWidth * 0.34, height: trackWidth)
                    // Çentik dairenin kenarına yaslanıyor: yarıçap kadar
                    // yukarı taşınıp merkez etrafında döndürülüyor.
                    .offset(y: -(diameter - trackWidth) / 2)
                    .rotationEffect(.degrees(Double(index) / Double(Self.tickCount) * 360))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : Motion.dataUpdate, value: filled)
    }

    @ViewBuilder
    private var readout: some View {
        // Test sürerken yazı değişmiyor: o an basılacak şey "durdur" ve o
        // kadranın içinde değil, yanındaki düğmede.
        if isHovering, !isRunning, action != nil, !actionTitle.isEmpty {
            Text(actionTitle)
                .font(.app(size: diameter * 0.105, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, diameter * 0.12)
                .transition(.opacity)
        } else {
            numericReadout
        }
    }

    private var numericReadout: some View {
        VStack(spacing: 1) {
            Text(hasReading ? Self.megabits(bitsPerSecond) : "—")
                .font(.app(size: diameter * 0.2, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.5)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("Mbps")
                .font(.app(size: diameter * 0.072, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion, isRunning else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    /// Test bitince kadranın tek seferlik "geldi" taşması. Kesintiye
    /// açık: kullanıcı hemen "Tekrar Test Et"e basarsa devam eden
    /// hareket, yeni durumun üstüne atlamadan aynı yay üzerinden geri
    /// dönüyor (yayların kendi doğası — mevcut değerden devam ederler).
    private func playArrival(_ finished: Bool) {
        guard finished, !reduceMotion else { return }
        withAnimation(arrivalSpring) { arrived = true }
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(260))
            withAnimation(arrivalSpring) { arrived = false }
        }
    }

    // MARK: - Biçimlendirme

    /// `SpeedTestSection` ile aynı kural: yüzün altında ondalık bilgi taşır,
    /// üstünde gürültüye dönüşür.
    static func megabits(_ bitsPerSecond: Double) -> String {
        let mbps = max(bitsPerSecond, 0) / 1_000_000
        return mbps >= 100
            ? String(format: "%.0f", mbps)
            : String(format: "%.1f", mbps)
    }
}
