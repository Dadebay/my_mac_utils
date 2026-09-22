import Darwin
import Foundation

/// Bir süreci sonlandırmanın güvenli olup olmadığına karar veren ortak
/// kurallar.
///
/// Hem bellek panelinin süreç listesi hem ağ panelinin "en çok kullananlar"
/// listesi aynı soruyu soruyor. İki yerde ayrı ayrı yazılsaydı korunan
/// isimler listesi zamanla birbirinden ayrışırdı — biri güncellenip öteki
/// unutulurdu.
enum ProcessSafety {

    /// Sonlandırılırsa oturumu kullanılamaz hâle getiren süreçler.
    ///
    /// Root'a ait olanların çoğu zaten `isOwnedByCurrentUser` kapısından
    /// geçemiyor; bunlar kullanıcının kendi oturumunda çalışıp yine de
    /// vazgeçilmez olanlar.
    static let protectedNames: Set<String> = [
        "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer", "launchd",
    ]

    /// Süreç bu kullanıcıya mı ait?
    ///
    /// Root'a ait bir sürece sinyal göndermek `EPERM` ile başarısız oluyor.
    /// Denemeden önce bilmek gerekiyor: yoksa düğme etkin görünür, basılır
    /// ve hiçbir şey olmaz — kullanıcı da uygulamanın bozuk olduğunu
    /// düşünür.
    static func isOwnedByCurrentUser(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return false }

        return info.kp_eproc.e_ucred.cr_uid == getuid()
    }

    /// Bu süreç sonlandırılabilir mi?
    ///
    /// - `launchd` (PID 1) hiçbir koşulda.
    /// - GlassDo'nun kendisi hiçbir koşulda.
    /// - Oturumun ayakta durmasını sağlayan süreçler hiçbir koşulda.
    /// - Bu kullanıcıya ait olmayanlar: teknik olarak imkânsız.
    static func canTerminate(pid: pid_t, name: String) -> Bool {
        guard pid > 1, pid != ProcessInfo.processInfo.processIdentifier else { return false }
        guard !protectedNames.contains(name) else { return false }
        return isOwnedByCurrentUser(pid)
    }
}
