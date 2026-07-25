import Combine
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Mewmew

@MainActor
final class MewmewSnapshotTests: XCTestCase {
    func testCatHomeHappy() {
        assertLightAndDark(
            CatHomeView(
                status: CatStatus(
                    level: 2,
                    xp: 46,
                    fish: 3,
                    mood: "happy",
                    outfit: "none"
                ),
                dueReminderCount: 1,
                dueCardCount: 1,
                showsConfirmation: false,
                unlockedOutfits: ["none", "scarf"],
                isCatAnimated: false,
                isFeeding: false,
                showsLevelUp: false,
                onCapture: {},
                onSelectToday: { _ in },
                onReview: {},
                onFeed: {},
                onSelectOutfit: { _ in },
                onLockedOutfit: { _ in }
            ),
            named: "cat-home-happy"
        )
    }

    func testCatHomeContent() {
        assertLightAndDark(
            makeCatHome(
                status: CatStatus(
                    level: 1,
                    xp: 29,
                    fish: 0,
                    mood: "content",
                    outfit: "none"
                )
            ),
            named: "cat-home-content"
        )
    }

    func testCatHomeSleepy() {
        assertLightAndDark(
            makeCatHome(
                status: CatStatus(
                    level: 4,
                    xp: 220,
                    fish: 2,
                    mood: "sleepy",
                    outfit: "none"
                )
            ),
            named: "cat-home-sleepy"
        )
    }

    func testCatHomeWithScarf() {
        assertLightAndDark(
            makeCatHome(
                status: CatStatus(
                    level: 2,
                    xp: 56,
                    fish: 1,
                    mood: "happy",
                    outfit: "scarf"
                )
            ),
            named: "cat-home-scarf"
        )
    }

    func testOutfitPickerShowsLockedOutfit() {
        assertLightAndDark(
            OutfitPickerSheet(
                selectedOutfit: "scarf",
                unlockedOutfits: ["none", "scarf"],
                onSelect: { _ in },
                onLockedTap: { _ in }
            ),
            named: "outfit-picker"
        )
    }

    func testMemoriesWithEveryKind() {
        assertLightAndDark(
            MemoriesView(
                memories: TestFixtures.memories,
                filter: .constant(.all),
                searchText: .constant(""),
                recallPresentation: nil,
                isRecalling: false,
                focusedMemoryID: nil,
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onSubmitRecall: {},
                onEmptyCapture: {}
            ),
            named: "memories-seeded"
        )
    }

    func testMemoriesEmptyState() {
        assertLightAndDark(
            MemoriesView(
                memories: [],
                filter: .constant(.all),
                searchText: .constant(""),
                recallPresentation: nil,
                isRecalling: false,
                focusedMemoryID: nil,
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onSubmitRecall: {},
                onEmptyCapture: {}
            ),
            named: "memories-empty"
        )
    }

    func testRecallResult() {
        assertLightAndDark(
            MemoriesView(
                memories: [TestFixtures.passportMemory],
                filter: .constant(.all),
                searchText: .constant("护照放哪了？"),
                recallPresentation: RecallPresentation(
                    message: "你把护照放在书房第二个抽屉里了",
                    listedMemories: [TestFixtures.passportMemory],
                    isFallback: false,
                    showsCitations: true
                ),
                isRecalling: false,
                focusedMemoryID: nil,
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onSubmitRecall: {},
                onEmptyCapture: {}
            ),
            named: "recall-result"
        )
    }

    /// The cat declining to answer must not blank the list — the search still
    /// found things and the user should be able to judge them.
    func testRecallWithoutCitations() {
        assertLightAndDark(
            MemoriesView(
                memories: [TestFixtures.passportMemory],
                filter: .constant(.all),
                searchText: .constant("我的飞机票订了吗？"),
                recallPresentation: RecallPresentation(
                    message: "我没记过这个",
                    listedMemories: [TestFixtures.passportMemory],
                    isFallback: false,
                    showsCitations: false
                ),
                isRecalling: false,
                focusedMemoryID: nil,
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onSubmitRecall: {},
                onEmptyCapture: {}
            ),
            named: "recall-uncited"
        )
    }

    func testRecallFallback() {
        assertLightAndDark(
            MemoriesView(
                memories: [TestFixtures.passportMemory],
                filter: .constant(.all),
                searchText: .constant("护照放哪了？"),
                recallPresentation: RecallPresentation(
                    message: "猫有点困,先看看这些记忆吧",
                    listedMemories: [TestFixtures.passportMemory],
                    isFallback: true,
                    showsCitations: false
                ),
                isRecalling: false,
                focusedMemoryID: nil,
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onSubmitRecall: {},
                onEmptyCapture: {}
            ),
            named: "recall-fallback"
        )
    }

    func testSettingsPhase3Observability() {
        assertLightAndDark(
            SettingsView(
                appVersion: "1.0 (1)",
                databasePath: "/Application Support/mewmew.sqlite3",
                scheduledReminderCount: 56,
                notificationPermission: .denied,
                // Pinned: the real value depends on whether the build carried a
                // token, which would make this snapshot flap.
                isClassifierConfigured: true,
                onOpenNotificationSettings: {}
            ),
            named: "settings"
        )
    }

    func testCaptureSheetIdle() {
        assertLightAndDark(
            CaptureSheet(
                speechCapture: FakeSpeechCapture(),
                onSave: { _ in true }
            ),
            named: "capture-idle"
        )
    }

    func testCaptureSheetRecordingWithPartialTranscript() {
        assertLightAndDark(
            CaptureSheet(
                speechCapture: FakeSpeechCapture(
                    transcript: "下周三下午三点提醒我交电费",
                    isRecording: true
                ),
                onSave: { _ in true }
            ),
            named: "capture-recording"
        )
    }

    func testReviewSessionQuestion() {
        assertLightAndDark(
            ReviewSessionView(
                model: ReviewSessionModel(
                    client: SnapshotReviewClient(),
                    currentTimestamp: { TestFixtures.now },
                    previewCards: [TestFixtures.reviewCard],
                    previewCurrentIndex: 0,
                    previewIsAnswerRevealed: false,
                    previewReviewedCount: 0,
                    previewEarnedFishCount: 0,
                    previewIsComplete: false
                ),
                onReturnHome: {}
            ),
            named: "review-question"
        )
    }

    func testReviewSessionAnswer() {
        assertLightAndDark(
            ReviewSessionView(
                model: ReviewSessionModel(
                    client: SnapshotReviewClient(),
                    currentTimestamp: { TestFixtures.now },
                    previewCards: [TestFixtures.reviewCard],
                    previewCurrentIndex: 0,
                    previewIsAnswerRevealed: true,
                    previewReviewedCount: 0,
                    previewEarnedFishCount: 0,
                    previewIsComplete: false
                ),
                onReturnHome: {}
            ),
            named: "review-answer"
        )
    }

    func testReviewSessionSummary() {
        assertLightAndDark(
            ReviewSessionView(
                model: ReviewSessionModel(
                    client: SnapshotReviewClient(),
                    currentTimestamp: { TestFixtures.now },
                    previewCards: [TestFixtures.reviewCard],
                    previewCurrentIndex: 1,
                    previewIsAnswerRevealed: false,
                    previewReviewedCount: 1,
                    previewEarnedFishCount: 1,
                    previewIsComplete: true
                ),
                onReturnHome: {}
            ),
            named: "review-summary"
        )
    }

    private func assertLightAndDark<V: View>(
        _ makeView: @autoclosure () -> V,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

        for scheme in [ColorScheme.light, .dark] {
            let themedView = AnyView(
                makeView()
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            )
            let controller = UIHostingController(rootView: themedView)
            controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light

            assertSnapshot(
                of: controller,
                as: .image(on: .iPhone13),
                named: "\(name)-\(scheme == .dark ? "dark" : "light")",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    private func makeCatHome(status: CatStatus) -> CatHomeView {
        CatHomeView(
            status: status,
            dueReminderCount: 1,
            dueCardCount: 1,
            showsConfirmation: false,
            unlockedOutfits: ["none", "scarf"],
            isCatAnimated: false,
            isFeeding: false,
            showsLevelUp: false,
            onCapture: {},
            onSelectToday: { _ in },
            onReview: {},
            onFeed: {},
            onSelectOutfit: { _ in },
            onLockedOutfit: { _ in }
        )
    }
}

@MainActor
private final class FakeSpeechCapture: SpeechCapturing {
    @Published private(set) var transcript: String
    @Published private(set) var isRecording: Bool
    @Published private(set) var errorMessage: String?

    init(
        transcript: String = "",
        isRecording: Bool = false,
        errorMessage: String? = nil
    ) {
        self.transcript = transcript
        self.isRecording = isRecording
        self.errorMessage = errorMessage
    }

    func requestPermissions() async -> Bool {
        true
    }

    func start() {}

    func stop() {
        isRecording = false
    }
}

private actor SnapshotReviewClient: ReviewServing {
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
        throw SnapshotReviewClientError.unexpectedCall
    }
}

private enum SnapshotReviewClientError: Error {
    case unexpectedCall
}
