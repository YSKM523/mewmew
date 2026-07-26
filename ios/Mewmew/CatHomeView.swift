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
    let feedTrigger: Int
    let levelUpTrigger: Int
    let onCapture: () -> Void
    let onSelectToday: (MemoryFilter) -> Void
    let onReview: () -> Void
    let onFeed: () -> Void
    let onSelectOutfit: (String) -> Void
    let onLockedOutfit: (Int64) -> Void

    @State private var isOutfitPickerPresented = false
    @State private var levelBadgeScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    catStage
                        .frame(minHeight: max(430, proxy.size.height * 0.53))
                        .background(Theme.surface)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: Theme.stageCornerRadius
                            )
                        )

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
                    .padding(.top, 30)

                    todaySection
                        .padding(.top, 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
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
        .transaction { transaction in
            if !isCatAnimated {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var catStage: some View {
        VStack(spacing: 0) {
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
                        .background(Theme.background)
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

            CatScene(
                mood: status.mood,
                outfit: status.outfit,
                fishCount: status.fish,
                isAnimated: isCatAnimated,
                isFeeding: isFeeding,
                feedTrigger: feedTrigger,
                levelUpTrigger: levelUpTrigger
            )
            .frame(height: 232)
            .padding(.top, 4)
                .overlay(alignment: .topTrailing) {
                    if showsConfirmation {
                        Text("记住啦")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .stroke(Theme.border, lineWidth: Theme.borderWidth)
                            }
                            .offset(x: 4, y: 4)
                            .transition(
                                .scale(scale: 0.72, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                            .accessibilityIdentifier("capture-confirmation")
                    }
                }
                .animation(
                    isCatAnimated
                        ? .spring(response: 0.36, dampingFraction: 0.72)
                        : nil,
                    value: showsConfirmation
                )

            Text(moodMessage)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 8)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("🐟")
                    Text("×\(status.fish)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .animation(
                    isCatAnimated ? .easeOut(duration: 0.3) : nil,
                    value: status.fish
                )
                .accessibilityElement(children: .ignore)
                    .accessibilityLabel("小鱼干 \(status.fish) 条")

                Button("喂猫", action: onFeed)
                    .buttonStyle(
                        FeedButtonStyle(isAnimated: isCatAnimated)
                    )
                    .disabled(isFeeding)
                    .opacity(isFeeding ? 0.55 : 1)
                    .accessibilityIdentifier("feed-cat-button")
            }
            .padding(.top, 12)

            levelProgress
                .frame(maxWidth: 280)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
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
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.background)
                    .clipShape(Capsule())
                    .scaleEffect(levelBadgeScale)

                if showsLevelUp {
                    Text("长大啦")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
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
                isCatAnimated ? .easeOut(duration: 0.6) : nil,
                value: status.xp
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("等级进度")
            .accessibilityValue("\(progress.percentage)%")
        }
        .animation(
            isCatAnimated ? .easeOut(duration: 0.2) : nil,
            value: showsLevelUp
        )
        .onAppear {
            updateLevelBadge(for: showsLevelUp)
        }
        .onChange(of: showsLevelUp) { _, isShowing in
            updateLevelBadge(for: isShowing)
        }
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

    private func updateLevelBadge(for isShowing: Bool) {
        guard isShowing, isCatAnimated else {
            levelBadgeScale = 1
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
            levelBadgeScale = 1.25
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard showsLevelUp else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                levelBadgeScale = 1
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
            .padding(20)
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

private struct CatScene: View {
    let mood: String
    let outfit: String
    let fishCount: Int64
    let isAnimated: Bool
    let isFeeding: Bool
    let feedTrigger: Int
    let levelUpTrigger: Int

    @State private var isZzzFloating = false

    private var sceneState: CatHomeSceneState {
        CatHomeSceneState(fishCount: fishCount)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Theme.surfaceDeep)
                .frame(width: 272, height: 58)
                .offset(y: -2)
                .accessibilityHidden(true)

            CatPresentation(
                mood: mood,
                outfit: outfit,
                isAnimated: isAnimated,
                feedTrigger: feedTrigger,
                levelUpTrigger: levelUpTrigger
            )
            .frame(width: 224, height: 224)
            .scaleEffect(isFeeding ? 1.06 : 1)
            .offset(y: isFeeding ? -1 : -6)
            .animation(
                isAnimated
                    ? .spring(response: 0.3, dampingFraction: 0.68)
                    : nil,
                value: isFeeding
            )
            .accessibilityIdentifier("cat-view")

            if sceneState.showsFishBowl {
                FishBowl(fishCount: fishCount)
                    .frame(width: 58, height: 40)
                    .offset(x: 102, y: -2)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .accessibilityIdentifier("fish-bowl")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if mood == "sleepy" {
                Text("Zzz")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .offset(x: -34, y: isZzzFloating ? -5 : 2)
                    .accessibilityIdentifier("sleepy-zzz")
            }
        }
        .animation(
            isAnimated ? .easeOut(duration: 0.22) : nil,
            value: sceneState.showsFishBowl
        )
        .onAppear {
            updateZzzAnimation()
        }
        .onChange(of: isAnimated) { _, _ in
            updateZzzAnimation()
        }
        .onChange(of: mood) { _, _ in
            updateZzzAnimation()
        }
    }

    private func updateZzzAnimation() {
        guard isAnimated, mood == "sleepy" else {
            isZzzFloating = false
            return
        }
        withAnimation(
            .easeInOut(duration: 1.25).repeatForever(autoreverses: true)
        ) {
            isZzzFloating = true
        }
    }
}

private struct FishBowl: View {
    let fishCount: Int64

    private var visibleFishCount: Int {
        Int(min(max(fishCount, 1), 3))
    }

    var body: some View {
        ZStack(alignment: .top) {
            BowlBodyShape()
                .fill(Theme.accent)
                .frame(width: 52, height: 27)
                .offset(y: 8)

            Ellipse()
                .fill(Theme.surfaceDeep)
                .frame(width: 52, height: 13)
                .overlay {
                    Ellipse()
                        .stroke(Theme.accent, lineWidth: 2)
                }

            HStack(spacing: 1) {
                ForEach(0..<visibleFishCount, id: \.self) { _ in
                    Image(systemName: "fish.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .offset(y: 2)
        }
        .accessibilityHidden(true)
    }
}

private struct BowlBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct FeedButtonStyle: ButtonStyle {
    let isAnimated: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.accent)
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                isAnimated ? .easeOut(duration: 0.12) : nil,
                value: configuration.isPressed
            )
    }
}
