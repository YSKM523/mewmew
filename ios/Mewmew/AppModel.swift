import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .cat
    @Published private(set) var memoryFilter: MemoryFilter = .all
    @Published var memories: [Memory] = []
    @Published var catStatus = CatStatus(level: 1, xp: 0, fish: 0, mood: "content")
    @Published var isCapturePresented = false
    @Published var showsConfirmation = false
    @Published var toastMessage: String?
    @Published var errorMessage: String?

    private let client: CoreClient
    private let currentTimestamp: () -> Int64
    private var hasStarted = false
    private var allMemories: [Memory] = []

    init(
        client: CoreClient = .shared,
        currentTimestamp: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        }
    ) {
        self.client = client
        self.currentTimestamp = currentTimestamp
    }

    var dueReminderCount: Int {
        let now = currentTimestamp()
        return allMemories.filter {
            $0.kind == .reminder
                && $0.completedAt == nil
                && ($0.dueAt ?? Int64.max) <= now
        }.count
    }

    var dueCardCount: Int {
        allMemories.filter { $0.kind == .card }.count
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await refresh()
    }

    func refresh() async {
        do {
            allMemories = try await client.listMemories(kind: nil)
            if let kind = memoryFilter.kind {
                memories = try await client.listMemories(kind: kind)
            } else {
                memories = allMemories
            }
            catStatus = try await client.catStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCapture() {
        isCapturePresented = true
    }

    func selectToday(_ filter: MemoryFilter) {
        selectedTab = .memories
        setMemoryFilter(filter)
    }

    func setMemoryFilter(_ filter: MemoryFilter) {
        memoryFilter = filter
        Task { @MainActor in
            do {
                let filtered = try await client.listMemories(kind: filter.kind)
                guard memoryFilter == filter else { return }
                memories = filtered
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func captureNote(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            let memory = NewMemory(
                kind: .note,
                rawText: trimmed,
                title: trimmed,
                dueAt: nil,
                question: nil,
                answer: nil
            )
            _ = try await client.addMemory(memory: memory, now: currentTimestamp())
            await refresh()
            showsConfirmation = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.showsConfirmation = false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func complete(_ memory: Memory) {
        Task { @MainActor in
            do {
                _ = try await client.completeReminder(
                    id: memory.id,
                    now: currentTimestamp()
                )
                toastMessage = "+1 小鱼干 🐟"
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                toastMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ memory: Memory) {
        Task { @MainActor in
            do {
                try await client.deleteMemory(id: memory.id, now: currentTimestamp())
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
