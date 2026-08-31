# 06 — Liquid Glass Tasarım Sistemi

macOS 26 / iOS 26 ile gelen native cam katman API'leri. Elle blur taklidi yapılmayacak.

## Temel API'ler

```swift
// Tek bir cam yüzey
someView
    .glassEffect(.regular, in: .rect(cornerRadius: 22))

// Renk tonlu + dokunmaya tepki veren
someView
    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)

// Daha koyu/belirgin varyant
someView
    .glassEffect(.clear, in: .circle)

// Birden fazla cam öğeyi birlikte yönet → yaklaşınca birleşirler (morph)
GlassEffectContainer(spacing: 14) {
    HStack(spacing: 14) {
        Button(...).glassEffect(.regular, in: .circle).glassEffectID("a", in: ns)
        Button(...).glassEffect(.regular, in: .circle).glassEffectID("b", in: ns)
    }
}

// Hazır stiller
Button("Ekle") { }.buttonStyle(.glass)
Button("Ekle") { }.buttonStyle(.glassProminent)
```

`@Namespace private var ns` ile `glassEffectID` birlikte kullanılır; collapsed →
expanded geçişinde kapsülün karta **dönüşmesi** bununla olur.

## Kullanım kuralları

**Kullan:**
- Floating panel gövdesi
- Menü bar popover'ı
- Quick Add penceresi
- Sidebar arka planı
- Yüzen aksiyon butonları, toolbar

**Kullanma:**
- İçerik satırlarının ardına (görev satırları düz olsun — cam üstüne cam okunmuyor)
- Uzun metin blokları arkasına
- İç içe (cam içinde cam) — birini seç

Apple'ın kuralı: cam **kontrol katmanı** içindir, **içerik katmanı** için değil.

## Token'lar

```swift
// GlassDoKit/DesignSystem/Tokens.swift
public enum Layout {
    public static let panelCornerRadius: CGFloat = 22
    public static let cardCornerRadius: CGFloat = 16
    public static let rowHeight: CGFloat = 34
    public static let gutter: CGFloat = 14
    public static let tightGutter: CGFloat = 8
}

public enum Motion {
    public static let expand   = Animation.spring(response: 0.34, dampingFraction: 0.82)
    public static let collapse = Animation.spring(response: 0.28, dampingFraction: 0.9)
    public static let toggle   = Animation.snappy(duration: 0.2)
}

public enum Palette {
    public static let projectColors = [
        "#5E9BFF", "#FF9F43", "#8B5CF6",
        "#34C759", "#FF453A", "#64D2FF"
    ]
}
```

Renkleri **sabit hex olarak dayatma** — sistem accent rengini ve Dark/Light modu
takip etsin. Sadece proje etiketleri sabit renkli.

## Erişilebilirlik (atlanamaz)

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    content
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22).fill(.background)
            }
        }
        .glassEffect(reduceTransparency ? .clear : .regular,
                     in: .rect(cornerRadius: 22))
        .animation(reduceMotion ? nil : Motion.expand, value: isExpanded)
}
```

Sistem "Transparency'yi azalt" açıkken cam yerine opak yüzey gerekir; aksi halde
metin okunmaz ve App Store review'da erişilebilirlik itirazı gelir.

## Eski OS fallback (istersen)

v1'de gerekmiyor ama deployment target'ı düşürmek istersen:

```swift
public extension View {
    func adaptiveGlass(cornerRadius: CGFloat = 22) -> some View {
        if #available(macOS 26, iOS 26, *) {
            return AnyView(self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)))
        } else {
            return AnyView(self
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)))
        }
    }
}
```

## Karanlık mod

Cam katman zaten arkasındaki içeriğe göre uyum sağlıyor. Sadece şunu doğrula:
panel koyu bir duvar kağıdının üstünde de açık bir Safari penceresinin üstünde de
okunur olmalı. Test: [08-TESTING.md](08-TESTING.md) → manuel checklist.

## Hareket (motion) prensibi

- Genişleme: yukarıdan aşağı **veya** sola doğru, panelin ekran konumuna göre
- Spring kullan, `linear` kullanma
- Tik atma: `.snappy`, satır hafifçe soluklaşıp listeden çıksın
- Panel görünme/kaybolma: opacity + scale 0.96 → 1.0
