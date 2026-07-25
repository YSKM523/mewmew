import Combine
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Mewmew

@MainActor
final class MewmewSnapshotTests: XCTestCase {
    func testCatHome() {
        assertLightAndDark(
            CatHomeView(
                status: TestFixtures.catStatus,
                dueReminderCount: 1,
                dueCardCount: 1,
                showsConfirmation: false,
                onCapture: {},
                onSelectToday: { _ in }
            ),
            named: "cat-home"
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
                    message: "你把护照放在书房第二个抽屉里了。",
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
                    message: "我没记过这个。",
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
