import Foundation

/// İşlemci yükü — çekirdeğin biriktirdiği tik sayaçlarının iki örnek
/// arasındaki farkından hesaplanır, o yüzden ilk örnekte hep 0'dır.
struct CPULoadStats: Equatable, Sendable, Codable {
    /// 0…1 arası toplam kullanım (tüm çekirdeklerin ortalaması).
    var usage: Double = 0
    /// Kullanıcı alanı ve çekirdek payları ayrı ayrı — yüksek sistem payı
    /// toplam yükle aynı şeyi anlatmaz, ayrı okunabilmeli.
    var userUsage: Double = 0
    var systemUsage: Double = 0
    /// Son ölçümler, en eskisi başta — çubuk grafiği için.
    var history: [Double] = []
    /// Aynı geçmişin kullanıcı/sistem katmanlı hâli.
    var layeredHistory: [[Double]] = []
    var coreCount: Int = 0

    /// `ProcessInfo.thermalState` karşılığı. Apple Silicon'da gerçek çekirdek
    /// sıcaklığı yalnızca özel API'lerle okunabildiği için sayı yerine
    /// sistemin kendi bildirdiği aralık gösteriliyor.
    var thermalPressure: ThermalPressure = .nominal

    /// Gerçek çekirdek sıcaklığı (°C). Apple Silicon'da IOHID sensörlerinden,
    /// Intel'de SMC'den okunur; ikisi de yoksa nil kalır ve yalnızca
    /// `thermalPressure` gösterilir — uydurma bir sayı yazılmaz.
    var temperature: Double?
    /// Sıcaklığın seyri, en eskisi başta — çubuk grafiği için.
    var temperatureHistory: [Double] = []

    /// Her mantıksal çekirdeğin **o andaki** yükü, 0…1. Dizinin sırası
    /// çekirdek sırasıdır (0 = ilk mantıksal çekirdek).
    ///
    /// `history` ile karıştırılmamalı: orası zamanın seyri, burası tek bir
    /// anın çekirdekler arasındaki dağılımı. İkisi farklı soru yanıtlıyor —
    /// "ne zaman yüklendi" ile "hangi çekirdek yüklü".
    var perCoreUsage: [Double] = []

    private enum CodingKeys: String, CodingKey {
        case usage, userUsage, systemUsage, history, layeredHistory, coreCount
        case thermalPressure, temperature, temperatureHistory, perCoreUsage
    }

    init() {}

    /// Diskteki eski anlık görüntüler yeni alanları tanımıyor. Üretilen
    /// çözümleyici eksik anahtarda hata fırlatıyor ve tek bir yeni alan
    /// yüzünden **bütün** anlık görüntü okunamaz hâle geliyor — widget da
    /// hiç veri yokmuş gibi davranırdı. Bu yüzden her alan tek tek, yoksa
    /// varsayılanıyla okunuyor.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usage = try container.decodeIfPresent(Double.self, forKey: .usage) ?? 0
        userUsage = try container.decodeIfPresent(Double.self, forKey: .userUsage) ?? 0
        systemUsage = try container.decodeIfPresent(Double.self, forKey: .systemUsage) ?? 0
        history = try container.decodeIfPresent([Double].self, forKey: .history) ?? []
        layeredHistory = try container.decodeIfPresent([[Double]].self, forKey: .layeredHistory) ?? []
        coreCount = try container.decodeIfPresent(Int.self, forKey: .coreCount) ?? 0
        thermalPressure = try container.decodeIfPresent(ThermalPressure.self, forKey: .thermalPressure) ?? .nominal
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        temperatureHistory = try container.decodeIfPresent([Double].self, forKey: .temperatureHistory) ?? []
        perCoreUsage = try container.decodeIfPresent([Double].self, forKey: .perCoreUsage) ?? []
    }
}

enum ThermalPressure: Sendable, Equatable, Codable {
    case nominal, fair, serious, critical
}

/// Önyükleme diski. APFS'te `/` salt okunur sistem birimidir ve her zaman
/// ~%3 dolu görünür; kullanıcının gerçekten doldurduğu yer veri birimidir.
struct DiskStats: Equatable, Sendable, Codable {
    var volumeName: String = ""
    var total: UInt64 = 0
    var used: UInt64 = 0
    /// Doluluk oranının zaman içindeki seyri.
    var history: [Double] = []

    var free: UInt64 { total > used ? total - used : 0 }

    var usedFraction: Double {
        total == 0 ? 0 : min(Double(used) / Double(total), 1)
    }
}

/// Batarya sağlığı ve anlık elektriksel durumu.
///
/// Sağlık yüzdesi, bataryanın bugün tutabildiği şarjın fabrika kapasitesine
/// oranıdır; şu anki doluluk oranıyla karıştırılmamalı — ikisi ayrı alanda.
struct BatteryStats: Equatable, Sendable, Codable {
    /// Bataryanın şu an tutabildiği en yüksek şarj (mAh).
    var currentCapacity: UInt64 = 0
    /// Fabrika çıkışı tasarım kapasitesi (mAh).
    var designCapacity: UInt64 = 0
    /// Şu anki doluluk (mAh) ve yüzdesi.
    var charge: UInt64 = 0
    var chargePercent: Int = 0
    var cycleCount: Int = 0
    var isPresent: Bool = false
    var hasPermanentFailure: Bool = false

    /// Santigrat derece.
    var temperature: Double = 0
    /// Volt. Negatif akım deşarjı gösterir.
    var voltage: Double = 0
    var amperage: Double = 0
    /// Watt — gerilim ve akımın çarpımı, işareti akımdan gelir.
    var power: Double { voltage * amperage }

    var isAdapterConnected: Bool = false
    var isCharging: Bool = false
    /// Dakika cinsinden kalan süre; sistem hesaplayamadığında nil.
    var minutesRemaining: Int?

    var healthHistory: [Double] = []

    /// 0…1 arası sağlık. Yeni bataryalarda 1'in biraz üstüne çıkabildiği
    /// için üstten kırpılıyor.
    var healthFraction: Double {
        designCapacity == 0 ? 0 : min(Double(currentCapacity) / Double(designCapacity), 1)
    }

    /// Apple'ın "Servis Önerilir" eşiği %80'dir.
    var condition: BatteryCondition {
        if hasPermanentFailure { return .service }
        let percent = healthFraction * 100
        if percent >= 95 { return .perfect }
        if percent >= 85 { return .good }
        if percent >= 80 { return .fair }
        return .service
    }
}

enum BatteryCondition: Sendable, Codable {
    case perfect, good, fair, service
}

/// Ağ trafiği. Çekirdeğin arayüz sayaçları her yeniden başlatmada sıfırlanır,
/// bu yüzden günlük toplamlar `NetworkHistoryStore` tarafından ayrıca
/// biriktirilir — geçmiş yalnızca uygulama çalışırken dolar.
struct NetworkStats: Equatable, Sendable, Codable {
    /// Açılıştan beri biriken ham sayaçlar.
    var totalReceived: UInt64 = 0
    var totalSent: UInt64 = 0
    /// Son iki örnek arasındaki anlık hız (bayt/saniye).
    var downloadRate: Double = 0
    var uploadRate: Double = 0

    var today: UInt64 = 0
    var yesterday: UInt64 = 0
    var last7Days: UInt64 = 0
    var last30Days: UInt64 = 0

    /// Son 30 günün günlük toplamları, en eskisi başta — çubuk grafiği için.
    var dailyTotals: [UInt64] = []
    /// Anlık hızın seyri (bayt/saniye), sıfır çizgisinin iki yanı.
    var downloadHistory: [Double] = []
    var uploadHistory: [Double] = []

    /// Etkin bağlantının türü ve yerel adresi.
    var interfaceName: String = ""
    var localAddress: String = ""
    /// Bir VPN tüneli ayakta mı — menü çubuğundaki VPN göstergesi için.
    var isVPNActive: Bool = false
}

/// Belleğin çekirdek sayaçlarından okunan dökümü. Süreç başına ölçümle
/// karıştırılmıyor — ikisi farklı muhasebe.
struct MemoryStats: Equatable, Sendable, Codable {
    var total: UInt64 = 0
    /// Yakın zamanda kullanılmış anonim sayfalar.
    var active: UInt64 = 0
    /// Diske taşınamayan çekirdek/sürücü belleği.
    var wired: UInt64 = 0
    /// Sıkıştırılarak yerden kazanılmış sayfalar.
    var compressed: UInt64 = 0
    /// Dosya önbelleği — baskı altında anında bırakılabilir.
    var cached: UInt64 = 0
    var free: UInt64 = 0

    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    var history: [[Double]] = []

    /// Etkinlik İzleyicisi'ndeki "Kullanılan Bellek" tanımı: önbellek dahil
    /// değil, çünkü baskı altında hemen boşaltılıyor.
    var used: UInt64 { active &+ wired &+ compressed }

    var usedFraction: Double {
        total == 0 ? 0 : min(Double(used) / Double(total), 1)
    }

    /// Bellek baskısı: sistemin gerçekten sıkışıp sıkışmadığını gösteren
    /// tek sayı. Sıkıştırılmış ve çivilenmiş sayfalar boşaltılamadığı için
    /// baskıyı onlar belirler — toplam kullanım değil.
    var pressureFraction: Double {
        total == 0 ? 0 : min(Double(wired &+ compressed) / Double(total), 1)
    }
}

/// Makinenin kendisiyle ilgili, başka hiçbir ölçere ait olmayan değerler.
struct DeviceStats: Equatable, Sendable, Codable {
    /// Son açılıştan beri geçen süre (saniye).
    var uptime: TimeInterval = 0
}
