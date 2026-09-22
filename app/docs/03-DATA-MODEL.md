# 03 — Veri Modeli

> **Kapsam güncellemesi:** iCloud/CloudKit sync kapsam dışı — store tamamen
> yerel. Aşağıdaki "CloudKit uyumluluk kuralları" artık zorunlu değil, ama
> yine de iyi pratik oldukları (optional/default alanlar, unique kullanmama)
> için korunuyor — ileride CloudKit eklenmek istenirse şema hazır olsun diye.

## SwiftData model kuralları

1. Her property ya **optional** olacak ya da **default değeri** olacak
2. Her ilişkinin **inverse**'ü tanımlı ve optional olmalı
3. Enum'lar `Codable` + `RawRepresentable` olmalı (String raw value öneriyorum)

## Modeller

> **✅ Faz 2'de uygulandı** — `Sources/GlassDoKit/Models/{Task,Project,Tag,Priority}.swift`.
> `GlassDoKit` bir framework olduğu için tüm tipler/property'ler `public`.

```swift
import SwiftData
import Foundation

@Model
public final class Task {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var isCompleted: Bool = false
    public var createdAt: Date = Date()
    public var completedAt: Date?
    public var dueDate: Date?
    public var priorityRaw: String = Priority.none.rawValue
    public var sortIndex: Int = 0

    @Relationship(inverse: \Project.tasks)
    public var project: Project?

    @Relationship(inverse: \Tag.tasks)
    public var tags: [Tag]? = []

    public var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    public init(title: String = "", project: Project? = nil) {
        self.title = title
        self.project = project
    }
}

@Model
public final class Project {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#5E9BFF"
    public var symbolName: String = "folder"
    public var sortIndex: Int = 0
    public var isArchived: Bool = false
    public var tasks: [Task]? = []

    public init(name: String = "") { self.name = name }
}

@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#8E8E93"
    public var tasks: [Task]? = []

    public init(name: String = "") { self.name = name }
}

public enum Priority: String, Codable, CaseIterable, Sendable {
    case none, low, medium, high

    public var symbolName: String {
        switch self {
        case .none:   "circle"
        case .low:    "arrow.down"
        case .medium: "equal"
        case .high:   "exclamationmark"
        }
    }
}
```

## Başlangıç projeleri (seed data)

Mevcut listen bunlara karşılık geliyor — ilk açılışta oluştur:

| Proje | Renk | Sembol | Örnek görevler |
|---|---|---|---|
| İş / Aykitap | `#5E9BFF` | `briefcase` | provider kod, platform güncelleme |
| Food Delivery | `#FF9F43` | `bicycle` | geocoding, kurye ödeme, endpoint |
| Shipaton | `#8B5CF6` | `car` | nav bar animasyon, firebase landing, splash |
| Öğrenme | `#34C759` | `book` | React Native dersleri, YouTube kanalı |
| Freelance | `#FF453A` | `dollarsign` | Atelyam, Samalyot, Salon app |
| Kişisel | `#64D2FF` | `person` | Zagran, banka kartı, sakamoto |

Tam liste: [11-SEED-DATA.md](11-SEED-DATA.md)

## ModelContainer kurulumu

> **✅ Faz 2'de uygulandı** — `Sources/GlassDoKit/Store/AppStore.swift`.
> CloudKit kapsam dışı olduğu için `groupContainer`/`cloudKitDatabase`
> **kullanılmıyor**; sadece `inMemory` (testler) ve varsayılan yerel store var.
> `appGroupID` sabiti Faz 7'de widget extension eklendiğinde devreye girecek.

```swift
// GlassDoKit/Store/AppStore.swift
import SwiftData

public enum AppStore {
    public static let appGroupID = "group.com.dadebay.glassdo"

    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Task.self, Project.self, Tag.self])

        let config: ModelConfiguration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            ModelConfiguration(schema: schema)
        }

        let container = try ModelContainer(for: schema, configurations: [config])
        if !inMemory { SeedData.populateIfNeeded(container: container) }
        return container
    }
}
```

`inMemory: true` testler için — hızlı, izole çalışır.

## Sık kullanılan sorgular

> **Bilinen tuzak (doğrulandı, Faz 2 testinde bulundu):** `#Predicate` içinde
> **force-unwrap (`task.dueDate!`) çalışma anında crash eder** —
> `SwiftDataError.unsupportedPredicate: ForcedUnwrap operator is not supported`.
> `?? Date.distantPast` gibi bir nil-coalescing da derleme hatası veriyor
> (`Comparison` ile birleşince macro genişlemesi başarısız oluyor). Çalışan
> tek yöntem **`.flatMap`**:

```swift
// Bugün: süresi bugün veya geçmiş, tamamlanmamış
public static func todayPredicate(now: Date = .now) -> Predicate<Task> {
    let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
    return #Predicate<Task> { task in
        !task.isCompleted && (task.dueDate.flatMap { $0 < end } ?? true)
    }
}

// Widget için: en yüksek öncelikli ilk 5
@Query(filter: Task.todayPredicate(),
       sort: [SortDescriptor(\Task.priorityRaw, order: .reverse),
              SortDescriptor(\Task.sortIndex)])
var todayTasks: [Task]
```

## Migrasyon

v1'de şemayı sabitle. Değişiklik gerekirse `VersionedSchema` + `SchemaMigrationPlan`
kullan — hafif (lightweight) migrasyon çoğu alan ekleme durumunda otomatik çalışır.
