import Foundation

actor CoreClient {
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

    func addMemory(memory: NewMemory, now: Int64) throws -> Memory {
        try instance().addMemory(memory: memory, now: now)
    }

    func getMemory(id: String) throws -> Memory {
        try instance().getMemory(id: id)
    }

    func listMemories(kind: MemoryKind?) throws -> [Memory] {
        try instance().listMemories(kind: kind)
    }

    func completeReminder(id: String, now: Int64) throws -> Memory {
        try instance().completeReminder(id: id, now: now)
    }

    func deleteMemory(id: String, now: Int64) throws {
        try instance().deleteMemory(id: id, now: now)
    }

    func catStatus() throws -> CatStatus {
        try instance().catStatus()
    }

    func search(queryText: String) throws -> [Memory] {
        try instance().search(queryText: queryText)
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
