import SwiftUI
import WidgetKit

/// Masaüstü ve Bildirim Merkezi widget'ları.
///
/// Her ölçer ayrı bir widget: kullanıcı hangisini istiyorsa onu ekliyor,
/// beşi birden dayatılmıyor. Yapılandırma statik — seçilecek bir şey yok,
/// ölçüm zaten makinenin kendisi.
@main
struct GlassDoWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemOverviewWidget()
        DiskWidget()
        NetworkWidget()
        BatteryWidget()
        MemoryWidget()
        ProcessorWidget()
    }
}

/// Bütün temel ölçümleri üçüncü referanstaki gibi tek büyük masaüstü
/// alanında toplar. Ayrı widget'lar seçim özgürlüğü için korunur.
struct SystemOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.dadebay.glassdo.widget.overview",
            provider: SystemProvider()
        ) { entry in
            SystemOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s(
            "Sistem Özeti",
            "System Overview",
            "Обзор системы"
        ))
        .description(s(
            "Ağ, batarya, disk, işlemci ve belleği tek alanda gösterir.",
            "Network, battery, disk, processor, and memory in one dashboard.",
            "Сеть, батарея, диск, процессор и память на одной панели."
        ))
        .supportedFamilies([.systemLarge])
    }
}

private let s = WidgetStrings.system

struct DiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dadebay.glassdo.widget.disk", provider: SystemProvider()) { entry in
            DiskWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s("Disk", "Disk", "Диск"))
        .description(s(
            "Disk doluluğu ve seyri.",
            "Disk usage and its trend.",
            "Заполненность диска и её динамика."
        ))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NetworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dadebay.glassdo.widget.network", provider: SystemProvider()) { entry in
            NetworkWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s("Ağ Trafiği", "Network Data", "Сетевой трафик"))
        .description(s(
            "Bugün, dün ve son 30 günde harcanan veri.",
            "Data used today, yesterday and over the last 30 days.",
            "Трафик за сегодня, вчера и последние 30 дней."
        ))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dadebay.glassdo.widget.battery", provider: SystemProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s("Batarya", "Battery", "Батарея"))
        .description(s(
            "Şarj durumu, sağlık ve döngü sayısı.",
            "Charge level, health and cycle count.",
            "Уровень заряда, здоровье и число циклов."
        ))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MemoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dadebay.glassdo.widget.memory", provider: SystemProvider()) { entry in
            MemoryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s("Bellek", "Memory", "Память"))
        .description(s(
            "Kullanılan RAM ve dağılımı.",
            "Used memory and its breakdown.",
            "Использованная память и её структура."
        ))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProcessorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.dadebay.glassdo.widget.processor", provider: SystemProvider()) { entry in
            ProcessorWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(s("İşlemci Sıcaklığı", "Processor Temperature", "Температура ЦП"))
        .description(s(
            "Çekirdek sıcaklığı ve termal baskı.",
            "Core temperature and thermal pressure.",
            "Температура ядер и термальная нагрузка."
        ))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
