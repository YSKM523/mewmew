import SwiftUI

@main
@MainActor
struct MewmewApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView(model: model)
        }
    }
}
