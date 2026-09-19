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

    // MARK: - Raf
    public static var shelfTitle: String { s("Raf", "Shelf", "Полка") }
    public static var shelfEmptyHint: String {
        s(
            "Görsel ve videoları buraya sürükle — sonra buradan tutup geri sürükleyebilirsin",
            "Drag images and videos here — then drag them back out whenever you need them",
            "Перетащите сюда изображения и видео — потом можно перетащить их обратно"
        )
    }
    public static var removeFromShelf: String { s("Raftan Kaldır", "Remove from Shelf", "Убрать с полки") }
    public static var clearShelf: String { s("Rafı Boşalt", "Clear Shelf", "Очистить полку") }
    /// Menüde bir pencere açtığı için üç nokta ile bitiyor.
    public static var shelfAddFiles: String { s("Dosya Ekle…", "Add Files…", "Добавить файлы…") }
    /// Menü başlığı: altındaki anahtar dışarı sürüklemenin ne yaptığını
    /// belirliyor.
    public static var shelfDragOutSection: String {
        s("Dışarı sürüklerken", "When dragging out", "При перетаскивании наружу")
    }
    /// Eski metin ("Sürükleyince raftan çıkar") anahtarın kapalı hâlini
    /// anlatmıyordu; şimdi iki durum da tek cümlede okunuyor.
    public static var shelfRemoveOnDrag: String {
        s("Dosyayı raftan taşı", "Move the file out", "Перемещать файл с полки")
    }
    public static var shelfRemoveOnDragHint: String {
        s(
            "Kapalıyken dosya rafta kalır, kopyası sürüklenir.",
            "When off, the file stays here and a copy is dragged.",
            "Когда выключено, файл остаётся здесь, перетаскивается копия."
        )
    }
    /// Silme geri alınabilir — kullanıcı "boşalt"a basmadan önce bilsin.
    public static var shelfClearHint: String {
        s(
            "Öğeler Çöp'e gider, kalıcı silinmez.",
            "Items go to the Trash, not deleted for good.",
            "Объекты отправляются в Корзину, а не удаляются навсегда."
        )
    }
    // MARK: Raf — araç çubuğu ve eylemler
    public static func shelfItemCount(_ n: Int) -> String {
        switch language {
        case .turkish: "\(n) öğe"
        case .russian: "\(n) " + ruPlural(n, one: "объект", few: "объекта", many: "объектов")
        case .english: n == 1 ? "1 item" : "\(n) items"
        }
    }
    public static var shelfSortLabel: String { s("Sırala", "Sort", "Сортировка") }
    public static var shelfSortRecent: String { s("En yeni", "Recent", "Недавние") }
    public static var shelfSortOldest: String { s("En eski", "Oldest", "Старые") }
    public static var shelfSortName: String { s("Ad", "Name", "Имя") }
    public static var shelfSortType: String { s("Tür", "Type", "Тип") }
    public static var shelfSortSize: String { s("Boyut", "Size", "Размер") }
    public static var shelfViewGrid: String { s("Izgara", "Grid", "Сетка") }
    public static var shelfViewList: String { s("Liste", "List", "Список") }
    public static var shelfPreview: String { s("Önizle", "Preview", "Просмотр") }
    public static var shelfCopy: String { s("Kopyala", "Copy", "Копировать") }
    public static var shelfCopyPath: String { s("Yolu Kopyala", "Copy Path", "Копировать путь") }
    public static var shelfRename: String { s("Yeniden Adlandır", "Rename", "Переименовать") }
    public static var shelfRenamePrompt: String { s("Yeni ad", "New name", "Новое имя") }
    public static var shelfDeleteForever: String { s("Sil", "Delete", "Удалить") }
    public static var shelfDeleteConfirmTitle: String {
        s("Kalıcı olarak silinsin mi?", "Delete permanently?", "Удалить навсегда?")
    }
    /// "Raftan Kaldır" ile "Sil" arasındaki fark burada söyleniyor: ilki
    /// geri alınabilir, ikincisi değil.
    public static var shelfDeleteConfirmBody: String {
        s(
            "Bu dosya Çöp'e gitmeden doğrudan silinir. Geri alınamaz. Raftan kaldırmak istiyorsan onun yerine \"Raftan Kaldır\" kullan — dosya Çöp'e gider.",
            "The file is deleted without going to the Trash. This can't be undone. To just take it off the Shelf, use \"Remove from Shelf\" instead — that moves it to the Trash.",
            "Файл удаляется минуя Корзину. Это нельзя отменить. Чтобы просто убрать его с полки, используйте «Убрать с полки» — файл попадёт в Корзину."
        )
    }
    public static var shelfEmptyTitle: String { s("Dosyaları buraya bırak", "Drop files here", "Перетащите файлы сюда") }
    public static var shelfEmptyBody: String {
        s(
            "Elinin altında tutmak istediklerin burada dursun.",
            "Keep things you want close at hand.",
            "Держите под рукой то, что нужно."
        )
    }
    public static var shelfAddedLabel: String { s("Eklendi", "Added", "Добавлено") }
    public static var shelfBackToShelf: String { s("Raf", "Shelf", "Полка") }

    /// Pano kartının menüsündeki eylem: kartı masaüstünde ayrı bir
    /// pencere olarak açar.
    public static var openAsDesktopWidget: String {
        s("Masaüstü Widget'ı Olarak Aç", "Open as Desktop Widget", "Открыть как виджет рабочего стола")
    }

    public static var sidebarSystemRunning: String {
        s("Sistem çalışıyor", "System running", "Система работает")
    }

    public static var shelfSearchPlaceholder: String {
        s("Rafta ara", "Search Shelf", "Поиск на полке")
    }
    /// Arama hiçbir şey bulamadığında. Aranan metin geri yazılıyor:
    /// kullanıcı yazdığını kutuya bakmadan görebilmeli.
    public static func shelfNoMatches(_ query: String) -> String {
        s(
            "“\(query)” ile eşleşen bir şey yok",
            "Nothing matches “\(query)”",
            "Ничего не найдено по запросу «\(query)»"
        )
    }
    public static var shelfClearSearch: String {
        s("Aramayı temizle", "Clear search", "Очистить поиск")
    }

    public static var shelfDropHint: String { s("Buraya bırak", "Drop here", "Отпустите здесь") }
    /// Sürükleme sırasında beliren küçük rozetin metni — panelin tamamını
    /// kaplayan eski örtünün yerine geçtiği için kısa tutuldu.
    public static var shelfDropNow: String { s("Bırak", "Drop", "Отпустите") }

    // MARK: - Ekran görüntüsü rafı
    public static var autoAddScreenshotsLabel: String {
        s(
            "Ekran görüntülerini otomatik Rafa taşı",
            "Automatically move screenshots to Shelf",
            "Автоматически перемещать снимки экрана на Полку"
        )
    }
    public static var autoAddScreenshotsHint: String {
        s(
            "Sistemin ekran görüntüsü klasörü izlenir; yeni bir görüntü çekildiğinde oradan Rafa taşınır (kopyalanmaz) — Masaüstü böylece dolmaz.",
            "Watches the system's screenshot folder; a new screenshot is moved (not copied) into Shelf as soon as it's taken — so the Desktop doesn't fill up.",
            "Отслеживается системная папка снимков экрана; новый снимок перемещается (а не копируется) на Полку сразу после создания — поэтому Рабочий стол не захламляется."
        )
    }

    // MARK: - Pano geçmişi
    public static var clipboardTitle: String { s("Pano", "Clipboard", "Буфер обмена") }
    public static var clipboardEmptyHint: String {
        s(
            "Kopyaladığın metin ve görseller burada birikir — bir öğeye tıklamak onu tekrar panoya kopyalar",
            "Text and images you copy collect here — tap an item to copy it back to the clipboard",
            "Скопированные текст и изображения собираются здесь — нажмите на элемент, чтобы скопировать его снова"
        )
    }
    public static var clearClipboardHistory: String {
        s("Pano Geçmişini Temizle", "Clear Clipboard History", "Очистить историю буфера обмена")
    }
    public static var copiedConfirmation: String { s("Kopyalandı", "Copied", "Скопировано") }
    public static var removeFromClipboardHistory: String {
        s("Geçmişten Kaldır", "Remove from History", "Удалить из истории")
    }

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
    public static var showFoldersIconLabel: String { shelfTitle }
    public static var showMemoryIconLabel: String { s("RAM Kullanımı", "Memory Usage", "Использование памяти") }
    public static var showClipboardIconLabel: String { clipboardTitle }
    public static var showNetworkIconLabel: String { s("Ağ Trafiği", "Network Data", "Сетевой трафик") }
    public static var showBatteryIconLabel: String { s("Batarya Sağlığı", "Battery Health", "Состояние батареи") }
    public static var showDiskIconLabel: String { s("Disk", "Disk", "Диск") }
    public static var showProcessorIconLabel: String { s("İşlemci Yükü", "Processor Load", "Загрузка процессора") }
    public static var showVolumeIconLabel: String { s("Ses Karıştırıcı", "Volume Mixer", "Микшер громкости") }
    public static var showPinIconLabel: String { s("Pinle", "Pin", "Закрепить") }
    public static var showSettingsIconLabel: String { s("Ayarlar", "Settings", "Настройки") }
    public static var showWindowSwitcherIconLabel: String { s("Pencere Değiştirici", "Window Switcher", "Переключатель окон") }
    public static var selectedIconCornerRadiusLabel: String {
        s("Seçili ikon köşesi", "Selected icon corner", "Скругление выбранного значка")
    }
    public static var selectedIconPaddingLabel: String {
        s("Seçili ikon boşluğu", "Selected icon padding", "Отступ выбранного значка")
    }

    // MARK: - Ses karıştırıcı

    public static var volumeMixerLabel: String { s("Ses Karıştırıcı", "Volume Mixer", "Микшер громкости") }
    public static var volumeOutputLabel: String { s("Çıkış", "Output", "Выход") }
    public static var volumeMicrophoneLabel: String { s("Mikrofon", "Microphone", "Микрофон") }
    public static var volumeMute: String { s("Sessize al", "Mute", "Выключить звук") }
    public static var volumeUnmute: String { s("Sesi aç", "Unmute", "Включить звук") }
    public static var volumePlayingNowLabel: String { s("Şu an çalan", "Playing now", "Сейчас воспроизводится") }
    public static var volumeNothingPlaying: String {
        s("Şu anda ses çalan uygulama yok", "No app is playing audio", "Ни одно приложение не воспроизводит звук")
    }
    public static var volumeNotAdjustable: String {
        s(
            "Bu çıkışın seviyesi cihazın kendisinden ayarlanıyor.",
            "This output's level is controlled on the device itself.",
            "Уровень этого выхода настраивается на самом устройстве."
        )
    }
    public static var volumePerAppNote: String {
        s(
            "Bir uygulamanın sesini kısmak, o uygulamaya özel bir ses yolu kurar — sistemin geri kalanını etkilemez.",
            "Lowering an app's level sets up a dedicated audio route for it — the rest of the system is unaffected.",
            "Понижение громкости приложения создаёт для него отдельный аудиопуть — на остальную систему это не влияет."
        )
    }
    public static var volumeResetToSystem: String {
        s("Sistem seviyesine dön", "Reset to system level", "Вернуть к системному уровню")
    }

    // MARK: - Çalışma alanları (workspaces)

    public static var workspacesSectionTitle: String { s("Çalışma Alanları", "Workspaces", "Рабочие пространства") }
    public static var workspacesSectionSubtitle: String {
        s(
            "Hazır etiket ve örnek görevlerle başla",
            "Start with ready-made tags and sample tasks",
            "Начните с готовых тегов и примеров задач"
        )
    }
    public static var workspacesIntro: String {
        s(
            "Bir şablon seç; ilgili etiketler ve birkaç örnek görev eklensin. Mevcut görevlerine dokunulmaz.",
            "Pick a template to add its tags and a few sample tasks. Your existing tasks are left untouched.",
            "Выберите шаблон — добавятся его теги и несколько примеров задач. Существующие задачи не изменятся."
        )
    }
    public static var workspaceApply: String { s("Uygula", "Apply", "Применить") }
    public static var workspaceApplied: String { s("Eklendi", "Added", "Добавлено") }
    public static var workspaceProjectsLabel: String { s("Projeler", "Projects", "Проекты") }
    public static var workspaceLabelsLabel: String { s("Etiketler", "Labels", "Метки") }
    public static var workspaceSampleTasksLabel: String { s("Örnek Görevler", "Sample Tasks", "Примеры задач") }

    public static func workspacePreview(newTags: Int, newTasks: Int) -> String {
        s(
            "\(newTags) etiket ve \(newTasks) görev eklenecek.",
            "\(newTags) tags and \(newTasks) tasks will be added.",
            "Будет добавлено тегов: \(newTags), задач: \(newTasks)."
        )
    }

    public static var workspaceAlreadyApplied: String {
        s(
            "Bu şablon zaten uygulanmış — tekrar uygulamak yeni bir şey eklemez.",
            "This template is already applied — applying again adds nothing new.",
            "Этот шаблон уже применён — повторное применение ничего не добавит."
        )
    }

    public static func workspaceAppliedConfirmation(newTags: Int, newTasks: Int) -> String {
        s(
            "\(newTags) etiket, \(newTasks) görev eklendi.",
            "Added \(newTags) tags, \(newTasks) tasks.",
            "Добавлено тегов: \(newTags), задач: \(newTasks)."
        )
    }

    public static var workspaceOnboardingTitle: String {
        s("GlassDo'ya Hoş Geldin", "Welcome to GlassDo", "Добро пожаловать в GlassDo")
    }
    public static var workspaceOnboardingSubtitle: String {
        s(
            "Hazır bir çalışma alanıyla başla, ya da boş listeyle kendin kur.",
            "Start with a ready-made workspace, or set things up yourself with an empty list.",
            "Начните с готового рабочего пространства или настройте всё сами с чистого списка."
        )
    }
    public static var workspaceOnboardingContinueEmpty: String {
        s("Boş Başla", "Start Empty", "Начать с нуля")
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
    public static var applyChanges: String { s("Uygula", "Apply", "Применить") }
    public static var versionLabel: String { s("Sürüm", "Version", "Версия") }

    public static func iconCountSummary(_ visible: Int, _ total: Int) -> String {
        s("\(visible) / \(total) görünür", "\(visible) of \(total) shown", "\(visible) из \(total) показано")
    }

    public static var listsSection: String { s("LİSTELER", "LISTS", "СПИСКИ") }
    /// Kenar çubuğunun dibindeki durum satırı: ölçerler örnekleme yapıyor,
    /// yani uygulama arka planda çalışıyor.
    public static var sidebarRunningStatus: String {
        s("Sistem çalışıyor", "System running", "Система работает")
    }
    /// Kenar çubuğu başlığında uygulama adının altındaki tek satır.
    public static var appTagline: String {
        s("İşini bitir", "Get things done", "Доводите дела до конца")
    }
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
    public static var systemSection: String { s("SİSTEM", "SYSTEM", "СИСТЕМА") }
    public static var systemMonitorTitle: String { s("RAM Kullanımı", "Memory Usage", "Использование памяти") }
    public static var systemMonitorEmpty: String { s("Çalışan uygulama yok", "No running apps", "Нет запущенных приложений") }
    public static var cancel: String { s("Vazgeç", "Cancel", "Отмена") }
    public static var save: String { s("Kaydet", "Save", "Сохранить") }
    public static var selectAll: String { s("Tümünü Seç", "Select All", "Выбрать все") }
    public static var deselectAll: String { s("Seçimi Kaldır", "Deselect All", "Снять выделение") }
    public static func deleteSelectedTasks(_ count: Int) -> String {
        switch language {
        case .turkish: "\(count) görevi sil"
        case .russian: "Удалить \(count) " + ruPlural(count, one: "задачу", few: "задачи", many: "задач")
        case .english: count == 1 ? "Delete task" : "Delete \(count) tasks"
        }
    }
    /// Silme geri alınamıyor; kaç öğenin gideceği onay metninde yazıyor.
    public static func deleteSelectedTasksConfirm(_ count: Int) -> String {
        switch language {
        case .turkish: "\(count) görev kalıcı olarak silinecek. Bu işlem geri alınamaz."
        case .russian: "\(count) " + ruPlural(count, one: "задача будет удалена", few: "задачи будут удалены", many: "задач будут удалены") + " навсегда. Отменить нельзя."
        case .english: count == 1
            ? "This task will be deleted permanently. This can't be undone."
            : "\(count) tasks will be deleted permanently. This can't be undone."
        }
    }

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
    /// Dock'ta görünmeyen süreçler: yardımcı süreçler, servisler, çalışma
    /// zamanları. "macOS ve Sistem" dilimini oluşturan yığın.
    public static var systemProcessesLabel: String {
        s("Sistem Süreçleri", "System Processes", "Системные процессы")
    }

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

    /// Arka plan ağ ajanı (Ayarlar > Ağ) etkinken gösterilen karşılığı —
    /// bu durumda geçmiş, uygulama tamamen kapalıyken de birikmeye devam
    /// ediyor; eski metin artık yanlış bilgi verirdi.
    public static var networkHistoryHintAgentEnabled: String {
        s(
            "Geçmiş, GlassDo kapalıyken de arka planda birikmeye devam ediyor",
            "History keeps accumulating in the background even while GlassDo is quit",
            "История продолжает накапливаться в фоне, даже когда GlassDo закрыт"
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
    // MARK: Bağlantı kimliği

    // MARK: Not yazı boyutu

    public static var noteTextSize: String { s("Yazı boyutu", "Text size", "Размер текста") }
    public static var noteTextSmaller: String { s("Küçült", "Smaller", "Уменьшить") }
    public static var noteTextLarger: String { s("Büyüt", "Larger", "Увеличить") }
    public static var noteTextSizeReset: String { s("Sıfırla", "Reset", "Сбросить") }

    // MARK: Not editöründe çoklu seçim

    public static func noteSelectedCount(_ count: Int) -> String {
        switch language {
        case .turkish: "\(count) satır seçili"
        case .russian: "Выбрано строк: \(count)"
        case .english: count == 1 ? "1 line selected" : "\(count) lines selected"
        }
    }
    /// Seçilen satırlar farklı türdeyse blok menüsünün etiketi.
    public static var noteMixedKinds: String { s("Karışık", "Multiple", "Разные") }
    public static var noteSelectAllHint: String {
        s(
            "⌘A hepsini seçer · ⇧ ya da ⌘ ile tıklayarak satır seç",
            "⌘A selects all · ⇧- or ⌘-click a line to select",
            "⌘A выделяет всё · ⇧- или ⌘-клик по строке"
        )
    }

    public static var publicIPLabel: String { s("Genel IP", "Public IP", "Внешний IP") }
    public static var localIPLabel: String { s("Yerel IP", "Local IP", "Локальный IP") }
    public static var vpnLabel: String { s("VPN", "VPN", "VPN") }
    public static var vpnActive: String { s("Bağlı", "Connected", "Подключён") }
    public static var vpnInactive: String { s("Bağlı değil", "Not connected", "Не подключён") }
    public static var publicIPUnavailable: String {
        s("Okunamadı", "Unavailable", "Недоступно")
    }
    /// Genel adresin nereden sorulduğu açıkça yazıyor: bu tek dış istek
    /// kullanıcıdan gizlenmemeli.
    public static var publicIPSourceNote: String {
        s(
            "Genel adres Cloudflare'a sorularak öğreniliyor",
            "The public address is looked up via Cloudflare",
            "Внешний адрес определяется через Cloudflare"
        )
    }
    public static var refreshLabel: String { s("Yenile", "Refresh", "Обновить") }

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

    public static var speedTestTitle: String {
        s("Bağlantını Test Et", "Test Your Connection", "Проверьте соединение")
    }
    public static var speedTestHowItWorksTitle: String {
        s("Nasıl çalışıyor", "How it works", "Как это работает")
    }
    public static var speedTestHowItWorksBody: String {
        s(
            "GlassDo küçük bir test dosyası indirip yükleyerek bağlantının gerçek hızını ölçer.",
            "GlassDo downloads and uploads a small test file to measure your real connection speed.",
            "GlassDo скачивает и отправляет небольшой тестовый файл, чтобы измерить реальную скорость соединения."
        )
    }
    /// Kartın üstündeki "açılıştan beri" etiketi: büyük sayı anlık hız
    /// değil, biriken toplam.
    public static var networkSinceBootLabel: String {
        s("Açılıştan beri", "Since boot", "С момента запуска")
    }

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
    public static var batteryTimeLabel: String { s("Kalan süre", "Time left", "Осталось") }

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
    public static var storageLargestItems: String {
        s("En Büyük Uygulamalar", "Largest Apps", "Самые большие приложения")
    }
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

    // MARK: İşlemci sayfası panosu
    public static var processorPerformanceEyebrow: String {
        s("PERFORMANS", "PERFORMANCE", "ПРОИЗВОДИТЕЛЬНОСТЬ")
    }
    public static var processorHeadlineCalm: String {
        s("Mac'in rahat çalışıyor", "Your Mac is running smoothly", "Ваш Mac работает спокойно")
    }
    public static var processorHeadlineBusy: String {
        s("İşlemci yoğun çalışıyor", "The processor is working hard", "Процессор нагружен")
    }
    public static var processorHeadlineHeavy: String {
        s("İşlemci sınırda", "The processor is maxed out", "Процессор на пределе")
    }
    public static var processorHeadlineThermal: String {
        s("Termal baskı yüksek", "Thermal pressure is high", "Высокая тепловая нагрузка")
    }
    public static var processorBodyCalm: String {
        s(
            "Kullanım normal aralıkta, her şey yolunda görünüyor.",
            "Usage is within the normal range — everything looks fine.",
            "Загрузка в норме — всё в порядке."
        )
    }
    public static var processorBodyBusy: String {
        s(
            "Kullanım yüksek ama sistem baskı altında değil.",
            "Usage is high, but the system isn't under pressure.",
            "Загрузка высокая, но система не перегружена."
        )
    }
    public static var processorBodyHeavy: String {
        s(
            "Uzun sürerse uygulamalar yavaşlayabilir.",
            "If this keeps up, apps may start to feel slow.",
            "Если так продолжится, приложения могут замедлиться."
        )
    }
    public static var processorBodyThermal: String {
        s(
            "Sistem hızını düşürerek sıcaklığı dengeliyor.",
            "The system is slowing itself down to manage heat.",
            "Система снижает частоту, чтобы справиться с нагревом."
        )
    }
    public static var processorTotalUsageLabel: String {
        s("Toplam kullanım", "Total Usage", "Общая загрузка")
    }
    public static var processorCoreUsageTitle: String { s("Çekirdek Yükü", "Core Usage", "Загрузка ядер") }
    public static var processorCoreUsageSubtitle: String {
        s("Her çekirdeğin anlık yükü", "Each core's current load", "Текущая нагрузка каждого ядра")
    }
    public static var processorDistributionTitle: String {
        s("Yük Dağılımı", "Load Distribution", "Распределение нагрузки")
    }
    public static var processorDistributionSubtitle: String {
        s("Kullanıcı / sistem / boşta", "User vs System vs Idle", "Пользователь / система / простой")
    }
    public static var processorIdleLabel: String { s("Boşta", "Idle", "Простой") }
    public static var processorCoresLabel: String { s("Çekirdek", "Cores", "Ядра") }
    public static var processorUptimeLabel: String { s("Açık kalma", "Uptime", "Время работы") }
    /// Süre kısaltmaları: "2g 14sa" gibi tek satırlık özetler için.
    public static var dayShort: String { s("g", "d", "д") }
    public static var hourShort: String { s("sa", "h", "ч") }
    public static var minuteShort: String { s("dk", "m", "м") }
    public static var processorTemperatureLabel: String { s("Sıcaklık", "Temperature", "Температура") }

    /// İşlemci ve batarya tek sayfada birleşti; kenar çubuğundaki satırın
    /// adı da bunu söylüyor.
    /// Kenar çubuğu satırı tek satırda kalmalı: "İşlemci ve Batarya"
    /// sığmayıp iki satıra bölünüyordu, komşu satırların ritmi bozuluyordu.
    public static var processorBatteryTitle: String {
        s("CPU ve Pil", "CPU & Battery", "ЦП и батарея")
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

    // MARK: - Görev ayrıntısı

    public static var openTaskDetail: String { s("Ayrıntıları Aç", "Open Details", "Открыть подробности") }
    public static var taskDetailTitle: String { s("Görev Ayrıntısı", "Task Details", "Подробности задачи") }
    public static var notesSectionTitle: String { s("Notlar", "Notes", "Заметки") }
    public static var notesPlaceholder: String { s("Notlar…", "Notes…", "Заметки…") }
    public static var dueDateLabel: String { s("Bitiş tarihi", "Due date", "Срок выполнения") }
    public static var noDueDate: String { s("Tarih yok", "No date", "Без даты") }
    public static var priorityLabel: String { s("Öncelik", "Priority", "Приоритет") }
    public static var recurrenceLabel: String { s("Tekrar", "Repeat", "Повтор") }
    public static var recurrenceNone: String { s("Tekrarlanmıyor", "Does not repeat", "Не повторяется") }
    public static var recurrenceNeedsDueDateHint: String {
        s(
            "Tekrar ayarlamak için önce bir bitiş tarihi seç",
            "Set a due date before choosing a repeat",
            "Сначала укажите срок, чтобы задать повтор"
        )
    }
    public static var subtasksTitle: String { s("Alt Görevler", "Subtasks", "Подзадачи") }
    public static var addSubtaskPlaceholder: String { s("Alt görev ekle…", "Add subtask…", "Добавить подзадачу…") }
    public static var completeParentTask: String { s("Ana Görevi Tamamla", "Complete Parent Task", "Завершить основную задачу") }
    public static var close: String { s("Kapat", "Close", "Закрыть") }

    // MARK: - Bağlam (attachments)

    public static var contextSectionTitle: String { s("Bağlam", "Context", "Контекст") }
    public static var addAttachmentHelp: String { s("Bağlam ekle", "Add context", "Добавить контекст") }
    public static var addFileAttachment: String { s("Dosya Ekle…", "Add File…", "Добавить файл…") }
    public static var addFolderAttachment: String { s("Klasör Ekle…", "Add Folder…", "Добавить папку…") }
    public static var addFromShelfAttachment: String { s("Raftan Ekle…", "Add from Shelf…", "Добавить с полки…") }
    public static var addFromClipboardAttachment: String { s("Panodan Ekle…", "Add from Clipboard…", "Добавить из буфера…") }
    public static var noAttachments: String { s("Henüz bağlam eklenmedi", "No context added yet", "Контекст пока не добавлен") }
    public static var attachmentStaleHint: String {
        s("Dosya taşınmış olabilir", "The file may have moved", "Файл мог быть перемещён")
    }
    public static var attachmentMissingHint: String {
        s("Dosya bulunamadı", "File not found", "Файл не найден")
    }
    public static var reselectFile: String { s("Dosyayı Yeniden Seç", "Reselect File", "Выбрать файл заново") }
    public static var attachmentLimitReached: String {
        s(
            "Bir göreve en fazla 30 bağlam öğesi eklenebilir",
            "A task can have at most 30 context items",
            "К задаче можно добавить не более 30 элементов контекста"
        )
    }
    public static var attachmentDuplicate: String {
        s("Bu dosya zaten ekli", "This file is already attached", "Этот файл уже прикреплён")
    }
    public static var attachmentBookmarkFailed: String {
        s("Dosyaya erişim sağlanamadı", "Couldn't get access to the file", "Не удалось получить доступ к файлу")
    }
    public static var removeAttachment: String { s("Kaldır", "Remove", "Удалить") }
    public static var attachmentsCountLabel: String {
        s("Bağlam", "Context", "Контекст")
    }

    // MARK: - Odak Oturumu (Focus Session)

    public static var focusSessionTitle: String { s("Odak Oturumu", "Focus Session", "Сеанс концентрации") }
    public static var focusStart: String { s("Başlat", "Start", "Начать") }
    public static var focusStop: String { s("Durdur", "Stop", "Остановить") }
    public static var focusComplete: String { s("Tamamla", "Complete", "Завершить") }
    public static var focusCompleteTaskToo: String {
        s("Görevi de tamamla", "Also complete the task", "Также завершить задачу")
    }
    public static var focusDurationLabel: String { s("Süre", "Duration", "Длительность") }
    public static func focusMinutesShort(_ minutes: Int) -> String {
        s("\(minutes) dk", "\(minutes)m", "\(minutes) мин")
    }
    public static var focusSessionAlreadyActive: String {
        s(
            "Zaten çalışan bir odak oturumu var",
            "A focus session is already running",
            "Сеанс концентрации уже запущен"
        )
    }
    public static var focusSwitchSessionTitle: String {
        s("Odak oturumu değiştirilsin mi?", "Switch focus session?", "Сменить сеанс концентрации?")
    }
    public static var focusSwitchSessionMessage: String {
        s(
            "Çalışan oturum durdurulup yenisi başlatılacak.",
            "The running session will be stopped and a new one started.",
            "Текущий сеанс будет остановлен, начнётся новый."
        )
    }
    public static var focusSwitchSessionConfirm: String { s("Değiştir", "Switch", "Сменить") }
    public static var focusHistoryTitle: String { s("Odak Geçmişi", "Focus History", "История концентрации") }
    public static var focusPerTaskLabel: String { s("Görev Başına", "Per Task", "По задачам") }
    public static var focusNoHistory: String {
        s("Henüz odak oturumu yok", "No focus sessions yet", "Пока нет сеансов концентрации")
    }
    public static var focusStartMenuTitle: String { s("Odak Oturumu Başlat", "Start Focus Session", "Начать сеанс концентрации") }
    public static var focusNotificationTitle: String {
        s("Odak oturumu bitti", "Focus session ended", "Сеанс концентрации завершён")
    }
    public static func focusNotificationBody(_ taskTitle: String) -> String {
        s("“\(taskTitle)” için ayrılan süre doldu", "Time's up for “\(taskTitle)”", "Время для «\(taskTitle)» истекло")
    }

    // MARK: - Bağlama duyarlı Edge Rail

    public static var contextRuleStartAction: String {
        s("Bu Uygulama Açıkken Öne Çıkar…", "Highlight When This App Is Active…", "Выделять, когда это приложение активно…")
    }
    public static var contextRuleCreated: String {
        s("Bağlam kuralı eklendi", "Context rule added", "Правило контекста добавлено")
    }
    public static var contextRulesTitle: String { s("Kurallar", "Rules", "Правила") }
    public static var contextRulesEmpty: String {
        s(
            "Henüz kural yok — bir görevin sağ tık menüsünden ekleyebilirsin",
            "No rules yet — add one from a task's right-click menu",
            "Пока нет правил — добавьте через контекстное меню задачи"
        )
    }
    public static var contextAwarePrivacyNote: String {
        s(
            "Yalnızca etkin uygulamanın kimliği ve adı bellekte tutulur; pencere başlığı, adres veya ekran içeriği hiçbir zaman okunmaz.",
            "Only the active app's identifier and name are kept in memory; window titles, URLs, or screen content are never read.",
            "В памяти хранятся только идентификатор и имя активного приложения; заголовки окон, адреса и содержимое экрана никогда не считываются."
        )
    }
    public static var contextSuggestedNowLabel: String {
        s("Şu an önerilen", "Suggested now", "Предложено сейчас")
    }
    public static func contextRuleTargetTag(_ name: String) -> String {
        s("Etiket: \(name)", "Tag: \(name)", "Метка: \(name)")
    }

    public static var weekdaySundayShort: String { s("Paz", "Sun", "Вс") }
    public static var weekdayMondayShort: String { s("Pzt", "Mon", "Пн") }
    public static var weekdayTuesdayShort: String { s("Sal", "Tue", "Вт") }
    public static var weekdayWednesdayShort: String { s("Çar", "Wed", "Ср") }
    public static var weekdayThursdayShort: String { s("Per", "Thu", "Чт") }
    public static var weekdayFridayShort: String { s("Cum", "Fri", "Пт") }
    public static var weekdaySaturdayShort: String { s("Cmt", "Sat", "Сб") }

    /// Çöpe atılamayan öğe. Sebebi söylüyor ve çıkış yolunu gösteriyor —
    /// sistemin ham "izniniz yok" metni kullanıcıyı ortada bırakıyordu.
    public static func storageNeedsAdminRights(_ name: String) -> String {
        s(
            "“\(name)” silinemedi. Uygulamalar klasöründeki uygulamalar macOS tarafından korunuyor; silmek yönetici izni ya da Gizlilik ayarlarındaki “Uygulama Yönetimi” iznini gerektiriyor. Finder'da silebilirsin.",
            "Couldn’t delete “\(name)”. Apps in the Applications folder are protected by macOS; removing one needs administrator rights or the “App Management” privacy permission. You can delete it in Finder.",
            "Не удалось удалить «\(name)». Приложения в папке Applications защищены macOS; для удаления нужны права администратора или разрешение «Управление приложениями». Вы можете удалить это в Finder."
        )
    }

    public static var storageOpenInFinder: String {
        s("Finder'da Aç", "Open in Finder", "Открыть в Finder")
    }

    // MARK: - Pano

    /// İki satırdan uzun girdilerde kalanın kaç satır olduğu.
    public static func clipboardMoreLines(_ count: Int) -> String {
        s(
            "+\(count) satır",
            "+\(count) line\(count == 1 ? "" : "s")",
            "+\(count) " + ruPlural(count, one: "строка", few: "строки", many: "строк")
        )
    }

    public static var clipboardKindCommand: String { s("Komut", "Command", "Команда") }
    public static var clipboardKindLink: String { s("Bağlantı", "Link", "Ссылка") }
    public static var clipboardKindCode: String { s("Kod", "Code", "Код") }
    public static var clipboardKindText: String { s("Metin", "Text", "Текст") }
    public static var clipboardKindImage: String { s("Görsel", "Image", "Изображение") }

    // MARK: - Satın alma

    /// "Satın Alımları Geri Yükle" hiçbir şey bulamadığında. Sessizce
    /// hiçbir şey olmaması, düğmenin bozuk olduğu izlenimi verirdi.
    public static var purchaseNothingToRestore: String {
        s(
            "Geri yüklenecek bir satın alma bulunamadı.",
            "No purchases to restore.",
            "Нет покупок для восстановления."
        )
    }
}
