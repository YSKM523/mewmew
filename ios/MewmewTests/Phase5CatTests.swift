import Foundation
import XCTest
@testable import Mewmew

@MainActor
final class Phase5CatTests: XCTestCase {
    func testLevelProgressUsesCoreThresholdsAtBoundaries() {
        let cases: [(xp: Int64, level: Int64, fraction: Double)] = [
            (29, 1, 29.0 / 30.0),
            (30, 2, 0),
            (79, 2, 49.0 / 50.0),
            (80, 3, 0),
        ]

        for item in cases {
            let progress = CatLevelProgress(xp: item.xp)

            XCTAssertEqual(progress.level, item.level, "xp=\(item.xp)")
            XCTAssertEqual(
                progress.fraction,
                item.fraction,
                accuracy: 0.000_001,
                "xp=\(item.xp)"
            )
        }
    }

    func testFeedInvalidShowsFriendlyMessageWithoutChangingStatus() async {
        let originalStatus = CatStatus(
            level: 1,
            xp: 20,
            fish: 1,
            mood: "happy",
            outfit: "none"
        )
        let core = Phase5FakeCore(
            status: originalStatus
        )
        let model = AppModel(
            client: core,
            parseClient: Phase5NoopParseClient(),
            recallClient: Phase5NoopRecallClient(),
            notificationScheduler: Phase5NoopNotificationScheduler(),
            promptDefaults: UserDefaults.standard,
            currentTimestamp: { TestFixtures.now },
            currentDate: {
                Date(timeIntervalSince1970: TimeInterval(TestFixtures.now))
            }
        )

        await model.refresh()
        await model.feedCat()

        XCTAssertEqual(model.catStatus, originalStatus)
        XCTAssertEqual(
            model.errorMessage,
            "没有小鱼干了,完成提醒或复习就能得到"
        )
        let feedCallCount = await core.receivedFeedCallCount()
        XCTAssertEqual(feedCallCount, 1)
    }

    func testFeedWithNoFishShowsFriendlyMessageWithoutCallingCore() async {
        let emptyStatus = CatStatus(
            level: 1,
            xp: 20,
            fish: 0,
            mood: "content",
            outfit: "none"
        )
        let core = Phase5FakeCore(status: emptyStatus)
        let model = AppModel(
            client: core,
            parseClient: Phase5NoopParseClient(),
            recallClient: Phase5NoopRecallClient(),
            notificationScheduler: Phase5NoopNotificationScheduler(),
            promptDefaults: UserDefaults.standard,
            currentTimestamp: { TestFixtures.now },
            currentDate: {
                Date(timeIntervalSince1970: TimeInterval(TestFixtures.now))
            }
        )

        await model.refresh()
        await model.feedCat()

        XCTAssertEqual(model.catStatus, emptyStatus)
        XCTAssertEqual(
            model.errorMessage,
            "没有小鱼干了,完成提醒或复习就能得到"
        )
        let feedCallCount = await core.receivedFeedCallCount()
        XCTAssertEqual(feedCallCount, 0)
    }
}

private actor Phase5FakeCore: CoreClientProtocol {
    private let status: CatStatus
    private var feedCallCount = 0

    init(status: CatStatus) {
        self.status = status
    }

    func addMemory(memory: NewMemory, now: Int64) async throws -> Memory {
        throw Phase5TestError.unexpectedCall
    }

    func getMemory(id: String) async throws -> Memory {
        throw Phase5TestError.unexpectedCall
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
        throw Phase5TestError.unexpectedCall
    }

    func listMemories(kind: MemoryKind?) async throws -> [Memory] {
        []
    }

    func pendingReminders(limit: UInt32, now: Int64) async throws -> [Memory] {
        []
    }

    func completeReminder(id: String, now: Int64) async throws -> Memory {
        throw Phase5TestError.unexpectedCall
    }

    func snoozeReminder(
        id: String,
        newDueAt: Int64,
        now: Int64
    ) async throws -> Memory {
        throw Phase5TestError.unexpectedCall
    }

    func deleteMemory(id: String, now: Int64) async throws {}

    func catStatusAt(now: Int64) async throws -> CatStatus {
        status
    }

    func feedCat(now: Int64) async throws -> CatStatus {
        feedCallCount += 1
        throw CoreError.Invalid("没有小鱼干了")
    }

    func unlockedOutfits() async throws -> [String] {
        ["none"]
    }

    func setOutfit(outfit: String, now: Int64) async throws -> CatStatus {
        throw Phase5TestError.unexpectedCall
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

    func dueCardCount(now: Int64) async throws -> UInt32 {
        0
    }

    func nextCardDueAt(now: Int64) async throws -> Int64? {
        nil
    }

    func dueCards(limit: UInt32, now: Int64) async throws -> [Memory] {
        []
    }

    func reviewCard(
        id: String,
        rating: ReviewRating,
        now: Int64
    ) async throws -> ReviewOutcome {
        throw Phase5TestError.unexpectedCall
    }

    func receivedFeedCallCount() -> Int {
        feedCallCount
    }
}

private actor Phase5NoopParseClient: ParseServing {
    func parse(
        text: String,
        timeZone: TimeZone,
        now: Date
    ) async -> ParseResult? {
        nil
    }
}

private actor Phase5NoopRecallClient: RecallServing {
    func recall(question: String, memories: [Memory]) async -> RecallResult? {
        nil
    }
}

@MainActor
private final class Phase5NoopNotificationScheduler: NotificationScheduling {
    weak var delegate: NotificationSchedulerDelegate?
    private(set) var scheduledCount = 0
    private(set) var permissionStatus =
        NotificationPermissionStatus.notDetermined

    func registerCategories() {}

    func requestAuthorization() async {}

    func sync() async -> NotificationScheduleState {
        NotificationScheduleState(
            scheduledCount: scheduledCount,
            permissionStatus: permissionStatus
        )
    }
}

private enum Phase5TestError: Error {
    case unexpectedCall
}
