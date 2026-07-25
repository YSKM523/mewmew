import Foundation

protocol ReviewServing: Sendable {
    func dueCardCount(now: Int64) async throws -> UInt32
    func nextCardDueAt(now: Int64) async throws -> Int64?
    func dueCards(limit: UInt32, now: Int64) async throws -> [Memory]
    func reviewCard(
        id: String,
        rating: ReviewRating,
        now: Int64
    ) async throws -> ReviewOutcome
}

protocol CoreClientProtocol: ReviewServing, Sendable {
    func addMemory(memory: NewMemory, now: Int64) async throws -> Memory
    func getMemory(id: String) async throws -> Memory
    func reclassifyMemory(
        id: String,
        kind: MemoryKind,
        title: String,
        dueAt: Int64?,
        question: String?,
        answer: String?,
        now: Int64
    ) async throws -> Memory
    func listMemories(kind: MemoryKind?) async throws -> [Memory]
    func pendingReminders(limit: UInt32, now: Int64) async throws -> [Memory]
    func completeReminder(id: String, now: Int64) async throws -> Memory
    func snoozeReminder(
        id: String,
        newDueAt: Int64,
        now: Int64
    ) async throws -> Memory
    func deleteMemory(id: String, now: Int64) async throws
    func catStatus() async throws -> CatStatus
    func search(queryText: String) async throws -> [Memory]
    func searchForRecall(query: String, limit: UInt32) async throws -> [Memory]
}

actor CoreClient: CoreClientProtocol {
    static let shared = CoreClient(databasePath: defaultDatabasePath)

    static var defaultDatabasePath: String {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return supportDirectory
            .appendingPathComponent("Mewmew", isDirectory: true)
            .appendingPathComponent("mewmew.sqlite3", isDirectory: false)
            .path
    }

    private let databasePath: String
    private var core: MewmewCore?

    init(databasePath: String) {
        self.databasePath = databasePath
    }

    func addMemory(memory: NewMemory, now: Int64) async throws -> Memory {
        try instance().addMemory(memory: memory, now: now)
    }

    func getMemory(id: String) async throws -> Memory {
        try instance().getMemory(id: id)
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
        try instance().reclassifyMemory(
            id: id,
            kind: kind,
            title: title,
            dueAt: dueAt,
            question: question,
            answer: answer,
            now: now
        )
    }

    func listMemories(kind: MemoryKind?) async throws -> [Memory] {
        try instance().listMemories(kind: kind)
    }

    func pendingReminders(limit: UInt32, now: Int64) async throws -> [Memory] {
        try instance().pendingReminders(limit: limit, now: now)
    }

    func dueCardCount(now: Int64) async throws -> UInt32 {
        try instance().dueCardCount(now: now)
    }

    func nextCardDueAt(now: Int64) async throws -> Int64? {
        try instance().nextCardDueAt(now: now)
    }

    func dueCards(limit: UInt32, now: Int64) async throws -> [Memory] {
        try instance().dueCards(limit: limit, now: now)
    }

    func reviewCard(
        id: String,
        rating: ReviewRating,
        now: Int64
    ) async throws -> ReviewOutcome {
        try instance().reviewCard(id: id, rating: rating, now: now)
    }

    func completeReminder(id: String, now: Int64) async throws -> Memory {
        try instance().completeReminder(id: id, now: now)
    }

    func snoozeReminder(
        id: String,
        newDueAt: Int64,
        now: Int64
    ) async throws -> Memory {
        try instance().snoozeReminder(
            id: id,
            newDueAt: newDueAt,
            now: now
        )
    }

    func deleteMemory(id: String, now: Int64) async throws {
        try instance().deleteMemory(id: id, now: now)
    }

    func catStatus() async throws -> CatStatus {
        try instance().catStatus()
    }

    func search(queryText: String) async throws -> [Memory] {
        try instance().search(queryText: queryText)
    }

    func searchForRecall(
        query: String,
        limit: UInt32
    ) async throws -> [Memory] {
        try instance().searchForRecall(query: query, limit: limit)
    }

    private func instance() throws -> MewmewCore {
        if let core {
            return core
        }

        let databaseURL = URL(fileURLWithPath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let newCore = try MewmewCore(dbPath: databasePath)
        core = newCore
        return newCore
    }
}
