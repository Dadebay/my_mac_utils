import Foundation
import GlassDoKit
import SwiftData
import UserNotifications

/// `FocusSessionService`'in üzerine yerel bildirim planlamasını ekler.
/// UI çağrı noktaları yalnızca bu tipi kullanır — bildirim izni isteme ve
/// planlama/iptal her zaman oturum başlangıcı/bitişiyle birlikte yürür.
@MainActor
enum FocusSessionCoordinator {
    @discardableResult
    static func start(task: Task?, duration: FocusDuration, in context: ModelContext) throws -> FocusSession {
        let session = try FocusSessionService.start(task: task, duration: duration, in: context)
        scheduleNotification(for: session)
        return session
    }

    @discardableResult
    static func forceStart(task: Task?, duration: FocusDuration, in context: ModelContext) -> FocusSession {
        if let active = FocusSessionService.activeSession(in: context) {
            cancelNotification(for: active)
        }
        let session = FocusSessionService.forceStart(task: task, duration: duration, in: context)
        scheduleNotification(for: session)
        return session
    }

    static func stop(_ session: FocusSession, reason: FocusSessionEndReason, in context: ModelContext) {
        cancelNotification(for: session)
        FocusSessionService.stop(session, reason: reason, in: context)
    }

    static func complete(_ session: FocusSession, completeTask: Bool, in context: ModelContext) {
        cancelNotification(for: session)
        FocusSessionService.complete(session, completeTask: completeTask, in: context)
    }

    /// İzin yalnızca burada, oturum gerçekten başlarken isteniyor —
    /// önceden veya uygulama açılışında sorulmuyor. İzin yoksa/reddedilmişse
    /// sessizce hiçbir şey planlanmaz; kullanıcı durumu uygulama içinden
    /// (kalan süre 0'a düşünce) görür.
    private static func scheduleNotification(for session: FocusSession) {
        let identifier = session.id.uuidString
        let remaining = session.remainingSeconds()
        guard remaining > 0 else { return }
        let taskTitle = session.task?.title ?? ""

        _Concurrency.Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }

            let current = await center.notificationSettings()
            guard current.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = L10n.focusNotificationTitle
            content.body = L10n.focusNotificationBody(taskTitle)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func cancelNotification(for session: FocusSession) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [session.id.uuidString])
    }
}
