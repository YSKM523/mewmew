import Combine
import Foundation
import UserNotifications

struct NotificationScheduleState: Equatable, Sendable {
    let scheduledCount: Int
    let permissionStatus: NotificationPermissionStatus
}

@MainActor
protocol NotificationSchedulerDelegate: AnyObject {
    func notificationSchedulerDidChangeMemories(completed: Bool) async
    func notificationSchedulerDidSelectMemory(id: String) async
}

@MainActor
protocol NotificationScheduling: AnyObject {
    var delegate: NotificationSchedulerDelegate? { get set }
    var scheduledCount: Int { get }
    var permissionStatus: NotificationPermissionStatus { get }

    func registerCategories()
    func requestAuthorization() async
    @discardableResult func sync() async -> NotificationScheduleState
}

@MainActor
protocol UserNotificationCenterServing: AnyObject {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
    func authorizationStatus() async -> NotificationPermissionStatus
    func removeAllPendingNotificationRequests()
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
final class SystemUserNotificationCenter: UserNotificationCenterServing {
    private let center: UNUserNotificationCenter

    // nonisolated so this can serve as a default argument: those are evaluated
    // outside any actor, and the type itself is @MainActor.
    nonisolated init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
        center.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                continuation.resume(returning: granted && error == nil)
            }
        }
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: NotificationPermissionStatus
                switch settings.authorizationStatus {
                case .notDetermined:
                    status = .notDetermined
                case .denied:
                    status = .denied
                case .authorized, .provisional, .ephemeral:
                    status = .authorized
                @unknown default:
                    status = .notDetermined
                }
                continuation.resume(returning: status)
            }
        }
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: Void())
                }
            }
        }
    }
}

@MainActor
final class NotificationScheduler: NSObject, ObservableObject, NotificationScheduling,
    UNUserNotificationCenterDelegate
{
    static let categoryIdentifier = "reminder"
    static let completeActionIdentifier = "COMPLETE"
    static let snoozeActionIdentifier = "SNOOZE"

    weak var delegate: NotificationSchedulerDelegate?
    @Published private(set) var scheduledCount = 0
    @Published private(set) var permissionStatus = NotificationPermissionStatus.notDetermined

    private let client: CoreClientProtocol
    private let center: UserNotificationCenterServing
    private let currentTimestamp: () -> Int64

    init(
        client: CoreClientProtocol,
        center: UserNotificationCenterServing = SystemUserNotificationCenter(),
        currentTimestamp: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        }
    ) {
        self.client = client
        self.center = center
        self.currentTimestamp = currentTimestamp
        super.init()
    }

    func registerCategories() {
        let complete = UNNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "记下了",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "等会儿",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )

        center.setDelegate(self)
        center.setNotificationCategories(Set([category]))
    }

    func requestAuthorization() async {
        _ = await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        permissionStatus = await center.authorizationStatus()
    }

    @discardableResult
    func sync() async -> NotificationScheduleState {
        center.removeAllPendingNotificationRequests()
        permissionStatus = await center.authorizationStatus()

        do {
            let reminders = try await client.pendingReminders(
                limit: 56,
                now: currentTimestamp()
            )
            var registeredCount = 0

            for memory in reminders {
                guard let dueAt = memory.dueAt else { continue }

                let content = UNMutableNotificationContent()
                content.title = "🐱 \(memory.title)"
                content.body = memory.rawText
                content.sound = .default
                content.categoryIdentifier = Self.categoryIdentifier
                content.userInfo = ["memoryId": memory.id]

                let date = Date(
                    timeIntervalSince1970: TimeInterval(dueAt)
                )
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: date
                )
                components.timeZone = .current
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "reminder-\(memory.id)",
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                    registeredCount += 1
                } catch {
                    // Keep replaying the remaining reminders and expose the
                    // count that was actually accepted by the notification
                    // center.
                }
            }

            scheduledCount = registeredCount
        } catch {
            scheduledCount = 0
        }

        return NotificationScheduleState(
            scheduledCount: scheduledCount,
            permissionStatus: permissionStatus
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let memoryID = response.notification.request.content
            .userInfo["memoryId"] as? String

        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self, let memoryID else { return }

            if actionIdentifier == UNNotificationDefaultActionIdentifier {
                await delegate?.notificationSchedulerDidSelectMemory(id: memoryID)
                return
            }

            let now = currentTimestamp()
            var completed = false

            do {
                switch actionIdentifier {
                case Self.completeActionIdentifier:
                    _ = try await client.completeReminder(id: memoryID, now: now)
                    completed = true
                case Self.snoozeActionIdentifier:
                    _ = try await client.snoozeReminder(
                        id: memoryID,
                        newDueAt: now + 1_800,
                        now: now
                    )
                default:
                    return
                }
            } catch {
                // The UI refresh below remains authoritative when an action
                // races with a delete or another completion.
            }

            await sync()
            await delegate?.notificationSchedulerDidChangeMemories(
                completed: completed
            )
        }
    }
}
