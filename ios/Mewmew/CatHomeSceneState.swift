import Foundation

struct CatHomeSceneState: Equatable {
    let fishCount: Int64

    var showsFishBowl: Bool {
        fishCount > 0
    }
}
