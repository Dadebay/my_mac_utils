import AudioToolbox
import CoreAudio
import Darwin
import Foundation

/// Uygulama başına **gerçek** ses seviyesi kontrolü.
///
/// macOS'un normal ses sistemi bunu desteklemiyor — ama macOS 14.2+'ın
/// Core Audio **process tap** API'si (genel, dokümante edilmiş; özel/gizli
/// bir API değil) bunu mümkün kılıyor:
///
/// 1. `CATapDescription` + `AudioHardwareCreateProcessTap` ile bir sürecin
///    sesi "yakalanır" ve `muteBehavior = .muted` ile **doğrudan çıkışa
///    gitmesi engellenir** — uygulama artık sisteme kendi başına ses
///    veremiyor, sesi yalnızca bizim tap'imizden okunabiliyor.
/// 2. Tek bir "aggregate device" hem bu tap'i (giriş tarafı) hem gerçek
///    çıkış cihazını (`kAudioAggregateDeviceMainSubDeviceKey`) taşıyor —
///    bu sayede aynı IOProc geri çağrısında hem yakalanan örnekleri
///    okuyup hem gerçek hoparlöre yazabiliyoruz. Ayrı bir oynatma motoru
///    (AVAudioEngine vb.) gerekmiyor: örnekler kazançla çarpılıp doğrudan
///    çıkış tamponuna kopyalanıyor.
///
/// Varsayılan (%100) seviyedeki bir uygulama için hiçbir tap kurulmuyor —
/// kullanıcı kaydırıcıyı gerçekten oynatana kadar sıfır ek yük ve sıfır
/// ses gecikmesi riski.
@MainActor
@Observable
final class PerAppVolumeController {
    static let shared = PerAppVolumeController()

    /// pid → 0…1 kazanç. Oturumu olmayan (%100'de kalan) uygulamalar
    /// burada hiç görünmez.
    private(set) var volumes: [pid_t: Double] = [:]
    private var sessions: [pid_t: TapSession] = [:]

    private init() {}

    func volume(for pid: pid_t) -> Double {
        volumes[pid] ?? 1.0
    }

    func isControlled(_ pid: pid_t) -> Bool {
        sessions[pid] != nil
    }

    /// Kaydırıcı her hareket ettiğinde çağrılır. Oturum zaten açıksa yalnız
    /// kazanç değişir (ucuz); değilse ilk kez %100'ün altına inildiğinde
    /// tap + aggregate device kurulur.
    func setVolume(_ value: Double, for app: AudioPlayingApp) {
        let clamped = min(max(value, 0), 1)
        volumes[app.id] = clamped

        if let session = sessions[app.id] {
            session.gain.value = Float(clamped)
            // Tam %100'e dönünce oturumu tamamen kapatıyoruz: sürekli bir
            // tap açık tutmak yerine sesin doğrudan yola dönmesi daha
            // güvenilir (format uyuşmazlığı, cihaz değişimi gibi uç
            // durumlarda hiçbir şeyin sessiz kalmaması garanti olur).
            if clamped >= 0.999 {
                teardown(app.id)
                volumes[app.id] = nil
            }
            return
        }

        guard clamped < 0.999 else { return }
        startSession(for: app, initialGain: Float(clamped))
    }

    func resetVolume(for pid: pid_t) {
        volumes[pid] = nil
        teardown(pid)
    }

    /// Bir uygulama kapandığında (artık `playingApps` listesinde değilse)
    /// kalıntı oturumunu temizler.
    func pruneSessions(activePIDs: Set<pid_t>) {
        for pid in sessions.keys where !activePIDs.contains(pid) {
            teardown(pid)
            volumes[pid] = nil
        }
    }

    // MARK: - Oturum kurulumu

    private func startSession(for app: AudioPlayingApp, initialGain: Float) {
        guard let outputUID = Self.defaultOutputDeviceUID() else { return }

        let description = CATapDescription(stereoMixdownOfProcesses: [app.processObjectID])
        description.muteBehavior = .muted
        // `privateTap` yeni SDK'da `isPrivate` olarak yeniden adlandırıldı.
        description.isPrivate = true
        description.name = "GlassDo — \(app.name)"

        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            volumes[app.id] = nil
            return
        }

        guard let tapUID = Self.stringProperty(tapID, kAudioTapPropertyUID) else {
            AudioHardwareDestroyProcessTap(tapID)
            volumes[app.id] = nil
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GlassDo Volume — \(app.name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ],
        ]

        var aggregateID = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0
        else {
            AudioHardwareDestroyProcessTap(tapID)
            volumes[app.id] = nil
            return
        }

        let session = TapSession(tapID: tapID, aggregateID: aggregateID)
        session.gain.value = initialGain

        guard session.start() else {
            session.teardown()
            volumes[app.id] = nil
            return
        }

        sessions[app.id] = session
    }

    private func teardown(_ pid: pid_t) {
        sessions[pid]?.teardown()
        sessions[pid] = nil
    }

    // MARK: - CoreAudio yardımcıları

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != 0 else { return nil }
        return stringProperty(device, kAudioDevicePropertyDeviceUID)
    }

    fileprivate static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - Ses parçacığı oturumu

/// Tek bir sürecin tap + aggregate device + IOProc oturumu.
///
/// `gain` gerçek zamanlı ses parçacığından (audio thread) okunuyor — Swift
/// eşzamanlılık modelinin tamamen dışında, `os_unfair_lock` ile korunan
/// düz bir kutu üzerinden. IOProc bir `@convention(c)` geri çağrısı olduğu
/// için `MainActor`'a hiç uğramıyor: `WindowSwitcherController`'daki
/// `CGEventTap` köprüsüyle aynı gerekçe, ama burada gerçek zamanlı ses
/// kısıtı ekleniyor — kilit, aktör sıçraması değil.
private final class TapSession {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let gain = GainBox()
    private var ioProcID: AudioDeviceIOProcID?

    init(tapID: AudioObjectID, aggregateID: AudioObjectID) {
        self.tapID = tapID
        self.aggregateID = aggregateID
    }

    func start() -> Bool {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var procID: AudioDeviceIOProcID?
        guard AudioDeviceCreateIOProcID(aggregateID, perAppVolumeIOProc, selfPtr, &procID) == noErr,
              let procID
        else { return false }

        guard AudioDeviceStart(aggregateID, procID) == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            return false
        }

        ioProcID = procID
        return true
    }

    /// Yakalanan örnekleri kazançla çarpıp çıkış tamponuna kopyalar.
    /// Gerçek zamanlı yol: bellek ayırmıyor, kilitlenmiyor (gain okuması
    /// hariç — o da `os_unfair_lock` ile öngörülebilir sürede).
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let g = gain.value
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)

        for index in 0..<outList.count {
            let outBuffer = outList[index]
            guard let outData = outBuffer.mData else { continue }
            let frameCount = Int(outBuffer.mDataByteSize) / MemoryLayout<Float32>.size
            let outPtr = outData.assumingMemoryBound(to: Float32.self)

            if index < inList.count, let inData = inList[index].mData {
                let inPtr = inData.assumingMemoryBound(to: Float32.self)
                let inFrameCount = Int(inList[index].mDataByteSize) / MemoryLayout<Float32>.size
                let n = min(frameCount, inFrameCount)
                for i in 0..<n { outPtr[i] = inPtr[i] * g }
                for i in n..<frameCount { outPtr[i] = 0 }
            } else {
                for i in 0..<frameCount { outPtr[i] = 0 }
            }
        }
    }

    func teardown() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
    }
}

/// Ses parçacığından (audio thread) okunan tek bir kazanç değeri.
/// `@unchecked Sendable`: `os_unfair_lock` korumalı, sözcük hizalı tekil
/// bir `Float` — gerçek zamanlı ses geri çağrılarında knob değeri
/// paylaşmanın standart, kilitlenmesi öngörülebilir yolu.
private final class GainBox: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var stored: Float = 1

    var value: Float {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return stored
        }
        set {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            stored = newValue
        }
    }
}

/// `AudioDeviceIOProc` bir `@convention(c)` fonksiyon işaretçisi bekler —
/// Swift closure'ları context yakalayamaz, bu yüzden serbest bir fonksiyon
/// olarak tanımlanıp `inClientData` üzerinden oturuma erişiyor.
private func perAppVolumeIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }
    let session = Unmanaged<TapSession>.fromOpaque(inClientData).takeUnretainedValue()
    session.render(input: inInputData, output: outOutputData)
    return noErr
}
