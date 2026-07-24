import SwiftUI

struct MemoriesView: View {
    let memories: [Memory]
    @Binding var filter: MemoryFilter
    let now: Int64
    let onComplete: (Memory) -> Void
    let onDelete: (Memory) -> Void
    let onEmptyCapture: () -> Void

    private var filteredMemories: [Memory] {
        guard let kind = filter.kind else { return memories }
        return memories.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("记忆类型", selection: $filter) {
                    ForEach(MemoryFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if filteredMemories.isEmpty {
                    EmptyMemoryView(onCapture: onEmptyCapture)
                } else {
                    memoryList
                }
            }
            .background(Theme.background)
            .navigationTitle("记忆")
        }
    }

    private var memoryList: some View {
        List(filteredMemories) { memory in
            MemoryRow(memory: memory, now: now)
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.background)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onDelete(memory)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(Theme.overdue)

                    if memory.kind == .reminder, memory.completedAt == nil {
                        Button {
                            onComplete(memory)
                        } label: {
                            Label("完成", systemImage: "checkmark")
                        }
                        .tint(Theme.completed)
                    }
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

private struct MemoryRow: View {
    let memory: Memory
    let now: Int64

    private var isOverdue: Bool {
        guard memory.kind == .reminder, memory.completedAt == nil, let dueAt = memory.dueAt else {
            return false
        }
        return dueAt < now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(memory.title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: memory.kind.systemImage)
                Text(memory.kind.title)
                Text("·")

                if memory.kind == .reminder, let dueAt = memory.dueAt {
                    if memory.completedAt != nil {
                        Text("已完成")
                            .foregroundStyle(Theme.completed)
                    } else {
                        Text("\(isOverdue ? "已到期" : "到期") \(Self.dueText(dueAt))")
                            .foregroundStyle(isOverdue ? Theme.overdue : Theme.secondaryText)
                    }
                } else {
                    Text(Self.relativeText(from: memory.createdAt, to: now))
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: Theme.borderWidth)
        }
        .accessibilityElement(children: .combine)
    }

    private static func relativeText(from timestamp: Int64, to now: Int64) -> String {
        let elapsed = max(0, now - timestamp)
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3_600 {
            return "\(elapsed / 60)分钟前"
        }
        if elapsed < 86_400 {
            return "\(elapsed / 3_600)小时前"
        }
        return "\(elapsed / 86_400)天前"
    }

    private static func dueText(_ timestamp: Int64) -> String {
        dueFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

private struct EmptyMemoryView: View {
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "cat.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            Text("还没有记忆")
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryText)

            Button("去记一下?", action: onCapture)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Theme.background)
    }
}
