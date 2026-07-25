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
    static let reviewDigestIdentifier = "review-digest"

    weak var delegate: NotificationSchedulerDelegate?
    @Published private(set) var scheduledCount = 0
    @Published private(set) var permissionStatus = NotificationPermissionStatus.notDetermined

    private let client: CoreClientProtocol
    private let center: UserNotificationCenterServing
    private let currentTimestamp: () -> Int64
    private let calendar: Calendar

    init(
        client: CoreClientProtocol,
        center: UserNotificationCenterServing = SystemUserNotificationCenter(),
        currentTimestamp: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        },
        calendar: Calendar = .current
    ) {
        self.client = client
        self.center = center
        self.currentTimestamp = currentTimestamp
        self.calendar = calendar
        super.init()
    }

    nonisolated static func adjustedReviewDeliveryDate(
        _ dueDate: Date,
        calendar: Calendar
    ) -> Date {
        let hour = calendar.component(.hour, from: dueDate)
        guard hour >= 21 || hour < 9 else { return dueDate }

        let targetDay: Date
        if hour >= 21 {
            targetDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: dueDate
            ) ?? dueDate
        } else {
            targetDay = dueDate
        }

        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: targetDay
        ) ?? dueDate
    }

    private func nextReviewDigest(
        now: Int64
    ) async throws -> (dueAt: Int64, count: UInt32)? {
        let dueNow = try await client.dueCardCount(now: now)
        if dueNow > 0 {
            return (now, dueNow)
        }

        guard let next = try await client.nextCardDueAt(now: now) else {
            return nil
        }
        let count = try await client.dueCardCount(now: next)
        return count > 0 ? (next, count) : nil
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
        let now = currentTimestamp()
        var registeredCount = 0

        do {
            let reminders = try await client.pendingReminders(
                limit: 56,
                now: now
            )

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
                var components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: date
                )
                components.timeZone = calendar.timeZone
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
        } catch {
            // Review scheduling remains independent when reminder replay fails.
        }

        do {
            let pendingDigest = try await nextReviewDigest(now: now)
            if let digest = pendingDigest {
                let dueDate = Date(
                    timeIntervalSince1970: TimeInterval(digest.dueAt)
                )
                let adjusted = Self.adjustedReviewDeliveryDate(
                    dueDate,
                    calendar: calendar
                )
                // One second keeps an already-due daytime calendar trigger in
                // the future after truncating the Unix timestamp.
                let deliveryDate = digest.dueAt <= now && adjusted == dueDate
                    ? adjusted.addingTimeInterval(1)
                    : adjusted
                var components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: deliveryDate
                )
                components.timeZone = calendar.timeZone

                let content = UNMutableNotificationContent()
                content.title = "🐱 有 \(digest.count) 张卡片等你"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: Self.reviewDigestIdentifier,
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                    registeredCount += 1
                } catch {
                    // The accepted request count remains authoritative.
                }
            }
        } catch {
            // Reminder replay remains useful if the review query fails.
        }

        scheduledCount = registeredCount
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
