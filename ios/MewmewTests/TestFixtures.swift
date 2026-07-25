import Foundation
@testable import Mewmew

enum TestFixtures {
    static let now: Int64 = 1_735_689_600

    static let memories: [Memory] = [
        Memory(
            id: "reminder-1",
            kind: .reminder,
            rawText: "下午三点交电费",
            title: "交电费",
            dueAt: now - 3_600,
            completedAt: nil,
            question: nil,
            answer: nil,
            createdAt: now - 7_200,
            updatedAt: now - 7_200
        ),
        Memory(
            id: "card-1",
            kind: .card,
            rawText: "Rust 所有权保证内存安全",
            title: "Rust 所有权",
            dueAt: nil,
            completedAt: nil,
            question: "Rust 的所有权解决什么问题？",
            answer: "在编译期保证内存安全。",
            createdAt: now - 14_400,
            updatedAt: now - 14_400
        ),
        Memory(
            id: "note-1",
            kind: .note,
            rawText: "周末去看新开的书店",
            title: "周末看书店",
            dueAt: nil,
            completedAt: nil,
            question: nil,
            answer: nil,
            createdAt: now - 86_400,
            updatedAt: now - 86_400
        ),
    ]

    static let passportMemory = Memory(
        id: "passport-1",
        kind: .note,
        rawText: "护照放在书房第二个抽屉里",
        title: "护照的位置",
        dueAt: nil,
        completedAt: nil,
        question: nil,
        answer: nil,
        createdAt: now - 1_800,
        updatedAt: now - 1_800
    )

    static let catStatus = CatStatus(level: 1, xp: 0, fish: 3, mood: "content")
}
