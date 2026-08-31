import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case turkish = "tr"
    case russian = "ru"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .turkish: "Türkçe"
        case .russian: "Русский"
        }
    }
}

@Observable
public final class LocalizationManager: @unchecked Sendable {
    public static let shared = LocalizationManager()

    private static let key = "app.language"

    public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
        }
    }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .english
    }
}

public enum L10n {
    public static var language: AppLanguage { LocalizationManager.shared.language }

    public static func s(_ turkish: String, _ english: String, _ russian: String) -> String {
        switch language {
        case .turkish: turkish
        case .english: english
        case .russian: russian
        }
    }

    /// Russian noun/verb agreement depends on the last one/two digits of the count.
    private static func ruPlural(_ n: Int, one: String, few: String, many: String) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    public static var activeTasks: String { s("Görevler", "Tasks", "Задачи") }
    public static var completedTasks: String { s("Tamamlanan", "Completed", "Завершено") }
    public static var folders: String { s("Klasörler", "Folders", "Папки") }

    public static var mainWindowQuickAddPlaceholder: String { s("Yeni görev…", "New task…", "Новая задача…") }
    public static var panelQuickAddPlaceholder: String { s("Hızlı ekle…", "Quick add…", "Быстрое добавление…") }

    public static var emptyTasks: String { s("Görev yok 🎉", "No tasks 🎉", "Нет задач 🎉") }
    public static var emptyCompleted: String { s("Henüz tamamlanan yok", "Nothing completed yet", "Пока ничего не завершено") }
    public static var emptyFoldersHint: String {
        s("Klasör sürükle veya + ile ekle", "Drag a folder here or add with +", "Перетащите папку сюда или добавьте с помощью +")
    }
    public static var addFolder: String { s("Klasör ekle…", "Add folder…", "Добавить папку…") }

    // MARK: - Yönetilen dosya alanı

    public static var newFolder: String { s("Yeni Klasör", "New Folder", "Новая папка") }
    public static var folderNameLabel: String { s("Klasör adı", "Folder Name", "Имя папки") }
    public static var create: String { s("Oluştur", "Create", "Создать") }
    public static var addFiles: String { s("Dosya Ekle", "Add Files", "Добавить файлы") }
    public static var linkExistingFolder: String {
        s("Mevcut Klasörü Bağla…", "Link Existing Folder…", "Связать существующую папку…")
    }
    public static var rename: String { s("Yeniden Adlandır", "Rename", "Переименовать") }
    public static var open: String { s("Aç", "Open", "Открыть") }
    public static var revealInFinder: String { s("Finder'da Göster", "Reveal in Finder", "Показать в Finder") }
    public static var moveToTrash: String { s("Çöp Kutusu'na Taşı", "Move to Trash", "Переместить в Корзину") }
    public static var emptyFolder: String { s("Klasör boş", "Empty Folder", "Папка пуста") }
    public static var dropFilesHere: String { s("Dosyaları buraya bırak", "Drop files here", "Перетащите файлы сюда") }
    public static var copyingFiles: String { s("Kopyalanıyor…", "Copying…", "Копирование…") }
    public static var preview: String { s("Önizleme", "Preview", "Предпросмотр") }

    /// Bağlanmış (dışarıdaki) klasör listeden çıkarılır; kullanıcının
    /// diskindeki klasöre dokunulmaz. Silmekle karıştırılmasın diye
    /// eylemin adı da farklı.
    public static var removeLink: String { s("Bağlantıyı Kaldır", "Remove Link", "Убрать связь") }

    public static func fileCountLabel(_ count: Int) -> String {
        s(
            "\(count) dosya",
            "\(count) file\(count == 1 ? "" : "s")",
            "\(count) " + ruPlural(count, one: "файл", few: "файла", many: "файлов")
        )
    }

    public static func trashConfirmTitle(_ name: String) -> String {
        s("“\(name)” Çöp Kutusu'na taşınsın mı?", "Move “\(name)” to Trash?", "Переместить «\(name)» в Корзину?")
    }

    public static var trashConfirmMessage: String {
        s(
            "Çöp Kutusu'ndan geri alabilirsin.",
            "You can put it back from the Trash.",
            "Вы сможете вернуть это из Корзины."
        )
    }

    public static func removeLinkConfirmTitle(_ name: String) -> String {
        s(
            "“\(name)” listeden kaldırılsın mı?",
            "Remove “\(name)” from the list?",
            "Убрать «\(name)» из списка?"
        )
    }

    public static var removeLinkConfirmMessage: String {
        s(
            "Klasör diskinde olduğu yerde kalır; yalnızca bu listeden çıkar.",
            "The folder stays where it is on disk; only this link is removed.",
            "Папка останется на диске; удаляется только эта связь."
        )
    }

    // Hata metinleri

    public static var storageUnavailable: String {
        s(
            "Dosya alanı açılamadı",
            "Storage unavailable",
            "Хранилище недоступно"
        )
    }

    public static var storageInvalidFolderName: String {
        s(
            "Bu klasör adı kullanılamaz",
            "That folder name can’t be used",
            "Такое имя папки использовать нельзя"
        )
    }

    public static var storageFolderCreationFailed: String {
        s("Klasör oluşturulamadı", "Folder could not be created", "Не удалось создать папку")
    }

    public static func storageCopyFailed(_ name: String) -> String {
        s(
            "“\(name)” kopyalanamadı",
            "“\(name)” could not be copied",
            "Не удалось скопировать «\(name)»"
        )
    }

    public static var storageOutsideStorage: String {
        s(
            "Bu konum GlassDo'nun dosya alanının dışında",
            "That location is outside GlassDo’s storage",
            "Это расположение вне хранилища GlassDo"
        )
    }

    public static var storageDirectoriesNotSupported: String {
        s(
            "Klasör eklenemiyor; şimdilik yalnızca dosyalar",
            "Folders can’t be added yet — files only",
            "Папки пока нельзя добавлять — только файлы"
        )
    }

    public static var selectAList: String { s("Bir liste seç", "Select a list", "Выберите список") }
    public static var selectATask: String { s("Görev seç", "Select a task", "Выберите задачу") }

    public static var themeLabel: String { s("Tema", "Theme", "Тема") }
    public static var languageLabel: String { s("Dil", "Language", "Язык") }
    public static var settingsTitle: String { s("Ayarlar", "Settings", "Настройки") }
    public static var panelSizeSection: String { s("Panel Boyutu", "Panel Size", "Размер панели") }
    public static var iconSizeLabel: String { s("İkon boyutu", "Icon size", "Размер значка") }
    public static var panelWidthLabel: String { s("Panel genişliği", "Panel width", "Ширина панели") }
    public static var panelHeightLabel: String { s("Panel yüksekliği", "Panel height", "Высота панели") }
    public static var railWidthLabel: String { s("Ray genişliği", "Rail width", "Ширина рейки") }
    public static var cornerRadiusLabel: String { s("Köşe yuvarlaklığı", "Corner radius", "Радиус скругления") }
    public static var railIconsSection: String { s("Ray İkonları", "Rail Icons", "Значки рейки") }
    public static var windowSwitcherSection: String { s("Pencere Değiştirici", "Window Switcher", "Переключатель окон") }
    public static var showTasksIconLabel: String { s("Görevler", "Tasks", "Задачи") }
    public static var showAddIconLabel: String { s("Hızlı ekle", "Quick add", "Быстрое добавление") }
    public static var showCompletedIconLabel: String { s("Tamamlanan", "Completed", "Завершено") }
    public static var showFoldersIconLabel: String { s("Klasörler", "Folders", "Папки") }
    public static var showMemoryIconLabel: String { s("RAM Kullanımı", "Memory Usage", "Использование памяти") }
    public static var showNetworkIconLabel: String { s("Ağ Trafiği", "Network Data", "Сетевой трафик") }
    public static var showBatteryIconLabel: String { s("Batarya Sağlığı", "Battery Health", "Состояние батареи") }
    public static var showDiskIconLabel: String { s("Disk", "Disk", "Диск") }
    public static var showProcessorIconLabel: String { s("İşlemci Yükü", "Processor Load", "Загрузка процессора") }
    public static var showPinIconLabel: String { s("Pinle", "Pin", "Закрепить") }
    public static var showSettingsIconLabel: String { s("Ayarlar", "Settings", "Настройки") }
    public static var showWindowSwitcherIconLabel: String { s("Pencere Değiştirici", "Window Switcher", "Переключатель окон") }
    public static var selectedIconCornerRadiusLabel: String {
        s("Seçili ikon köşesi", "Selected icon corner", "Скругление выбранного значка")
    }
    public static var selectedIconPaddingLabel: String {
        s("Seçili ikon boşluğu", "Selected icon padding", "Отступ выбранного значка")
    }

    public static var generalSection: String { s("Genel", "General", "Общие") }
    public static var aboutSection: String { s("Hakkında", "About", "О программе") }
    public static var appearanceGroup: String { s("Görünüm", "Appearance", "Внешний вид") }
    public static var previewGroup: String { s("Önizleme", "Preview", "Предпросмотр") }
    public static var previewHint: String { s("Değişiklikler anında yansır", "Changes apply instantly", "Изменения применяются мгновенно") }
    public static var railGroup: String { s("Ray", "Rail", "Рейка") }
    public static var expandedPanelGroup: String { s("Açılan panel", "Expanded panel", "Развёрнутая панель") }
    public static var visibleIconsGroup: String { s("Görünür ikonlar", "Visible icons", "Видимые значки") }
    public static var iconStyleGroup: String { s("İkon stili", "Icon style", "Стиль значков") }
    public static var resetDefaults: String { s("Sıfırla", "Reset", "Сбросить") }
    public static var versionLabel: String { s("Sürüm", "Version", "Версия") }

    public static func iconCountSummary(_ visible: Int, _ total: Int) -> String {
        s("\(visible) / \(total) görünür", "\(visible) of \(total) shown", "\(visible) из \(total) показано")
    }

    public static var listsSection: String { s("LİSTELER", "LISTS", "СПИСКИ") }
    public static var allCaughtUp: String { s("Hepsi tamam 🎉", "All caught up 🎉", "Все выполнено 🎉") }
    public static var enterHint: String { s("⏎ ile ekle", "⏎ to add", "⏎ чтобы добавить") }
    public static var searchPlaceholder: String { s("Ara", "Search", "Поиск") }
    public static var noSearchResults: String { s("Sonuç yok", "No results", "Нет результатов") }
    public static var collapseSidebar: String { s("Kenar çubuğunu daralt", "Collapse sidebar", "Свернуть боковую панель") }
    public static var expandSidebar: String { s("Kenar çubuğunu genişlet", "Expand sidebar", "Развернуть боковую панель") }
    public static var editTask: String { s("Düzenle", "Edit", "Изменить") }

    public static func activeTaskSummary(_ count: Int) -> String {
        if count == 0 { return allCaughtUp }
        return s(
            "\(count) görev kaldı",
            "\(count) task\(count == 1 ? "" : "s") left",
            "\(count) " + ruPlural(count, one: "задача осталась", few: "задачи остались", many: "задач осталось")
        )
    }

    public static func completedTaskSummary(_ count: Int) -> String {
        s(
            "\(count) görev tamamlandı",
            "\(count) task\(count == 1 ? "" : "s") completed",
            "\(count) " + ruPlural(count, one: "задача выполнена", few: "задачи выполнены", many: "задач выполнено")
        )
    }

    public static func progressSummary(_ done: Int, _ total: Int) -> String {
        s("\(done) / \(total) tamamlandı", "\(done) of \(total) done", "\(done) из \(total) выполнено")
    }

    public static var hideWidget: String { s("Widget'ı Gizle", "Hide Widget", "Скрыть виджет") }
    public static var showWidget: String { s("Widget'ı Göster", "Show Widget", "Показать виджет") }
    public static var pinPanel: String { s("Paneli Pinle", "Pin Panel", "Закрепить панель") }
    public static var unpinPanel: String { s("Pinlemeyi Kaldır", "Unpin Panel", "Открепить панель") }
    public static var mainWindow: String { s("Ana Pencere", "Main Window", "Главное окно") }
    public static var quit: String { s("Çık", "Quit", "Выход") }
    public static var delete: String { s("Sil", "Delete", "Удалить") }
    public static var checkWindowSwitcherPermissions: String {
        s("Pencere Değiştirici — İzinleri Kontrol Et", "Window Switcher — Check Permissions", "Переключатель окон — Проверить разрешения")
    }
    public static var windowSwitcherReady: String {
        s(
            "Pencere Değiştirici Aktif (⌥ basılı tut + Tab)",
            "Window Switcher Active (hold ⌥ + Tab)",
            "Переключатель окон активен (удерживайте ⌥ + Tab)"
        )
    }

    public static var systemSection: String { s("SİSTEM", "SYSTEM", "СИСТЕМА") }
    public static var systemMonitorTitle: String { s("RAM Kullanımı", "Memory Usage", "Использование памяти") }
    public static var systemMonitorEmpty: String { s("Çalışan uygulama yok", "No running apps", "Нет запущенных приложений") }
    public static var cancel: String { s("Vazgeç", "Cancel", "Отмена") }

    public static func systemMonitorSubtitle(_ count: Int) -> String {
        s(
            "\(count) uygulama çalışıyor",
            "\(count) app\(count == 1 ? "" : "s") running",
            "\(count) " + ruPlural(count, one: "приложение запущено", few: "приложения запущены", many: "приложений запущено")
        )
    }

    public static func quitAppConfirmTitle(_ name: String) -> String {
        s("“\(name)” uygulamasını kapatmak istiyor musunuz?", "Quit “\(name)”?", "Закрыть «\(name)»?")
    }

    public static func quitAppHelp(_ name: String) -> String {
        s("“\(name)” uygulamasını kapat", "Quit “\(name)”", "Закрыть «\(name)»")
    }

    public static var memoryUsedLabel: String { s("Kullanılan Bellek", "Memory Used", "Используемая память") }
    public static var memoryTotalLabel: String { s("Toplam RAM", "Total RAM", "Всего ОЗУ") }
    public static var memoryAppsLabel: String { s("Uygulamalar", "Apps", "Приложения") }
    public static var memorySystemLabel: String { s("macOS ve Sistem", "macOS & System", "macOS и система") }
    public static var memoryCachedLabel: String { s("Önbellek", "Cached", "Кэш") }
    public static var memoryFreeLabel: String { s("Boş", "Free", "Свободно") }
    public static var runningAppsLabel: String { s("Çalışan Uygulamalar", "Running Apps", "Запущенные приложения") }

    public static func memoryBreakdownDescription(_ used: String, _ total: String) -> String {
        s("\(total) RAM'in \(used) kadarı kullanılıyor", "\(used) of \(total) RAM in use", "Используется \(used) из \(total) ОЗУ")
    }

    // MARK: - Sistem panosu

    public static var systemOverviewTitle: String { s("Genel Bakış", "Overview", "Обзор") }

    public static var networkDataLabel: String { s("Ağ Trafiği", "Network Data", "Сетевой трафик") }
    public static var networkTodayLabel: String { s("Bugün", "Today", "Сегодня") }
    public static var networkLast7DaysLabel: String { s("Son 7 gün", "Last 7 days", "Последние 7 дней") }
    public static var networkLast30DaysLabel: String { s("Son 30 gün", "Last 30 days", "Последние 30 дней") }
    public static var networkDownloadLabel: String { s("İndirme", "Download", "Загрузка") }
    public static var networkUploadLabel: String { s("Yükleme", "Upload", "Отправка") }

    /// Çekirdek sayaçları her yeniden başlatmada sıfırlandığı için geçmiş
    /// yalnızca uygulama çalışırken birikir — kullanıcı boş değerleri hata
    /// sanmasın diye açıkça söyleniyor.
    public static var networkHistoryHint: String {
        s(
            "Geçmiş yalnızca GlassDo çalışırken birikir",
            "History accumulates only while GlassDo is running",
            "История накапливается только когда GlassDo запущен"
        )
    }

    // MARK: Süreç bazlı ağ kullanımı

    public static var networkTopProcessesLabel: String {
        s("En çok kullananlar", "Top processes", "Больше всего трафика")
    }

    /// Sayaçların anlık hız değil birikmiş toplam olduğunu söylüyor —
    /// kullanıcı "şu an indirmiyorum, bu sayı ne" diye takılmasın.
    public static var networkProcessesHint: String {
        s(
            "Sayaçlar süreç açıldığından beri birikir",
            "Counters accumulate since each process started",
            "Счётчики накапливаются с момента запуска процесса"
        )
    }

    /// `nettop` bazı makinelerde politika ya da yetki nedeniyle hiç
    /// çalışmıyor; bu bir hata değil, ölçümün yokluğu.
    public static var networkProcessesUnavailable: String {
        s(
            "Süreç bazlı ölçüm bu makinede alınamıyor",
            "Per-process measurement is unavailable on this Mac",
            "Измерение по процессам недоступно на этом Mac"
        )
    }

    public static var networkProcessesEmpty: String {
        s("Henüz süreç trafiği ölçülmedi", "No process traffic measured yet", "Трафик процессов пока не измерен")
    }

    public static var networkProcessActivate: String {
        s("Öne getir", "Bring to front", "На передний план")
    }

    public static var networkProcessQuit: String {
        s("Kapat", "Quit", "Завершить")
    }

    public static func networkProcessQuitPrompt(_ name: String) -> String {
        s("“\(name)” kapatılsın mı?", "Quit “\(name)”?", "Завершить «\(name)»?")
    }

    public static var networkProcessQuitMessage: String {
        s(
            "Uygulamaya kapanma isteği gönderilir; kaydedilmemiş işi varsa kendisi sorar.",
            "The app is asked to quit; if it has unsaved work it will ask you first.",
            "Приложению будет отправлен запрос на выход; при несохранённой работе оно спросит вас."
        )
    }

    public static var speedTestLabel: String { s("Hız Testi", "Speed Test", "Тест скорости") }
    public static var speedTestStart: String { s("Testi Başlat", "Run Test", "Запустить тест") }
    public static var speedTestRetry: String { s("Tekrar Test Et", "Test Again", "Повторить тест") }
    public static var speedTestStop: String { s("Durdur", "Stop", "Остановить") }
    public static var speedTestLatencyLabel: String { s("Gecikme", "Latency", "Задержка") }
    public static var speedTestJitterLabel: String { s("Titreşim", "Jitter", "Джиттер") }
    public static var speedTestPhaseLatency: String { s("Gecikme ölçülüyor…", "Measuring latency…", "Измерение задержки…") }
    public static var speedTestPhaseDownload: String { s("İndirme ölçülüyor…", "Measuring download…", "Измерение загрузки…") }
    public static var speedTestPhaseUpload: String { s("Yükleme ölçülüyor…", "Measuring upload…", "Измерение отправки…") }
    public static var speedTestCancelled: String { s("Test durduruldu", "Test stopped", "Тест остановлен") }

    public static func speedTestFailed(_ reason: String) -> String {
        s("Test başarısız: \(reason)", "Test failed: \(reason)", "Тест не удался: \(reason)")
    }

    /// Test gerçek trafik üretir ve arayüz sayaçlarına yansır — kullanıcı
    /// "Bugün" değerindeki sıçramayı hata sanmasın.
    public static var speedTestTrafficNote: String {
        s(
            "Test gerçek veri kullanır ve günlük toplama eklenir",
            "The test uses real data and counts toward your daily total",
            "Тест использует реальный трафик и учитывается в дневном итоге"
        )
    }

    public static var batteryHealthLabel: String { s("Batarya Sağlığı", "Battery Health", "Состояние батареи") }
    public static var batteryCyclesLabel: String { s("Çevrim", "Cycles", "Циклы") }
    public static var batteryUnavailable: String { s("Batarya yok", "No battery", "Нет батареи") }
    public static var batteryConditionLabel: String { s("Durum", "Condition", "Состояние") }
    public static var batteryConditionPerfect: String { s("Mükemmel", "Perfect", "Отличное") }
    public static var batteryConditionGood: String { s("İyi", "Good", "Хорошее") }
    public static var batteryConditionFair: String { s("Orta", "Fair", "Удовлетворительное") }
    public static var batteryConditionService: String { s("Servis gerekli", "Service needed", "Нужно обслуживание") }

    public static var networkYesterdayLabel: String { s("Dün", "Yesterday", "Вчера") }
    public static var networkActivityLabel: String { s("Ağ Etkinliği", "Network Activity", "Сетевая активность") }
    public static var networkConnectionLabel: String { s("Bağlantı", "Connection", "Соединение") }

    public static var batteryLabel: String { s("Batarya", "Battery", "Батарея") }
    public static var batteryTemperatureLabel: String { s("Sıcaklık", "Temperature", "Температура") }
    public static var batteryPowerLabel: String { s("Güç", "Power", "Мощность") }
    public static var batteryAmperageLabel: String { s("Akım", "Amperage", "Ток") }
    public static var batteryVoltageLabel: String { s("Gerilim", "Voltage", "Напряжение") }
    public static var batteryAdapterLabel: String { s("Güç adaptörü", "Power adapter", "Адаптер питания") }
    public static var batteryAdapterDisconnected: String { s("Takılı değil", "Not connected", "Не подключён") }
    public static var batteryChargingLabel: String { s("Şarj oluyor", "Charging", "Зарядка") }

    public static func batteryTimeRemaining(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let value = hours > 0 ? "\(hours) sa \(rest) dk" : "\(rest) dk"
        let english = hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
        let russian = hours > 0 ? "\(hours) ч \(rest) мин" : "\(rest) мин"
        return s("\(value) kaldı", "\(english) left", "осталось \(russian)")
    }

    public static var memoryLabel: String { s("Bellek", "Memory", "Память") }
    public static var memoryPressureLabel: String { s("Baskı", "Pressure", "Нагрузка") }
    public static var memorySwapLabel: String { s("Takas", "Swap", "Подкачка") }
    public static var memoryActiveLabel: String { s("Etkin", "Active", "Активная") }
    public static var memoryWiredLabel: String { s("Çivilenmiş", "Wired", "Закреплённая") }
    public static var memoryCompressedLabel: String { s("Sıkıştırılmış", "Compressed", "Сжатая") }

    public static var processorUserLabel: String { s("Kullanıcı", "User", "Пользователь") }
    public static var processorSystemLabel: String { s("Sistem", "System", "Система") }
    public static var processorThermalLabel: String { s("Termal", "Thermal", "Тепловой режим") }
    public static var thermalNominal: String { s("Normal", "Normal", "Норма") }
    public static var thermalFair: String { s("Ilımlı", "Fair", "Умеренный") }
    public static var thermalSerious: String { s("Yüksek", "Serious", "Высокий") }
    public static var thermalCritical: String { s("Kritik", "Critical", "Критический") }

    public static var diskLabel: String { s("Disk", "Disk", "Диск") }
    public static var diskFreeLabel: String { s("Boş alan", "Free space", "Свободно") }
    public static var diskUsedLabel: String { s("Kullanılan", "Used", "Использовано") }
    public static var storageLargestItems: String { s("En Çok Yer Kaplayanlar", "Largest Items", "Самые большие объекты") }
    public static var storageScanning: String { s("Dosyalar taranıyor…", "Scanning files…", "Сканирование файлов…") }
    public static var storageScanAgain: String { s("Yeniden tara", "Scan again", "Сканировать снова") }
    public static var storageNoItems: String { s("Büyük dosya bulunamadı", "No large items found", "Крупные объекты не найдены") }
    public static var storageRevealInFinder: String { s("Finder'da göster", "Reveal in Finder", "Показать в Finder") }
    public static var storageMoveToTrash: String { s("Çöp Kutusu'na taşı", "Move to Trash", "Переместить в Корзину") }
    public static var storageCancel: String { s("Vazgeç", "Cancel", "Отмена") }
    public static func storageDeleteTitle(_ name: String) -> String {
        s("\(name) silinsin mi?", "Remove \(name)?", "Удалить \(name)?")
    }
    public static var storageDeleteMessage: String {
        s(
            "Öğe kalıcı olarak silinmez; macOS Çöp Kutusu'na taşınır.",
            "The item is not permanently deleted; it will be moved to the macOS Trash.",
            "Объект не удаляется навсегда; он будет перемещён в Корзину macOS."
        )
    }

    public static var processorLoadLabel: String { s("İşlemci Yükü", "Processor Load", "Загрузка процессора") }

    public static func processorCoreSummary(_ count: Int) -> String {
        s(
            "\(count) çekirdek",
            "\(count) core\(count == 1 ? "" : "s")",
            "\(count) " + ruPlural(count, one: "ядро", few: "ядра", many: "ядер")
        )
    }

    // MARK: Çekirdek başına yük

    public static var processorCoreActivityLabel: String {
        s("Çekirdek Etkinliği", "Core Activity", "Активность ядер")
    }

    /// Grafiğin sağ üstündeki özet: "Çekirdek 4 • %82". Çekirdekler
    /// kullanıcıya 1'den başlayarak numaralanıyor — Etkinlik İzleyicisi de
    /// öyle sayıyor, dizideki 0 tabanlı sıra yalnızca kodun içinde kalıyor.
    public static func processorBusiestCore(_ number: Int, _ fraction: Double) -> String {
        let percent = Int((max(fraction, 0) * 100).rounded())
        return s(
            "Çekirdek \(number) • %\(percent)",
            "Core \(number) • \(percent)%",
            "Ядро \(number) • \(percent)%"
        )
    }

    /// Grafik ekran okuyucuya tek parça olarak okunuyor: otuz ayrı sütunu
    /// tek tek dinletmenin kimseye faydası yok, taşıdığı bilgi "hangi
    /// çekirdek en yüklü".
    public static func processorPerCoreAccessibility(_ number: Int, _ fraction: Double) -> String {
        let percent = Int((max(fraction, 0) * 100).rounded())
        return s(
            "Çekirdek başına CPU kullanımı. En yoğun çekirdek \(number), %\(percent).",
            "Per-core CPU usage. Busiest core \(number) at \(percent) percent.",
            "Загрузка CPU по ядрам. Самое загруженное ядро \(number), \(percent) процентов."
        )
    }
}
