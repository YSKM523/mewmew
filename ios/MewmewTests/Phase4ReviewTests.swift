import Foundation
import UserNotifications
import XCTest
@testable import Mewmew

@MainActor
final class Phase4ReviewTests: XCTestCase {
    func testQuietHoursMoveEarlyMorningToNineOnTheSameDay() {
        let calendar = makeCalendar()
        let dueDate = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 3,
            minute: 15,
            calendar: calendar
        )

        let adjusted = NotificationScheduler.adjustedReviewDeliveryDate(
            dueDate,
            calendar: calendar
        )

        XCTAssertEqual(
            adjusted,
            date(
                year: 2025,
                month: 1,
                day: 2,
                hour: 9,
                minute: 0,
                calendar: calendar
            )
        )
    }

    func testQuietHoursMoveNineAtNightToNineTheNextDay() {
        let calendar = makeCalendar()
        let dueDate = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 21,
            minute: 0,
            calendar: calendar
        )

        let adjusted = NotificationScheduler.adjustedReviewDeliveryDate(
            dueDate,
            calendar: calendar
        )

        XCTAssertEqual(
            adjusted,
            date(
                year: 2025,
                month: 1,
                day: 3,
                hour: 9,
                minute: 0,
                calendar: calendar
            )
        )
    }

    func testQuietHoursLeaveNineInTheMorningAndDaytimeUnchanged() {
        let calendar = makeCalendar()
        let nineAM = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 9,
            minute: 0,
            calendar: calendar
        )
        let daytime = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 20,
            minute: 59,
            calendar: calendar
        )

        XCTAssertEqual(
            NotificationScheduler.adjustedReviewDeliveryDate(
                nineAM,
                calendar: calendar
            ),
            nineAM
        )
        XCTAssertEqual(
            NotificationScheduler.adjustedReviewDeliveryDate(
                daytime,
                calendar: calendar
            ),
            daytime
        )
    }

    func testReviewSessionAdvancesAndAccumulatesOnlyEarnedFish() async {
        let cards = [reviewCard(id: "card-1"), reviewCard(id: "card-2")]
        let client = FakeReviewClient(
            cards: cards,
            earnedFishByCardID: [
                "card-1": false,
                "card-2": true,
            ]
        )
        let model = ReviewSessionModel(
            client: client,
            currentTimestamp: { TestFixtures.now }
        )

        await model.load()
        XCTAssertEqual(model.totalCount, 2)
        XCTAssertEqual(model.currentPosition, 1)
        XCTAssertFalse(model.isAnswerRevealed)

        model.revealAnswer()
        XCTAssertTrue(model.isAnswerRevealed)
        await model.submit(rating: .again)

        XCTAssertEqual(model.reviewedCount, 1)
        XCTAssertEqual(model.earnedFishCount, 0)
        XCTAssertEqual(model.currentPosition, 2)
        XCTAssertFalse(model.isAnswerRevealed)
        XCTAssertFalse(model.isComplete)

        model.revealAnswer()
        await model.submit(rating: .good)

        XCTAssertEqual(model.reviewedCount, 2)
        XCTAssertEqual(model.earnedFishCount, 1)
        XCTAssertTrue(model.isComplete)
        let receivedRatings = await client.receivedRatings()
        XCTAssertEqual(receivedRatings, [.again, .good])
    }

    func testNotificationReplayAddsOneQuietHoursAdjustedReviewDigest() async throws {
        let calendar = makeCalendar()
        let nowDate = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 3,
            minute: 15,
            calendar: calendar
        )
        let now = Int64(nowDate.timeIntervalSince1970)
        let core = FakeNotificationCore(dueCount: 2)
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(
            client: core,
            center: center,
            currentTimestamp: { now },
            calendar: calendar
        )

        let state = await scheduler.sync()

        XCTAssertEqual(state.scheduledCount, 1)
        XCTAssertEqual(center.requests.count, 1)
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(
            request.identifier,
            NotificationScheduler.reviewDigestIdentifier
        )
        XCTAssertEqual(request.content.title, "🐱 有 2 张卡片等你")
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 9)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(trigger?.dateComponents.day, 2)
    }

    func testNotificationReplayDoesNotAddDigestWithoutDueCards() async {
        let calendar = makeCalendar()
        let core = FakeNotificationCore(dueCount: 0)
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(
            client: core,
            center: center,
            currentTimestamp: { TestFixtures.now },
            calendar: calendar
        )

        let state = await scheduler.sync()

        XCTAssertEqual(state.scheduledCount, 0)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testNotificationReplayFindsTheNextFutureDueTime() async throws {
        let calendar = makeCalendar()
        let nowDate = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 10,
            minute: 0,
            calendar: calendar
        )
        let nextDueDate = date(
            year: 2025,
            month: 1,
            day: 2,
            hour: 21,
            minute: 30,
            calendar: calendar
        )
        let core = FakeNotificationCore(
            dueCount: 3,
            nextDueAt: Int64(nextDueDate.timeIntervalSince1970)
        )
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(
            client: core,
            center: center,
            currentTimestamp: {
                Int64(nowDate.timeIntervalSince1970)
            },
            calendar: calendar
        )

        let state = await scheduler.sync()

        XCTAssertEqual(state.scheduledCount, 1)
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.content.title, "🐱 有 3 张卡片等你")
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.day, 3)
        XCTAssertEqual(trigger?.dateComponents.hour, 9)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
    }

    func testNotificationReplayKeepsFiftySixReminderLimitWithDigest() async {
        let reminders = (0..<60).map { index in
            Memory(
                id: "reminder-\(index)",
                kind: .reminder,
                rawText: "提醒 \(index)",
                title: "提醒 \(index)",
                dueAt: TestFixtures.now + 3_600 + Int64(index),
                completedAt: nil,
                question: nil,
                answer: nil,
                createdAt: TestFixtures.now,
                updatedAt: TestFixtures.now
            )
        }
        let core = FakeNotificationCore(
            dueCount: 1,
            reminders: reminders
        )
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(
            client: core,
            center: center,
            currentTimestamp: { TestFixtures.now },
            calendar: makeCalendar()
        )

        let state = await scheduler.sync()
        let receivedLimit = await core.receivedReminderLimit()

        XCTAssertEqual(receivedLimit, UInt32(56))
        XCTAssertEqual(state.scheduledCount, 57)
        XCTAssertEqual(center.requests.count, 57)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func reviewCard(id: String) -> Memory {
        Memory(
            id: id,
            kind: .card,
            rawText: "\(id) raw text",
            title: id,
            dueAt: nil,
            completedAt: nil,
            question: "\(id) question",
            answer: "\(id) answer",
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
    }
}

private actor FakeReviewClient: ReviewServing {
    private let cards: [Memory]
    private let earnedFishByCardID: [String: Bool]
    private var ratings: [ReviewRating] = []

    init(cards: [Memory], earnedFishByCardID: [String: Bool]) {
        self.cards = cards
        self.earnedFishByCardID = earnedFishByCardID
    }

    func dueCardCount(now: Int64) async throws -> UInt32 {
        UInt32(cards.count)
    }

    func nextCardDueAt(now: Int64) async throws -> Int64? {
        nil
    }

    func dueCards(limit: UInt32, now: Int64) async throws -> [Memory] {
        Array(cards.prefix(Int(limit)))
    }

    func reviewCard(
        id: String,
        rating: ReviewRating,
        now: Int64
    ) async throws -> ReviewOutcome {
        ratings.append(rating)
        let card = cards.first { $0.id == id }!
        return ReviewOutcome(
            memory: card,
            nextDueAt: now + 600,
            earnedFish: earnedFishByCardID[id] ?? false
        )
    }

    func receivedRatings() -> [ReviewRating] {
        ratings
    }
}

private actor FakeNotificationCore: CoreClientProtocol {
    private let dueCount: UInt32
    private let nextDueAt: Int64?
    private let reminders: [Memory]
    private var reminderLimit: UInt32?

    init(
        dueCount: UInt32,
        nextDueAt: Int64? = nil,
        reminders: [Memory] = []
    ) {
        self.dueCount = dueCount
        self.nextDueAt = nextDueAt
        self.reminders = reminders
    }

    func addMemory(memory: NewMemory, now: Int64) async throws -> Memory {
        throw Phase4TestError.unexpectedCall
    }

    func getMemory(id: String) async throws -> Memory {
        throw Phase4TestError.unexpectedCall
    }

    func reclassifyMemory(
        id: String,
        kind: MemoryKind,
        title: String,
        dueAt: Int64?,
        question: String?,
        answer: String?,
        now: Int64
    ) async throws -> Memory {
        throw Phase4TestError.unexpectedCall
    }

    func listMemories(kind: MemoryKind?) async throws -> [Memory] {
        []
    }

    func pendingReminders(limit: UInt32, now: Int64) async throws -> [Memory] {
        reminderLimit = limit
        return Array(reminders.prefix(Int(limit)))
    }

    func dueCardCount(now: Int64) async throws -> UInt32 {
        guard let nextDueAt else { return dueCount }
        return now >= nextDueAt ? dueCount : 0
    }

    func nextCardDueAt(now: Int64) async throws -> Int64? {
        guard let nextDueAt, nextDueAt > now else { return nil }
        return nextDueAt
    }

    func dueCards(limit: UInt32, now: Int64) async throws -> [Memory] {
        []
    }

    func reviewCard(
        id: String,
        rating: ReviewRating,
        now: Int64
    ) async throws -> ReviewOutcome {
        throw Phase4TestError.unexpectedCall
    }

    func completeReminder(id: String, now: Int64) async throws -> Memory {
        throw Phase4TestError.unexpectedCall
    }

    func snoozeReminder(
        id: String,
        newDueAt: Int64,
        now: Int64
    ) async throws -> Memory {
        throw Phase4TestError.unexpectedCall
    }

    func deleteMemory(id: String, now: Int64) async throws {}

    func catStatusAt(now: Int64) async throws -> CatStatus {
        TestFixtures.catStatus
    }

    func feedCat(now: Int64) async throws -> CatStatus {
        throw Phase4TestError.unexpectedCall
    }

    func unlockedOutfits() async throws -> [String] {
        ["none"]
    }

    func setOutfit(outfit: String, now: Int64) async throws -> CatStatus {
        throw Phase4TestError.unexpectedCall
    }

    func search(queryText: String) async throws -> [Memory] {
        []
    }

    func searchForRecall(
        query: String,
        limit: UInt32
    ) async throws -> [Memory] {
        []
    }

    func receivedReminderLimit() -> UInt32? {
        reminderLimit
    }
}

@MainActor
private final class FakeNotificationCenter: UserNotificationCenterServing {
    private(set) var requests: [UNNotificationRequest] = []

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {}

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        true
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        .authorized
    }

    func removeAllPendingNotificationRequests() {
        requests = []
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }
}

private enum Phase4TestError: Error {
    case unexpectedCall
}
