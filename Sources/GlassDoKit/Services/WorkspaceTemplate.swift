import Foundation

/// Bir şablon etiketinin adı ve rengi. `Tag`'in kendisi değil — şablon
/// veri modeline hiç yazılmıyor, yalnızca `WorkspaceTemplateApplier`
/// uygularken gerçek `Tag` kayıtlarına dönüşüyor.
public struct WorkspaceTagSpec: Sendable, Equatable {
    public let name: String
    public let colorHex: String
}

/// Bir şablon örnek görevi. `tagNames`, aynı şablonun `content.allTags`
/// listesindeki adlarla birebir eşleşmeli — uygulama sırasında adla
/// arama yapılıyor.
public struct WorkspaceTaskSpec: Sendable, Equatable {
    public let title: String
    public let tagNames: [String]
}

/// Bir şablonun içeriği: proje niteliğindeki etiketler, genel etiketler
/// ve örnek görevler.
///
/// `projectTags` ile `labelTags` ayrımı yalnızca önizleme/anlatım için —
/// veri modelinde ikisi de aynı `Tag` sınıfına dönüşüyor. Uygulamada ayrı
/// bir "Project" kavramı kasıtlı olarak yok (bkz. `AppContextRule`'ın
/// belgesi); bu ayrımı burada da icat etmek yalnızca kafa karıştırırdı.
public struct WorkspaceTemplateContent: Sendable {
    public let projectTags: [WorkspaceTagSpec]
    public let labelTags: [WorkspaceTagSpec]
    public let sampleTasks: [WorkspaceTaskSpec]

    /// Uygulanacak tüm etiketler, proje+genel birleşik ve tekrarsız.
    public var allTags: [WorkspaceTagSpec] {
        var seen = Set<String>()
        return (projectTags + labelTags).filter { seen.insert($0.name).inserted }
    }
}

/// Hazır çalışma alanı şablonları. SwiftData modeli **değil** — sabit,
/// yalnızca kod içinde tanımlı bir liste. Kullanıcı bir şablonu
/// uyguladığında yalnızca seçtiği varlıklar `WorkspaceTemplateApplier`
/// aracılığıyla gerçek `Tag`/`Task` kayıtlarına kopyalanır.
public enum WorkspaceTemplateKind: String, CaseIterable, Identifiable, Sendable {
    case developer, freelancer, student, creator

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .developer: L10n.s("Geliştirici", "Developer", "Разработчик")
        case .freelancer: L10n.s("Serbest Çalışan", "Freelancer", "Фрилансер")
        case .student: L10n.s("Öğrenci", "Student", "Студент")
        case .creator: L10n.s("İçerik Üreticisi", "Creator", "Автор контента")
        }
    }

    public var subtitle: String {
        switch self {
        case .developer:
            L10n.s(
                "Ürün ve yan proje takibi", "Track your product and side project",
                "Отслеживание продукта и пет-проекта")
        case .freelancer:
            L10n.s(
                "Müşteri projeleri ve faturalar", "Client projects and invoices",
                "Клиентские проекты и счета")
        case .student:
            L10n.s(
                "Dersler, ödevler, sınavlar", "Courses, assignments, exams",
                "Курсы, задания, экзамены")
        case .creator:
            L10n.s(
                "İçerik takvimi ve yayınlar", "Content calendar and releases",
                "Контент-план и публикации")
        }
    }

    public var symbolName: String {
        switch self {
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .freelancer: "briefcase"
        case .student: "graduationcap"
        case .creator: "video"
        }
    }

    public var tintHex: String {
        switch self {
        case .developer: "#0A84FF"
        case .freelancer: "#BF5AF2"
        case .student: "#30D158"
        case .creator: "#FF9F0A"
        }
    }

    /// Şablonun etiketleri ve örnek görevleri. Tek bir `switch` içinde
    /// tanımlanıyor ki örnek görevlerin `tagNames`'i, etiket listesindeki
    /// adlarla aynı Swift `let` değerinden gelsin — iki ayrı yerde aynı
    /// dizeyi elle tekrarlamak zamanla ayrışabilirdi.
    public var content: WorkspaceTemplateContent {
        switch self {
        case .developer:
            let mainProduct = WorkspaceTagSpec(
                name: L10n.s("Ana Ürün", "Main Product", "Основной продукт"), colorHex: "#0A84FF")
            let sideProject = WorkspaceTagSpec(
                name: L10n.s("Yan Proje", "Side Project", "Пет-проект"), colorHex: "#FF9F0A")
            let bug = WorkspaceTagSpec(name: L10n.s("Hata", "Bug", "Баг"), colorHex: "#FF453A")
            let feature = WorkspaceTagSpec(
                name: L10n.s("Özellik", "Feature", "Функция"), colorHex: "#30D158")
            let review = WorkspaceTagSpec(
                name: L10n.s("İnceleme", "Review", "Обзор"), colorHex: "#BF5AF2")
            let learning = WorkspaceTagSpec(
                name: L10n.s("Öğrenme", "Learning", "Обучение"), colorHex: "#64D2FF")
            return WorkspaceTemplateContent(
                projectTags: [mainProduct, sideProject],
                labelTags: [bug, feature, review, learning],
                sampleTasks: [
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — README dosyasını güncelle", "Example — Update the README",
                            "Пример — обновить README"),
                        tagNames: [mainProduct.name, feature.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Açık bir hata kaydını incele", "Example — Triage an open bug",
                            "Пример — разобрать открытый баг"),
                        tagNames: [mainProduct.name, bug.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Yan projene 30 dakika ayır",
                            "Example — Spend 30 minutes on your side project",
                            "Пример — уделить 30 минут пет-проекту"),
                        tagNames: [sideProject.name]
                    ),
                ]
            )

        case .freelancer:
            let website = WorkspaceTagSpec(
                name: L10n.s("Web Sitesi Projesi", "Website Project", "Проект сайта"),
                colorHex: "#0A84FF")
            let brand = WorkspaceTagSpec(
                name: L10n.s("Marka Kimliği Projesi", "Brand Identity Project", "Проект бренда"),
                colorHex: "#BF5AF2")
            let consulting = WorkspaceTagSpec(
                name: L10n.s("Danışmanlık", "Consulting", "Консультации"), colorHex: "#30D158")
            let invoice = WorkspaceTagSpec(
                name: L10n.s("Fatura", "Invoice", "Счёт"), colorHex: "#FF9F0A")
            let proposal = WorkspaceTagSpec(
                name: L10n.s("Teklif", "Proposal", "Предложение"), colorHex: "#64D2FF")
            let call = WorkspaceTagSpec(
                name: L10n.s("Müşteri Görüşmesi", "Client Call", "Звонок с клиентом"),
                colorHex: "#FF453A")
            let revision = WorkspaceTagSpec(
                name: L10n.s("Revizyon", "Revision", "Правки"), colorHex: "#5E5CE6")
            return WorkspaceTemplateContent(
                projectTags: [website, brand, consulting],
                labelTags: [invoice, proposal, call, revision],
                sampleTasks: [
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Web Sitesi Projesi için teklif gönder",
                            "Example — Send a proposal for the Website Project",
                            "Пример — отправить предложение по проекту сайта"),
                        tagNames: [website.name, proposal.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Bu ayın faturalarını hazırla",
                            "Example — Prepare this month's invoices",
                            "Пример — подготовить счета за этот месяц"),
                        tagNames: [invoice.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Müşteriyle görüşme planla",
                            "Example — Schedule a call with a client",
                            "Пример — запланировать звонок с клиентом"),
                        tagNames: [call.name]
                    ),
                ]
            )

        case .student:
            let term = WorkspaceTagSpec(
                name: L10n.s("Dönem Projesi", "Term Project", "Курсовой проект"),
                colorHex: "#30D158")
            let thesis = WorkspaceTagSpec(
                name: L10n.s("Bitirme Tezi", "Thesis", "Диплом"), colorHex: "#0A84FF")
            let assignment = WorkspaceTagSpec(
                name: L10n.s("Ödev", "Assignment", "Домашнее задание"), colorHex: "#FF9F0A")
            let exam = WorkspaceTagSpec(
                name: L10n.s("Sınav", "Exam", "Экзамен"), colorHex: "#FF453A")
            let reading = WorkspaceTagSpec(
                name: L10n.s("Okuma", "Reading", "Чтение"), colorHex: "#64D2FF")
            let lecture = WorkspaceTagSpec(
                name: L10n.s("Ders Notları", "Lecture Notes", "Конспект"), colorHex: "#BF5AF2")
            return WorkspaceTemplateContent(
                projectTags: [term, thesis],
                labelTags: [assignment, exam, reading, lecture],
                sampleTasks: [
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Yarının sınavına çalış", "Example — Study for tomorrow's exam",
                            "Пример — подготовиться к завтрашнему экзамену"),
                        tagNames: [exam.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Dönem projesi taslağını yaz",
                            "Example — Draft the term project outline",
                            "Пример — написать план курсового проекта"),
                        tagNames: [term.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Bu haftanın okuma ödevini bitir",
                            "Example — Finish this week's reading",
                            "Пример — закончить чтение на этой неделе"),
                        tagNames: [reading.name]
                    ),
                ]
            )

        case .creator:
            let channel = WorkspaceTagSpec(
                name: L10n.s("YouTube Kanalı", "YouTube Channel", "YouTube-канал"),
                colorHex: "#FF453A")
            let podcast = WorkspaceTagSpec(
                name: L10n.s("Podcast", "Podcast", "Подкаст"), colorHex: "#BF5AF2")
            let launch = WorkspaceTagSpec(
                name: L10n.s("Ürün Lansmanı", "Product Launch", "Запуск продукта"),
                colorHex: "#0A84FF")
            let script = WorkspaceTagSpec(
                name: L10n.s("Senaryo", "Script", "Сценарий"), colorHex: "#FF9F0A")
            let edit = WorkspaceTagSpec(
                name: L10n.s("Kurgu", "Edit", "Монтаж"), colorHex: "#64D2FF")
            let schedule = WorkspaceTagSpec(
                name: L10n.s("Yayın Takvimi", "Publish Schedule", "График публикаций"),
                colorHex: "#30D158")
            let sponsorship = WorkspaceTagSpec(
                name: L10n.s("Sponsorluk", "Sponsorship", "Спонсорство"), colorHex: "#5E5CE6")
            return WorkspaceTemplateContent(
                projectTags: [channel, podcast, launch],
                labelTags: [script, edit, schedule, sponsorship],
                sampleTasks: [
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Bir sonraki video için senaryo yaz",
                            "Example — Write the script for the next video",
                            "Пример — написать сценарий для следующего видео"),
                        tagNames: [channel.name, script.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Bu haftanın videosunu kurgula",
                            "Example — Edit this week's video",
                            "Пример — смонтировать видео этой недели"),
                        tagNames: [channel.name, edit.name]
                    ),
                    WorkspaceTaskSpec(
                        title: L10n.s(
                            "Örnek — Sponsorluk teklifini yanıtla",
                            "Example — Reply to the sponsorship offer",
                            "Пример — ответить на предложение о спонсорстве"),
                        tagNames: [sponsorship.name]
                    ),
                ]
            )
        }
    }
}
