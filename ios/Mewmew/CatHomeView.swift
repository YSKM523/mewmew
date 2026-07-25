import SwiftUI

struct CatHomeView: View {
    let status: CatStatus
    let dueReminderCount: Int
    let dueCardCount: Int
    let showsConfirmation: Bool
    let onCapture: () -> Void
    let onSelectToday: (MemoryFilter) -> Void
    let onReview: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    catStage
                        .frame(minHeight: max(280, proxy.size.height * 0.45))

                    Button(action: onCapture) {
                        Text("记一下…")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .accessibilityIdentifier("capture-button")

                    todaySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
        }
    }

    private var catStage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 16)

            Image(systemName: "cat.fill")
                .font(.system(size: 132, weight: .regular))
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("猫")
                .overlay(alignment: .topTrailing) {
                    if showsConfirmation {
                        Text("记住啦!")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .stroke(Theme.border, lineWidth: Theme.borderWidth)
                            }
                            .offset(x: 42, y: -12)
                            .accessibilityIdentifier("capture-confirmation")
                    }
                }

            Text("小鱼干 ×\(status.fish) · Lv.\(status.level)")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天")
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryText)

            HStack(spacing: 12) {
                TodaySummaryCard(
                    title: "到期提醒",
                    count: dueReminderCount,
                    systemImage: "bell.fill",
                    action: { onSelectToday(.reminder) }
                )
                TodaySummaryCard(
                    title: "到期卡片",
                    count: dueCardCount,
                    systemImage: "rectangle.stack.fill",
                    isEnabled: dueCardCount > 0,
                    action: onReview
                )
            }
        }
    }
}

private struct TodaySummaryCard: View {
    let title: String
    let count: Int
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: systemImage)
                    Spacer()
                    Text("\(count)")
                        .font(.title2.bold())
                }
                .foregroundStyle(Theme.primaryText)

                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: Theme.borderWidth)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel("\(title)，\(count)")
        .accessibilityHint(
            Text(isEnabled ? "打开" : "暂无可复习卡片")
        )
    }
}
