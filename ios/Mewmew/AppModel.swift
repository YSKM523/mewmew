import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject, NotificationSchedulerDelegate {
    @Published var selectedTab: AppTab = .cat
    @Published private(set) var memoryFilter: MemoryFilter = .all
    @Published var memories: [Memory] = []
    @Published var catStatus = CatStatus(
        level: 1,
        xp: 0,
        fish: 0,
        mood: "content",
        outfit: "none"
    )
    @Published private(set) var unlockedOutfits: Set<String> = ["none"]
    @Published private(set) var isFeedingCat = false
    @Published private(set) var showsLevelUp = false
    @Published private(set) var feedAnimationEvent = 0
    @Published private(set) var levelUpAnimationEvent = 0
    @Published var isCapturePresented = false
    @Published var showsConfirmation = false
    @Published var toastMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var searchText = ""
    @Published private(set) var recallPresentation: RecallPresentation?
    @Published private(set) var isRecalling = false
    @Published var focusedMemoryID: String?
    @Published private(set) var scheduledReminderCount = 0
    @Published private(set) var dueCardCount = 0
    @Published private(set) var notificationPermission =
        NotificationPermissionStatus.notDetermined
    @Published var reviewSession: ReviewSessionModel?

    private static let notificationPromptedKey =
        "hasRequestedReminderNotificationAuthorization"

    private let client: CoreClientProtocol
    private let parseClient: ParseServing
    private let recallClient: RecallServing
    private let notificationScheduler: NotificationScheduling
    private let promptDefaults: UserDefaults
    private let currentTimestamp: () -> Int64
    private let currentDate: () -> Date
    private var hasStarted = false
    private var allMemories: [Memory] = []
    private var searchResults: [Memory] = []
    private var searchTask: Task<Void, Never>?
    private var recallTask: Task<Void, Never>?

    init(
        client: CoreClientProtocol = CoreClient.shared,
        parseClient: ParseServing = ParseClient.shared,
        recallClient: RecallServing = RecallClient.shared,
        notificationScheduler: NotificationScheduling? = nil,
        promptDefaults: UserDefaults = .standard,
        currentTimestamp: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970)
        },
        currentDate: @escaping () -> Date = {
            Date()
        }
    ) {
        self.client = client
        self.parseClient = parseClient
        self.recallClient = recallClient
        self.promptDefaults = promptDefaults
        self.currentTimestamp = currentTimestamp
        self.currentDate = currentDate

        let scheduler = notificationScheduler ?? NotificationScheduler(
            client: client,
            currentTimestamp: currentTimestamp
        )
        self.notificationScheduler = scheduler

        scheduler.delegate = self
        scheduler.registerCategories()
    }

    var displayedMemories: [Memory] {
        let source: [Memory]
        if let recallPresentation {
            source = recallPresentation.listedMemories
        } else if searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            source = memories
        } else {
            source = searchResults
        }

        guard let kind = memoryFilter.kind else { return source }
        return source.filter { $0.kind == kind }
    }

    var dueReminderCount: Int {
        let now = currentTimestamp()
        return allMemories.filter {
            $0.kind == .reminder
                && $0.completedAt == nil
                && ($0.dueAt ?? Int64.max) <= now
        }.count
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await refresh()
        await syncNotifications()
    }

    func didBecomeActive() async {
        await refresh()
        await syncNotifications()
    }

    func refresh() async {
        do {
            allMemories = try await client.listMemories(kind: nil)
            if let kind = memoryFilter.kind {
                memories = try await client.listMemories(kind: kind)
            } else {
                memories = allMemories
            }
            catStatus = try await client.catStatusAt(now: currentTimestamp())
            unlockedOutfits = Set(try await client.unlockedOutfits())
            dueCardCount = Int(
                try await client.dueCardCount(now: currentTimestamp())
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCapture() {
        isCapturePresented = true
    }

    func openReviewSession() {
        guard dueCardCount > 0, reviewSession == nil else { return }
        reviewSession = ReviewSessionModel(
            client: client,
            currentTimestamp: currentTimestamp
        )
    }

    func feedCat() async {
        guard !isFeedingCat else { return }
        guard catStatus.fish > 0 else {
            errorMessage = "没有小鱼干了,完成提醒或复习就能得到"
            return
        }

        let previousLevel = catStatus.level
        isFeedingCat = true
        defer { isFeedingCat = false }

        do {
            let now = currentTimestamp()
            catStatus = try await client.feedCat(now: now)
            feedAnimationEvent += 1
            catStatus = try await client.catStatusAt(now: now)
            unlockedOutfits = Set(try await client.unlockedOutfits())

            if catStatus.level > previousLevel {
                levelUpAnimationEvent += 1
                showLevelUpFeedback()
            }

            try? await Task.sleep(nanoseconds: 450_000_000)
        } catch {
            errorMessage = friendlyCatErrorMessage(for: error)
        }
    }

    func setOutfit(_ outfit: String) async {
        do {
            let now = currentTimestamp()
            catStatus = try await client.setOutfit(outfit: outfit, now: now)
            catStatus = try await client.catStatusAt(now: now)
            unlockedOutfits = Set(try await client.unlockedOutfits())
        } catch {
            errorMessage = friendlyCatErrorMessage(for: error)
        }
    }

    func showLockedOutfitMessage(requiredLevel: Int64) {
        errorMessage = "长到 Lv.\(requiredLevel) 就能穿上啦"
    }

    func reviewSessionDidDismiss() async {
        await refresh()
        await syncNotifications()
    }

    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    func selectToday(_ filter: MemoryFilter) {
        selectedTab = .memories
        setMemoryFilter(filter)
    }

    func setMemoryFilter(_ filter: MemoryFilter) {
        memoryFilter = filter
        guard searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return
        }

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

    func setSearchText(_ text: String) {
        searchText = text
        searchTask?.cancel()
        recallTask?.cancel()
        recallPresentation = nil
        isRecalling = false
        focusedMemoryID = nil
        searchResults = []

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        memoryFilter = .all

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let results = try await client.searchForRecall(
                    query: query,
                    limit: 56
                )
                guard !Task.isCancelled, searchText == text else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled, searchText == text else { return }
                searchResults = []
            }
        }
    }

    func submitRecall() {
        let question = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !question.isEmpty else { return }

        searchTask?.cancel()
        recallTask?.cancel()
        recallPresentation = nil
        isRecalling = true

        recallTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let localMatches: [Memory]
            do {
                localMatches = try await client.searchForRecall(
                    query: question,
                    limit: 8
                )
            } catch {
                localMatches = []
            }

            guard !Task.isCancelled,
                searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == question
            else {
                return
            }
            searchResults = localMatches

            let result = await recallClient.recall(
                question: question,
                memories: localMatches
            )

            guard !Task.isCancelled,
                searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == question
            else {
                return
            }

            if let result,
                !result.answer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                var memoryByID = Dictionary(
                    uniqueKeysWithValues: localMatches.map { ($0.id, $0) }
                )
                var citedMemories: [Memory] = []
                for id in result.citedIDs {
                    if let memory = memoryByID.removeValue(forKey: id) {
                        citedMemories.append(memory)
                    }
                }
                // Declining to cite is the honest answer to a question we
                // never recorded, but it should not blank the list: show what
                // the search did turn up so the user can judge for themselves.
                let hasCitations = !citedMemories.isEmpty
                recallPresentation = RecallPresentation(
                    message: result.answer,
                    listedMemories: hasCitations ? citedMemories : localMatches,
                    isFallback: false,
                    showsCitations: hasCitations
                )
            } else {
                recallPresentation = RecallPresentation(
                    message: "猫有点困,先看看这些记忆吧",
                    listedMemories: localMatches,
                    isFallback: true,
                    showsCitations: false
                )
            }
            isRecalling = false
        }
    }

    func captureNote(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            let memory = NewMemory(
                kind: .note,
                rawText: trimmed,
                title: String(trimmed.prefix(20)),
                dueAt: nil,
                question: nil,
                answer: nil
            )
            let saved = try await client.addMemory(
                memory: memory,
                now: currentTimestamp()
            )
            upsertInMemory(saved)
            await syncNotifications()
            showsConfirmation = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.showsConfirmation = false
            }
            Task { @MainActor [weak self] in
                await self?.parseAndReclassify(saved, text: trimmed)
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
                showCompletionToast()
                await refresh()
                await syncNotifications()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func snooze(_ memory: Memory) {
        Task { @MainActor in
            let now = currentTimestamp()
            do {
                _ = try await client.snoozeReminder(
                    id: memory.id,
                    newDueAt: now + 1_800,
                    now: now
                )
                await refresh()
                await syncNotifications()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ memory: Memory) {
        Task { @MainActor in
            do {
                try await client.deleteMemory(
                    id: memory.id,
                    now: currentTimestamp()
                )
                await refresh()
                await syncNotifications()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func notificationSchedulerDidChangeMemories(completed: Bool) async {
        scheduledReminderCount = notificationScheduler.scheduledCount
        notificationPermission = notificationScheduler.permissionStatus
        await refresh()
        if completed {
            showCompletionToast()
        }
    }

    func notificationSchedulerDidSelectMemory(id: String) async {
        setSearchText("")
        selectedTab = .memories
        memoryFilter = .all
        await refresh()
        focusedMemoryID = id
    }

    private func parseAndReclassify(_ memory: Memory, text: String) async {
        guard let result = await parseClient.parse(
            text: text,
            timeZone: .current,
            now: currentDate()
        ) else {
            return
        }

        do {
            let reclassified = try await client.reclassifyMemory(
                id: memory.id,
                kind: result.kind.memoryKind,
                title: result.title,
                dueAt: result.dueAt,
                question: result.question,
                answer: result.answer,
                now: currentTimestamp()
            )
            upsertInMemory(reclassified)
            if reclassified.kind == .reminder {
                await requestNotificationAuthorizationIfNeeded()
            }
            dueCardCount = Int(
                try await client.dueCardCount(now: currentTimestamp())
            )
            await syncNotifications()
        } catch {
            // Capture has already succeeded locally. Background upgrades are
            // deliberately best-effort and never surface errors to the user.
        }
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        guard !promptDefaults.bool(
            forKey: Self.notificationPromptedKey
        ) else {
            return
        }

        promptDefaults.set(true, forKey: Self.notificationPromptedKey)
        await notificationScheduler.requestAuthorization()
    }

    private func syncNotifications() async {
        let state = await notificationScheduler.sync()
        scheduledReminderCount = state.scheduledCount
        notificationPermission = state.permissionStatus
    }

    private func showCompletionToast() {
        toastMessage = "+1 小鱼干 🐟"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.toastMessage = nil
        }
    }

    private func showLevelUpFeedback() {
        showsLevelUp = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            self?.showsLevelUp = false
        }
    }

    private func friendlyCatErrorMessage(for error: Error) -> String {
        if let coreError = error as? CoreError {
            switch coreError {
            case let .Invalid(message):
                if message == "没有小鱼干了" {
                    return "没有小鱼干了,完成提醒或复习就能得到"
                }
                return message
            case .Db(_), .NotFound:
                break
            }
        }
        return "猫现在有点忙,稍后再试试"
    }

    private func upsertInMemory(_ memory: Memory) {
        allMemories.removeAll { $0.id == memory.id }
        allMemories.append(memory)
        allMemories.sort {
            if $0.updatedAt == $1.updatedAt {
                return $0.id > $1.id
            }
            return $0.updatedAt > $1.updatedAt
        }

        if memoryFilter.kind == nil || memoryFilter.kind == memory.kind {
            memories.removeAll { $0.id == memory.id }
            memories.append(memory)
            memories.sort {
                if $0.updatedAt == $1.updatedAt {
                    return $0.id > $1.id
                }
                return $0.updatedAt > $1.updatedAt
            }
        } else {
            memories.removeAll { $0.id == memory.id }
        }
    }
}
