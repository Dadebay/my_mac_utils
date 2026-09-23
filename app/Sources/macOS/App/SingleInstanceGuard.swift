import AppKit

/// Uygulamanın ikinci bir kopyasının açılmasını engeller.
///
/// macOS, aynı paket kimliğine sahip iki uygulamayı **farklı klasörlerdeyse**
/// seve seve birlikte çalıştırıyor: `/Applications/GlassDo.app` ile Xcode'un
/// derleme klasöründeki kopya aynı anda ayakta kalabiliyor. Sonuç, kullanıcının
/// ekranında iki kenar rayı, menü çubuğunda iki ölçer takımı ve her uyarıdan
/// iki bildirim.
///
/// Bildirime tıklamak bunu görünür kılan şeydi: tıklama LaunchServices'e
/// "bu kimliğe kayıtlı uygulamayı aç" diyor, o da kurulu kopyayı açıyor —
/// zaten çalışan kopyayı öne getirmek yerine ikincisini başlatıyordu.
///
/// Görünürdeki karmaşadan daha ciddi olan şu: iki süreç aynı SwiftData
/// deposuna yazıyor. Aynı dosyaya iki yazar, veri kaybı için yeterli sebep.
enum SingleInstanceGuard {

    /// Başka bir kopya çalışıyorsa onu öne getirir ve bu süreci sonlandırır.
    ///
    /// Uygulamanın `init`'inde, veri deposu açılmadan **önce** çağrılıyor:
    /// ikinci kopya depoya hiç dokunmadan, hiçbir pencere çizmeden çekiliyor.
    static func enforce() {
        guard let id = Bundle.main.bundleIdentifier else { return }

        let me = ProcessInfo.processInfo.processIdentifier
        let myLaunch = NSRunningApplication.current.launchDate ?? Date()

        /* Yalnızca *bizden önce* başlamış bir kopya bizi sonlandırıyor.
           İki kopya aynı anda açılırsa (ikisi de diğerini görürse) bu kural
           olmadan ikisi birden kapanırdı; tarih karşılaştırması her zaman
           bir kazanan bırakıyor. */
        let earlier = NSRunningApplication
            .runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
            .filter { ($0.launchDate ?? .distantPast) < myLaunch }

        guard let existing = earlier.first else { return }

        /*
         * Önce öne getir, sonra bekle — bu sıra önemli.
         *
         * İki farklı durum aynı tabloyu veriyor ve ayırt etmenin doğrudan
         * bir yolu yok: (1) çalışan bir kopya var, kullanıcı ikincisini
         * açtı; (2) bir kopya kapanmakta, üzerine hemen yenisi açılıyor —
         * kurulum betikleri tam olarak bunu yapıyor
         * (`osascript ... to quit` ardından `open`).
         *
         * Çözüm, ikisinde de doğru olan şeyi hemen yapmak: var olan kopyayı
         * öne getirmek. Kapanmakta olan bir kopyada bu zaten etkisiz. Sonra
         * bekliyoruz: kopya ölürse sıra bize geçiyor ve açılış normal devam
         * ediyor; yaşamaya devam ederse gerçekten çalışan bir kopya var
         * demektir ve biz çekiliyoruz.
         *
         * Böylece kullanıcı ikinci kez açtığında uygulama ANINDA öne
         * geliyor (bekleme kullanıcıya görünmüyor), kurulum betiği de
         * çalışıyor.
         *
         * Süre ölçüyle seçildi: bu uygulamanın kapanması ~2 saniye sürüyor
         * (Firebase ve veri deposu kapanışı dahil). 3,5 saniye buna rahat
         * bir pay bırakıyor.
         */
        existing.activate()

        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline {
            if existing.isTerminated { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !existing.isTerminated else { return }

        exit(0)
    }
}
