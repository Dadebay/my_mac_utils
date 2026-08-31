import GlassDoKit
import SwiftUI
import WidgetKit

/// Masaüstü ve Bildirim Merkezi widget'larının önizlemesi.
///
/// Buradaki kartlar widget uzantısındaki görünümlerin **kendisi**
/// (`Sources/Widgets`), yalnızca boyutu elle veriliyor. Ayrı bir önizleme
/// çizilseydi widget değiştikçe burası yalan söylemeye başlardı.
struct WidgetsSettingsSection: View {
  private let controller = SystemStatsController.shared
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var entry: SystemEntry {
    SystemEntry(
      date: Date(),
      snapshot: SystemSnapshot(
        date: Date(),
        cpu: controller.cpu,
        memory: controller.memory,
        disk: controller.disk,
        battery: controller.battery,
        network: controller.network,
        device: controller.device,
        language: L10n.language.rawValue
      )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(
        title: L10n.s(
          "Masaüstü ve Bildirim Merkezi",
          "Desktop and Notification Center",
          "Рабочий стол и Центр уведомлений"
        )
      ) {
        setupHint
          .padding(.vertical, 4)
      }

      previewSection

      SettingsCard(
        title: L10n.s("Nasıl güncelleniyor?", "How they refresh", "Как они обновляются"),
        subtitle: nil
      ) {
        VStack(alignment: .leading, spacing: 8) {
          hint(
            symbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            text: L10n.s(
              "Widget’ları macOS yeniler; sıklığı sistem belirler, yaklaşık beş dakikada bir.",
              "macOS refreshes widgets; the system sets the pace, roughly every five minutes.",
              "Виджеты обновляет macOS; частоту задаёт система — примерно раз в пять минут."
            )
          )
          hint(
            symbolName: "thermometer.medium",
            text: L10n.s(
              "Sıcaklık ve “bugün / son 30 gün” ağ toplamları GlassDo çalışırken ölçülüp widget’a bırakılır; bellek, disk ve batarya uygulama kapalıyken de okunur.",
              "Temperature and the today / last 30 days network totals are measured while GlassDo runs; memory, disk and battery are read even when the app is closed.",
              "Температура и сетевые итоги за сегодня / 30 дней измеряются, пока работает GlassDo; память, диск и батарея читаются и при закрытом приложении."
            )
          )
        }
        .padding(.vertical, 2)
      }
    }
    .task { controller.start() }
    .onDisappear { controller.stop() }
  }

  // MARK: - Kurulum

  private var setupHint: some View {
    HStack(alignment: .top, spacing: 12) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(0.07))
        .frame(width: 36, height: 36)
        .overlay {
          Image(systemName: "rectangle.grid.2x2")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
        }

      Text(
        L10n.s(
          "Masaüstüne sağ tıklayıp “Widget’ları Düzenle”yi seç, sonra listeden GlassDo’yu bul.",
          "Right-click the desktop, choose “Edit Widgets”, then find GlassDo in the list.",
          "Нажмите правой кнопкой на рабочем столе, выберите «Изменить виджеты» и найдите GlassDo."
        )
      )
      .font(.system(size: 12.5))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
  }

  // MARK: - Önizleme

  /// Kartın kendi kutusuyla `SettingsCard`'ın kutusu üst üste binmesin
  /// diye bu bölüm `SettingsCard` sarmalayıcısını kullanmıyor — yalnızca
  /// aynı küçük büyük harfli başlık kuralını elle tekrar ediyor.
  private var previewSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.previewGroup)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .kerning(0.4)
        .padding(.horizontal, 2)

      previewCanvas
    }
  }

  /// Referans tasarımdaki doygun duvar kâğıdı zemini kaldırıldı: widget
  /// içindeki metnin okunabilirliğini test etmek için renkli bir zemin
  /// gerekmiyor, üstelik iki widget arası hizayı bozan bir görsel gürültü
  /// ekliyordu. Nötr, sistemin kendi malzemesine yakın bir tuval yeterli.
  private var previewCanvas: some View {
    VStack(alignment: .leading, spacing: 16) {
      previewGroupHeader(
        L10n.s("Sistem Özeti", "System Overview", "Обзор системы"),
        detail: L10n.s("Büyük", "Large", "Большой")
      )

      HStack {
        Spacer(minLength: 0)
        WidgetPreviewTile(nativeSize: WidgetNativeSize.large) {
          SystemOverviewWidgetView(entry: entry)
        }
        Spacer(minLength: 0)
      }

      Divider()
        .overlay(Color.primary.opacity(0.07))

      previewGroupHeader(
        L10n.s("Tekil Widget’lar", "Individual Widgets", "Отдельные виджеты"),
        detail: nil
      )

      // Orta boy önizleme 329 pt'lik gerçek widget'tan yalnızca çok
      // hafif küçüktür. İki sütun sığmadığında grid tek sütuna düşer;
      // hiçbir kart mevcut genişliği doldurmak için büyütülmez.
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(
              minimum: WidgetPreviewMetrics.mediumDisplayWidth,
              maximum: WidgetPreviewMetrics.mediumDisplayWidth
            ),
            spacing: 12
          )
        ],
        alignment: .center,
        spacing: 12
      ) {
        WidgetPreviewTile(
          nativeSize: WidgetNativeSize.medium,
          displayWidth: WidgetPreviewMetrics.mediumDisplayWidth
        ) {
          DiskWidgetView(entry: entry, forcedFamily: .systemMedium)
        }
        WidgetPreviewTile(
          nativeSize: WidgetNativeSize.medium,
          displayWidth: WidgetPreviewMetrics.mediumDisplayWidth
        ) {
          NetworkWidgetView(entry: entry, forcedFamily: .systemMedium)
        }
        WidgetPreviewTile(
          nativeSize: WidgetNativeSize.medium,
          displayWidth: WidgetPreviewMetrics.mediumDisplayWidth
        ) {
          ProcessorWidgetView(entry: entry, forcedFamily: .systemMedium)
        }
        HStack(spacing: 12) {
          WidgetPreviewTile(
            nativeSize: WidgetNativeSize.small,
            displayWidth: WidgetPreviewMetrics.smallDisplayWidth
          ) {
            BatteryWidgetView(entry: entry, forcedFamily: .systemSmall)
          }
          WidgetPreviewTile(
            nativeSize: WidgetNativeSize.small,
            displayWidth: WidgetPreviewMetrics.smallDisplayWidth
          ) {
            MemoryWidgetView(entry: entry, forcedFamily: .systemSmall)
          }
        }
        .frame(width: WidgetPreviewMetrics.mediumDisplayWidth, alignment: .center)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.primary.opacity(reduceTransparency ? 0.065 : 0.03))
        .overlay {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
  }

  private func previewGroupHeader(_ title: String, detail: String?) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.secondary)

      Spacer(minLength: 8)

      if let detail {
        Text(detail)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.primary.opacity(0.055)))
      }
    }
  }

  private func hint(symbolName: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: symbolName)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 16)
      Text(text)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Native ölçüler

/// macOS'un gerçek widget ölçüleri. Kartlar bu boyutta çizilip ölçekleniyor:
/// küçültülmüş bir düzen yerine gerçek düzenin küçüğü görünsün — yazı boyu
/// oranları da aynı kalsın.
private enum WidgetNativeSize {
  static let small = CGSize(width: 155, height: 155)
  static let medium = CGSize(width: 329, height: 155)
  static let large = CGSize(width: 345, height: 345)
}

private enum WidgetPreviewMetrics {
  /// Preview canvas'ın 652 pt'lik tipik iç genişliğine iki kartın
  /// aralarındaki 12 pt ile birlikte sığdığı değer: 312 + 12 + 312.
  static let mediumDisplayWidth: CGFloat = 312
  static let smallDisplayWidth: CGFloat = 150
  static let contentInset: CGFloat = 14
}

/// Bir widget'ı native ölçüsünde çizip mevcut genişliğe göre ölçekler.
///
/// Önceki sürüm sabit bir `scaleEffect(0.5)` kullanıyordu: bu, yalnızca
/// önizlemenin çizildiği tek bir sütun genişliğinde doğruydu. Pencere
/// daralınca (ya da sütun sırası değişince) ölçek aynı kalıyor, gerçek
/// widget'lar container'dan taşıyordu.
///
/// Widget'ı kendi doğal boyutunda düzenleyip tek parça halinde hedef genişliğe
/// ölçekler. Genişlik doğal boyutta sınırlandığı için önizleme hiçbir zaman
/// büyüyüp taşmaz; dış frame de görünen kartın gerçek ölçüsüyle birebir kalır.
private struct WidgetPreviewTile<Content: View>: View {
  let nativeSize: CGSize
  var displayWidth: CGFloat?
  @ViewBuilder let content: () -> Content

  private var fittedWidth: CGFloat {
    min(displayWidth ?? nativeSize.width, nativeSize.width)
  }

  private var scale: CGFloat {
    fittedWidth / nativeSize.width
  }

  private var fittedHeight: CGFloat {
    nativeSize.height * scale
  }

  var body: some View {
    content()
      // WidgetKit gerçek widget'ta içerik marjını sistemden verir.
      // Ayarlar önizlemesi widget bağlamı dışında olduğu için aynı
      // nefes alanını burada taklit etmezsek başlık ve grafikler kart
      // kenarına yapışıp kırpılmış görünür.
      .padding(WidgetPreviewMetrics.contentInset)
      .frame(width: nativeSize.width, height: nativeSize.height, alignment: .topLeading)
      .background {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Color.black.opacity(0.72))
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
          }
      }
      .environment(\.colorScheme, .dark)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      // Ölçek 1'i hiçbir zaman geçmez. Önceki implementation tam
      // sütun genişliğini native genişliğe bölüp 2× büyüttüğü için
      // medium widget'lar ekranın tamamını kaplıyordu.
      .scaleEffect(scale, anchor: .topLeading)
      // `scaleEffect` layout ölçüsünü değiştirmez; bu dış frame görünen
      // ölçüyü layout'a da bildirir ve komşu kartların üst üste
      // binmesini engeller.
      .frame(width: fittedWidth, height: fittedHeight, alignment: .topLeading)
      .clipShape(
        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
      )
  }
}
