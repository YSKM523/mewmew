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
                databasePath: "/Application Support/mewmew.sqlite3"
            ),
            named: "settings"
        )
    }

    private func assertLightAndDark<V: View>(
        _ view: V,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

        for scheme in [ColorScheme.light, .dark] {
            let themedView = AnyView(
                view
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
