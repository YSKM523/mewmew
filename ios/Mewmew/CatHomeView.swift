import SwiftUI

struct CatHomeView: View {
    let status: CatStatus
    let dueReminderCount: Int
    let dueCardCount: Int
    let showsConfirmation: Bool
    let unlockedOutfits: Set<String>
    let isCatAnimated: Bool
    let isFeeding: Bool
    let showsLevelUp: Bool
    let onCapture: () -> Void
    let onSelectToday: (MemoryFilter) -> Void
    let onReview: () -> Void
    let onFeed: () -> Void
    let onSelectOutfit: (String) -> Void
    let onLockedOutfit: (Int64) -> Void

    @State private var isOutfitPickerPresented = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    catStage
                        .frame(minHeight: max(340, proxy.size.height * 0.5))

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
        .sheet(isPresented: $isOutfitPickerPresented) {
            OutfitPickerSheet(
                selectedOutfit: status.outfit,
                unlockedOutfits: unlockedOutfits,
                onSelect: onSelectOutfit,
                onLockedTap: onLockedOutfit
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var catStage: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button {
                    isOutfitPickerPresented = true
                } label: {
                    Label("装扮", systemImage: "tshirt")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Theme.surface)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Theme.cornerRadius
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: Theme.cornerRadius
                            )
                            .stroke(
                                Theme.border,
                                lineWidth: Theme.borderWidth
                            )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("outfit-button")
            }

            CatView(
                mood: status.mood,
                outfit: status.outfit,
                isAnimated: isCatAnimated
            )
            .frame(width: 240, height: 240)
            .scaleEffect(isFeeding ? 1.06 : 1)
            .offset(y: isFeeding ? 5 : 0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.68),
                value: isFeeding
            )
            .accessibilityIdentifier("cat-view")
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

            Text(moodMessage)
                .font(.body)
                .foregroundStyle(Theme.primaryText)

            HStack(spacing: 12) {
                Text("🐟 ×\(status.fish)")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("小鱼干 \(status.fish) 条")

                if status.fish > 0 {
                    Button("喂猫", action: onFeed)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Theme.cornerRadius
                            )
                        )
                        .buttonStyle(.plain)
                        .disabled(isFeeding)
                        .opacity(isFeeding ? 0.55 : 1)
                        .accessibilityIdentifier("feed-cat-button")
                }
            }

            levelProgress
                .frame(maxWidth: 280)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var levelProgress: some View {
        let progress = CatLevelProgress(xp: status.xp)
        let nextThreshold = CatLevelProgress.threshold(
            for: progress.level + 1
        )

        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text("Lv.\(status.level)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .scaleEffect(showsLevelUp ? 1.18 : 1)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.58),
                        value: showsLevelUp
                    )

                if showsLevelUp {
                    Text("长大啦!")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                Text("\(status.xp) / \(nextThreshold) XP")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.border)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(progress.fraction)
                        )
                }
            }
            .frame(height: 3)
            .animation(
                .easeOut(duration: 0.45),
                value: status.xp
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("等级进度")
            .accessibilityValue(
                "\(Int((progress.fraction * 100).rounded()))%"
            )
        }
        .animation(.easeOut(duration: 0.2), value: showsLevelUp)
    }

    private var moodMessage: String {
        switch status.mood {
        case "happy":
            return "猫正精神地陪着你"
        case "sleepy":
            return "猫在窝里打盹"
        default:
            return "猫安静地待在你身边"
        }
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
        .accessibilityLabel("\(title),\(count)")
        .accessibilityHint(
            Text(isEnabled ? "打开" : "暂无可复习卡片")
        )
    }
}
