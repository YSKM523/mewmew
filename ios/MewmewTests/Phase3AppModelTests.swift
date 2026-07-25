import Foundation
import XCTest
@testable import Mewmew

@MainActor
final class Phase3AppModelTests: XCTestCase {
    func testRecallFailureUsesEightLocalMatchesAndShowsFallback() async {
        let memories = (0..<10).map { index in
            Memory(
                id: "memory-\(index)",
                kind: .note,
                rawText: "护照位置 \(index)",
                title: "护照 \(index)",
                dueAt: nil,
                completedAt: nil,
                question: nil,
                answer: nil,
                createdAt: TestFixtures.now - Int64(index),
                updatedAt: TestFixtures.now - Int64(index)
            )
        }
        let core = FakeCoreClient(memories: memories)
        let recall = FakeRecallClient(result: nil)
        let scheduler = FakeNotificationScheduler()
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            client: core,
            parseClient: FakeParseClient(result: nil),
            recallClient: recall,
            notificationScheduler: scheduler,
            promptDefaults: defaults,
            currentTimestamp: { TestFixtures.now },
            currentDate: { Date(timeIntervalSince1970: TimeInterval(TestFixtures.now)) }
        )

        model.setSearchText("护照放哪了？")
        model.submitRecall()
        await waitUntil { !model.isRecalling }

        XCTAssertEqual(
            model.recallPresentation?.message,
            "猫有点困,先看看这些记忆吧"
        )
        XCTAssertEqual(model.recallPresentation?.listedMemories.count, 8)
        let receivedMemoryCount = await recall.receivedMemoryCount()
        XCTAssertEqual(receivedMemoryCount, 8)
    }

    func testFirstReclassifiedReminderRequestsPermissionOnlyOnce() async {
        let core = FakeCoreClient(memories: [])
        let parse = FakeParseClient(
            result: ParseResult(
                kind: .reminder,
                title: "交电费",
                dueAt: TestFixtures.now + 3_600,
                question: nil,
                answer: nil,
                confidence: 0.99
            )
        )
        let scheduler = FakeNotificationScheduler()
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let model = AppModel(
            client: core,
            parseClient: parse,
            recallClient: FakeRecallClient(result: nil),
            notificationScheduler: scheduler,
            promptDefaults: defaults,
            currentTimestamp: { TestFixtures.now },
            currentDate: { Date(timeIntervalSince1970: TimeInterval(TestFixtures.now)) }
        )

        let firstCaptureSaved = await model.captureNote("一小时后提醒我交电费")
        XCTAssertTrue(firstCaptureSaved)
        await waitUntil { scheduler.authorizationRequestCount == 1 }
        let secondCaptureSaved = await model.captureNote("一小时后提醒我关窗")
        XCTAssertTrue(secondCaptureSaved)
        await waitUntil { scheduler.syncCount >= 4 }

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertTrue(scheduler.didRegisterCategories)
    }

    private var defaultsSuiteName: String {
        "Phase3AppModelTests"
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for async model state", file: file, line: line)
    }
}

private actor FakeCoreClient: CoreClientProtocol {
    private var memories: [Memory]
    private var nextID = 0

    init(memories: [Memory]) {
        self.memories = memories
    }

    func addMemory(memory: NewMemory, now: Int64) async throws -> Memory {
        nextID += 1
        let saved = Memory(
            id: "saved-\(nextID)",
            kind: memory.kind,
            rawText: memory.rawText,
            title: memory.title,
            dueAt: memory.dueAt,
            completedAt: nil,
            question: memory.question,
            answer: memory.answer,
            createdAt: now,
            updatedAt: now
        )
        memories.append(saved)
        return saved
    }

    func getMemory(id: String) async throws -> Memory {
        memories.first { $0.id == id }!
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
        let existing = memories.first { $0.id == id }!
        let updated = Memory(
            id: existing.id,
            kind: kind,
            rawText: existing.rawText,
            title: title,
            dueAt: dueAt,
            completedAt: existing.completedAt,
            question: question,
            answer: answer,
            createdAt: existing.createdAt,
            updatedAt: now
        )
        memories.removeAll { $0.id == id }
        memories.append(updated)
        return updated
    }

    func listMemories(kind: MemoryKind?) async throws -> [Memory] {
        guard let kind else { return memories }
        return memories.filter { $0.kind == kind }
    }

    func pendingReminders(limit: UInt32, now: Int64) async throws -> [Memory] {
        Array(
            memories.filter {
                $0.kind == .reminder
                    && $0.completedAt == nil
                    && ($0.dueAt ?? 0) > now
            }
            .prefix(Int(limit))
        )
    }

    func completeReminder(id: String, now: Int64) async throws -> Memory {
        try await getMemory(id: id)
    }

    func snoozeReminder(
        id: String,
        newDueAt: Int64,
        now: Int64
    ) async throws -> Memory {
        try await getMemory(id: id)
    }

    func deleteMemory(id: String, now: Int64) async throws {
        memories.removeAll { $0.id == id }
    }

    func catStatus() async throws -> CatStatus {
        TestFixtures.catStatus
    }

    func search(queryText: String) async throws -> [Memory] {
        memories
    }

    func searchForRecall(
        query: String,
        limit: UInt32
    ) async throws -> [Memory] {
        Array(memories.prefix(Int(limit)))
    }
}

private actor FakeParseClient: ParseServing {
    private let result: ParseResult?

    init(result: ParseResult?) {
        self.result = result
    }

    func parse(
        text: String,
        timeZone: TimeZone,
        now: Date
    ) async -> ParseResult? {
        result
    }
}

private actor FakeRecallClient: RecallServing {
    private let result: RecallResult?
    private var memoryCount = 0

    init(result: RecallResult?) {
        self.result = result
    }

    func recall(question: String, memories: [Memory]) async -> RecallResult? {
        memoryCount = memories.count
        return result
    }

    func receivedMemoryCount() -> Int {
        memoryCount
    }
}

@MainActor
private final class FakeNotificationScheduler: NotificationScheduling {
    weak var delegate: NotificationSchedulerDelegate?
    private(set) var scheduledCount = 0
    private(set) var permissionStatus = NotificationPermissionStatus.denied
    private(set) var authorizationRequestCount = 0
    private(set) var syncCount = 0
    private(set) var didRegisterCategories = false

    func registerCategories() {
        didRegisterCategories = true
    }

    func requestAuthorization() async {
        authorizationRequestCount += 1
        permissionStatus = .authorized
    }

    func sync() async -> NotificationScheduleState {
        syncCount += 1
        return NotificationScheduleState(
            scheduledCount: scheduledCount,
            permissionStatus: permissionStatus
        )
    }
}
