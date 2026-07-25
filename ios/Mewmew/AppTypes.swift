import SwiftUI

enum AppTab: Hashable {
    case cat
    case memories
    case profile
}

enum NotificationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized

    var title: String {
        switch self {
        case .notDetermined:
            "未询问"
        case .denied:
            "未授权"
        case .authorized:
            "已授权"
        }
    }
}

struct RecallPresentation: Equatable {
    let message: String
    /// What to list under the bubble. These are the cat's citations only when
    /// `showsCitations` is set — when it declines to answer there are none, and
    /// listing nothing would throw away the search the user just triggered.
    let listedMemories: [Memory]
    let isFallback: Bool
    let showsCitations: Bool

    var listHeading: String { showsCitations ? "引用的记忆" : "本地结果" }
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
