import SwiftUI

@main
@MainActor
struct MewmewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { @MainActor in
                        await model.didBecomeActive()
                    }
                }
        }
    }
}
