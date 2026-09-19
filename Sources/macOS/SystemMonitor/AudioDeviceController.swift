import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Bir ses cihazı — çıkış (hoparlör/kulaklık) ya da giriş (mikrofon).
struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let name: String
    /// Sistemin kendi varsayılan cihazı mı.
    var isDefault: Bool
}

/// O anda ses çalan bir uygulama.
///
/// macOS'un **normal** ses sistemi uygulama başına seviye sunmuyor —
/// `kAudioProcessProperty*` yalnızca PID, bundle kimliği ve "çalıyor mu"
/// bilgisini veriyor. Ama macOS 14.2+'ın Core Audio **process tap** API'si
/// (genel, dokümante edilmiş) bunu gerçekten mümkün kılıyor: bkz.
/// `PerAppVolumeController`. `processObjectID`, o API'nin tap kurmak için
/// istediği kimlik — `id` (pid) değil.
struct AudioPlayingApp: Identifiable, Equatable, Sendable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let processObjectID: AudioObjectID
}

/// Sistem ses çıkışını, girişini ve o anda ses çalan uygulamaları okur.
///
/// `SystemStatsController` ile aynı desen: tek örnek, sayaçlı `start()`/
/// `stop()`, tüketici kalmayınca dinleyiciler bırakılıyor. Fark, buranın
/// bir zamanlayıcıya değil CoreAudio'nun kendi değişiklik bildirimlerine
/// bağlı olması — ses seviyesi saniyede bir yoklanacak bir büyüklük değil,
/// kullanıcı ya da başka bir uygulama değiştirdiğinde haber geliyor.
@MainActor
@Observable
final class AudioDeviceController {
    static let shared = AudioDeviceController()

    private(set) var outputDevices: [AudioDevice] = []
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var playingApps: [AudioPlayingApp] = []

    /// 0…1. Cihaz seviye ayarını desteklemiyorsa (bazı HDMI/dijital
    /// çıkışlar) `nil` — kayan çubuk yerine açıklama gösterilir.
    private(set) var outputVolume: Double?
    private(set) var isOutputMuted = false

    private var subscribers = 0
    /// Blok da saklanıyor: `AudioObjectRemovePropertyListenerBlock` dinleyiciyi
    /// **blok kimliğiyle** eşleştiriyor. Kaldırırken yeni bir kapanış vermek
    /// hiçbir şeyi kaldırmaz — eskiler birikir ve her değişiklikte hepsi
    /// birden ateşlenir.
    private var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    /// Cihaza özel dinleyicilerin (seviye, sessiz) bağlı olduğu çıkış.
    /// Varsayılan çıkış değişmediği sürece yeniden kurulmaları gerekmiyor.
    private var listenedOutputDevice: AudioObjectID?
    /// Ses çalan uygulama listesi bildirimle gelmiyor; yalnızca panel
    /// açıkken ve seyrek yoklanıyor.
    private var pollTask: _Concurrency.Task<Void, Never>?
    private static let pollInterval: Duration = .seconds(3)

    private init() {}

    // MARK: - Yaşam döngüsü

    func start() {
        subscribers += 1
        guard subscribers == 1 else { return }

        refreshDevices()
        refreshVolume()
        refreshPlayingApps()
        installListeners()

        pollTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: Self.pollInterval)
                guard !_Concurrency.Task.isCancelled else { return }
                self?.refreshPlayingApps()
            }
        }
    }

    func stop() {
        subscribers = max(subscribers - 1, 0)
        guard subscribers == 0 else { return }

        pollTask?.cancel()
        pollTask = nil
        removeListeners()
    }

    // MARK: - Kullanıcı eylemleri

    func setOutputVolume(_ value: Double) {
        guard let device = defaultDevice(scope: .output) else { return }
        var scalar = Float32(min(max(value, 0), 1))
        var address = Self.virtualMainVolumeAddress
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar
        )
        // Sessizken seviye değiştirmek sesi geri açar: kullanıcı çubuğu
        // oynattıysa niyeti sesi duymak.
        if status == noErr {
            outputVolume = Double(scalar)
            if isOutputMuted, scalar > 0 { setOutputMuted(false) }
        }
    }

    func setOutputMuted(_ muted: Bool) {
        guard let device = defaultDevice(scope: .output) else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(
            kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        if AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        ) == noErr {
            isOutputMuted = muted
        }
    }

    func selectOutputDevice(_ device: AudioDevice) {
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
        // Sistem sesleri (uyarılar) ayrı bir varsayılan taşıyor; kullanıcı
        // çıkışı değiştirdiğinde ikisinin ayrışması beklenmiyor.
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        refreshDevices()
        refreshVolume()
    }

    func selectInputDevice(_ device: AudioDevice) {
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultInputDevice)
        refreshDevices()
    }

    private func setDefaultDevice(_ id: AudioObjectID, selector: AudioObjectPropertySelector) {
        var value = id
        var address = Self.address(selector)
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &value
        )
    }

    // MARK: - Okuma

    private func refreshDevices() {
        let all = Self.deviceIDs()
        let defaultOutput = defaultDevice(scope: .output)
        let defaultInput = defaultDevice(scope: .input)

        outputDevices = all.compactMap { id in
            guard Self.channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  let name = Self.name(of: id) else { return nil }
            return AudioDevice(id: id, name: name, isDefault: id == defaultOutput)
        }

        inputDevices = all.compactMap { id in
            guard Self.channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
                  let name = Self.name(of: id) else { return nil }
            return AudioDevice(id: id, name: name, isDefault: id == defaultInput)
        }
    }

    private func refreshVolume() {
        guard let device = defaultDevice(scope: .output) else {
            outputVolume = nil
            isOutputMuted = false
            return
        }

        var address = Self.virtualMainVolumeAddress
        if AudioObjectHasProperty(device, &address) {
            var scalar = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            outputVolume = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &scalar) == noErr
                ? Double(scalar)
                : nil
        } else {
            // Dijital çıkışların çoğunda seviye kaynakta değil, cihazda
            // ayarlanıyor; uydurma bir çubuk göstermek yanlış olurdu.
            outputVolume = nil
        }

        var muteAddress = Self.address(
            kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput
        )
        if AudioObjectHasProperty(device, &muteAddress) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr {
                isOutputMuted = value != 0
            }
        } else {
            isOutputMuted = false
        }
    }

    /// O anda çıkışa ses veren süreçler. GlassDo'nun kendisi listede
    /// görünmüyor — kullanıcı için bilgi taşımıyor.
    private func refreshPlayingApps() {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else {
            playingApps = []
            return
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else {
            playingApps = []
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        var apps: [AudioPlayingApp] = []

        for object in objects {
            guard Self.boolValue(object, kAudioProcessPropertyIsRunningOutput) else { continue }
            guard let pid = Self.pid(of: object), pid != ownPID, seen.insert(pid).inserted else { continue }

            let running = NSRunningApplication(processIdentifier: pid)
            let bundleID = Self.stringValue(object, kAudioProcessPropertyBundleID)
            // Adı olmayan arka plan sesleri (coreaudiod yardımcıları)
            // kullanıcıya bir şey anlatmıyor.
            guard let name = running?.localizedName ?? bundleID else { continue }

            apps.append(AudioPlayingApp(id: pid, name: name, bundleIdentifier: bundleID, processObjectID: object))
        }

        playingApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Kapanmış bir uygulamanın tap oturumu açık kalmasın — aggregate
        // device ve tap, sürecin kendisi yokken de teknik olarak yaşamaya
        // devam eder.
        PerAppVolumeController.shared.pruneSessions(activePIDs: Set(apps.map(\.id)))
    }

    private enum DeviceScope { case output, input }

    private func defaultDevice(scope: DeviceScope) -> AudioObjectID? {
        var address = Self.address(
            scope == .output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice
        )
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != 0 else { return nil }
        return device
    }

    // MARK: - Değişiklik bildirimleri

    /// Seviye/çıkış değişimini yoklamak yerine CoreAudio'nun kendi
    /// bildirimlerine bağlanıyoruz: kullanıcı klavyeden sesi değiştirdiğinde
    /// ya da kulaklık takıldığında panel anında güncelleniyor.
    private func installListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let systemSelectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        for selector in systemSelectors {
            addListener(system, Self.address(selector))
        }

        installOutputDeviceListeners()
    }

    /// Seviye ve sessiz dinleyicileri o anki varsayılan çıkışa bağlı.
    /// Yalnızca çıkış gerçekten değiştiğinde yeniden kuruluyorlar — her
    /// bildirimde hepsini söküp takmak, dinleyicilerin katlanarak
    /// çoğalmasına yol açıyordu.
    private func installOutputDeviceListeners() {
        let device = defaultDevice(scope: .output)
        guard device != listenedOutputDevice else { return }

        if let previous = listenedOutputDevice {
            removeListeners(matching: previous)
        }
        listenedOutputDevice = device

        guard let device else { return }
        addListener(device, Self.virtualMainVolumeAddress)
        addListener(device, Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput))
    }

    private func addListener(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshDevices()
                self.refreshVolume()
                // Varsayılan çıkış değiştiyse cihaza bağlı dinleyiciler
                // yanlış nesneye bakıyor; yalnızca onlar taşınıyor.
                self.installOutputDeviceListeners()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners(matching object: AudioObjectID? = nil) {
        let doomed = listeners.filter { object == nil || $0.object == object }
        for entry in doomed {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(
                entry.object, &address, DispatchQueue.main, entry.block
            )
        }
        listeners.removeAll { object == nil || $0.object == object }
        if object == nil { listenedOutputDevice = nil }
    }

    // MARK: - CoreAudio yardımcıları

    private static let virtualMainVolumeAddress = address(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        scope: kAudioObjectPropertyScopeOutput
    )

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// Bir cihazın o yöndeki kanal sayısı — sıfırsa cihaz o yönde
    /// kullanılamaz (mikrofonu çıkış listesinde göstermemek için).
    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of id: AudioObjectID) -> String? {
        stringValue(id, kAudioObjectPropertyName)
    }

    private static func stringValue(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value as String
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func boolValue(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
