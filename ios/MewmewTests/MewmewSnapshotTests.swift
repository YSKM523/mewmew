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
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
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
                now: TestFixtures.now,
                onComplete: { _ in },
                onDelete: { _ in },
                onEmptyCapture: {}
            ),
            named: "memories-empty"
        )
    }

    func testSettingsPlaceholder() {
        assertLightAndDark(
            SettingsView(
                appVersion: "1.0 (1)",
                databasePath: "/Application Support/mewmew.sqlite3",
                // Pinned: the real value depends on whether the build carried a
                // token, which would make this snapshot flap.
                isClassifierConfigured: true
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
