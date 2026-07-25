import SwiftUI

struct OutfitPickerSheet: View {
    let selectedOutfit: String
    let unlockedOutfits: Set<String>
    let onSelect: (String) -> Void
    let onLockedTap: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CatOutfitOption.all) { option in
                        outfitButton(option)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("给猫装扮")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    private func outfitButton(_ option: CatOutfitOption) -> some View {
        let isUnlocked = unlockedOutfits.contains(option.id)
        let isSelected = selectedOutfit == option.id

        return Button {
            if isUnlocked {
                onSelect(option.id)
                dismiss()
            } else {
                onLockedTap(option.requiredLevel)
            }
        } label: {
            HStack(spacing: 16) {
                CatView(
                    mood: "content",
                    outfit: option.id,
                    isAnimated: false
                )
                .scaleEffect(0.32)
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(option.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)

                    if isUnlocked {
                        Text(isSelected ? "正在穿" : "已解锁")
                            .font(.footnote)
                            .foregroundStyle(
                                isSelected
                                    ? Theme.accent
                                    : Theme.secondaryText
                            )
                    } else {
                        Text("Lv.\(option.requiredLevel) 解锁")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: Theme.borderWidth
                    )
            }
            .opacity(isUnlocked ? 1 : 0.48)
            .contentShape(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isUnlocked
                ? "\(option.name),\(isSelected ? "正在穿" : "已解锁")"
                : "\(option.name),Lv.\(option.requiredLevel) 解锁"
        )
        .accessibilityHint(
            Text(isUnlocked ? "选择装扮" : "尚未解锁")
        )
    }
}

private struct CatOutfitOption: Identifiable {
    let id: String
    let name: String
    let requiredLevel: Int64

    static let all = [
        CatOutfitOption(id: "none", name: "原样", requiredLevel: 1),
        CatOutfitOption(id: "bell", name: "小铃铛", requiredLevel: 2),
        CatOutfitOption(id: "glasses", name: "圆眼镜", requiredLevel: 4),
    ]
}
