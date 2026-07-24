import SwiftUI

enum AppTab: Hashable {
    case cat
    case memories
    case profile
}

enum MemoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case reminder = "提醒"
    case card = "卡片"
    case note = "笔记"

    var id: Self { self }

    var kind: MemoryKind? {
        switch self {
        case .all:
            nil
        case .reminder:
            .reminder
        case .card:
            .card
        case .note:
            .note
        }
    }
}

extension Memory: Identifiable {}

extension MemoryKind {
    var title: String {
        switch self {
        case .reminder:
            "提醒"
        case .card:
            "卡片"
        case .note:
            "笔记"
        }
    }

    var systemImage: String {
        switch self {
        case .reminder:
            "bell.fill"
        case .card:
            "rectangle.stack.fill"
        case .note:
            "note.text"
        }
    }
}
