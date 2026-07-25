import Combine
import SwiftUI

@MainActor
final class ReviewSessionModel: ObservableObject, Identifiable {
    let id = UUID()

    @Published private(set) var cards: [Memory]
    @Published private(set) var currentIndex: Int
    @Published private(set) var isAnswerRevealed: Bool
    @Published private(set) var reviewedCount: Int
    @Published private(set) var earnedFishCount: Int
    @Published private(set) var isComplete: Bool
    @Published private(set) var isLoading: Bool
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    private let client: ReviewServing
    private let currentTimestamp: () -> Int64
    private var hasLoaded: Bool

    init(
        client: ReviewServing,
        currentTimestamp: @escaping () -> Int64,
        previewCards: [Memory]? = nil,
        previewCurrentIndex: Int = 0,
        previewIsAnswerRevealed: Bool = false,
        previewReviewedCount: Int = 0,
        previewEarnedFishCount: Int = 0,
        previewIsComplete: Bool = false
    ) {
        self.client = client
        self.currentTimestamp = currentTimestamp
        cards = previewCards ?? []
        currentIndex = previewCurrentIndex
        isAnswerRevealed = previewIsAnswerRevealed
        reviewedCount = previewReviewedCount
        earnedFishCount = previewEarnedFishCount
        isComplete = previewIsComplete
        hasLoaded = previewCards != nil
        isLoading = previewCards == nil
    }

    var currentCard: Memory? {
        guard cards.indices.contains(currentIndex) else { return nil }
        return cards[currentIndex]
    }

    var totalCount: Int {
        cards.count
    }

    var currentPosition: Int {
        guard !cards.isEmpty else { return 0 }
        return min(currentIndex + 1, cards.count)
    }

    var catReaction: String {
        if earnedFishCount == 0 {
            return "猫蹭蹭你：忘了也没关系，下次再来。"
        }
        if earnedFishCount == reviewedCount {
            return "猫满意地眯起眼，把小鱼干收好了。"
        }
        return "猫甩甩尾巴：今天也记住了不少。"
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        errorMessage = nil

        do {
            let now = currentTimestamp()
            let count = try await client.dueCardCount(now: now)
            cards = try await client.dueCards(limit: count, now: now)
            currentIndex = 0
            isAnswerRevealed = false
            isComplete = cards.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func retryLoad() async {
        hasLoaded = false
        await load()
    }

    func revealAnswer() {
        guard currentCard != nil, !isSubmitting else { return }
        isAnswerRevealed = true
    }

    func submit(rating: ReviewRating) async {
        guard isAnswerRevealed, let card = currentCard, !isSubmitting else {
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let outcome = try await client.reviewCard(
                id: card.id,
                rating: rating,
                now: currentTimestamp()
            )
            reviewedCount += 1
            if outcome.earnedFish {
                earnedFishCount += 1
            }

            currentIndex += 1
            isAnswerRevealed = false
            isComplete = currentIndex >= cards.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ReviewSessionModel

    let onReturnHome: () -> Void

    init(
        model: ReviewSessionModel,
        onReturnHome: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.onReturnHome = onReturnHome
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    loadingContent
                } else if model.isComplete {
                    summaryContent
                } else if let card = model.currentCard {
                    reviewContent(card)
                } else {
                    loadFailureContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("review-close-button")
                }
            }
        }
        .task {
            await model.load()
        }
        .interactiveDismissDisabled(model.isSubmitting)
    }

    private var loadingContent: some View {
        ProgressView("正在叼来卡片…")
            .tint(Theme.accent)
            .foregroundStyle(Theme.secondaryText)
    }

    private func reviewContent(_ card: Memory) -> some View {
        VStack(spacing: 0) {
            Text("第 \(model.currentPosition) / \(model.totalCount) 张")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
                .accessibilityIdentifier("review-progress")

            ScrollView {
                VStack(spacing: 28) {
                    Text(card.question ?? "")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("review-question")

                    if model.isAnswerRevealed {
                        Text(card.answer ?? "")
                            .font(.title3)
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .accessibilityIdentifier("review-answer")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 32)
            }

            if !model.isAnswerRevealed {
                Button {
                    model.revealAnswer()
                } label: {
                    Text("想想…")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(Theme.accent)
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .accessibilityIdentifier("review-reveal-button")
            } else {
                ratingButtons
            }
        }
    }

    private var ratingButtons: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                ratingButton(
                    title: "不记得",
                    rating: .again,
                    style: .outlined
                )
                ratingButton(
                    title: "记得",
                    rating: .good,
                    style: .primary
                )
                ratingButton(
                    title: "太简单",
                    rating: .easy,
                    style: .secondary
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func ratingButton(
        title: String,
        rating: ReviewRating,
        style: ReviewButtonStyle
    ) -> some View {
        Button {
            Task { @MainActor in
                await model.submit(rating: rating)
            }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(style.foreground)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(style.border, lineWidth: Theme.borderWidth)
        }
        .disabled(model.isSubmitting)
        .opacity(model.isSubmitting ? 0.55 : 1)
        .accessibilityIdentifier("review-rating-\(style.identifier)")
    }

    private var summaryContent: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("复习完成")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.primaryText)

            VStack(spacing: 8) {
                Text("复习了 \(model.reviewedCount) 张")
                Text("喂了猫 \(model.earnedFishCount) 条小鱼干")
            }
            .font(.title3)
            .foregroundStyle(Theme.primaryText)

            Text(model.catReaction)
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()

            Button {
                onReturnHome()
                dismiss()
            } label: {
                Text("回猫窝")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .accessibilityIdentifier("review-return-home-button")
        }
        .accessibilityIdentifier("review-summary")
    }

    private var loadFailureContent: some View {
        VStack(spacing: 16) {
            Text("卡片没叼过来")
                .font(.title2.bold())
                .foregroundStyle(Theme.primaryText)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button("再试一次") {
                Task { @MainActor in
                    await model.retryLoad()
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(24)
    }
}

private enum ReviewButtonStyle {
    case outlined
    case primary
    case secondary

    var foreground: Color {
        switch self {
        case .outlined:
            Theme.accent
        case .primary:
            Color.white
        case .secondary:
            Theme.primaryText
        }
    }

    var background: Color {
        switch self {
        case .outlined, .secondary:
            Theme.surface
        case .primary:
            Theme.accent
        }
    }

    var border: Color {
        switch self {
        case .outlined:
            Theme.accent
        case .primary:
            Theme.accent
        case .secondary:
            Theme.border
        }
    }

    var identifier: String {
        switch self {
        case .outlined:
            "again"
        case .primary:
            "good"
        case .secondary:
            "easy"
        }
    }
}
