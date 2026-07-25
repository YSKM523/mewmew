import SwiftUI

@MainActor
struct RootTabView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            CatHomeView(
                status: model.catStatus,
                dueReminderCount: model.dueReminderCount,
                dueCardCount: model.dueCardCount,
                showsConfirmation: model.showsConfirmation,
                unlockedOutfits: model.unlockedOutfits,
                isCatAnimated: true,
                isFeeding: model.isFeedingCat,
                showsLevelUp: model.showsLevelUp,
                onCapture: model.openCapture,
                onSelectToday: model.selectToday,
                onReview: model.openReviewSession,
                onFeed: {
                    Task { @MainActor in
                        await model.feedCat()
                    }
                },
                onSelectOutfit: { outfit in
                    Task { @MainActor in
                        await model.setOutfit(outfit)
                    }
                },
                onLockedOutfit: model.showLockedOutfitMessage
            )
            .tabItem {
                Label("猫", systemImage: "cat.fill")
            }
            .tag(AppTab.cat)

            MemoriesView(
                memories: model.displayedMemories,
                filter: Binding(
                    get: { model.memoryFilter },
                    set: model.setMemoryFilter
                ),
                searchText: Binding(
                    get: { model.searchText },
                    set: model.setSearchText
                ),
                recallPresentation: model.recallPresentation,
                isRecalling: model.isRecalling,
                focusedMemoryID: model.focusedMemoryID,
                now: Int64(Date().timeIntervalSince1970),
                onComplete: model.complete,
                onDelete: model.delete,
                onSubmitRecall: model.submitRecall,
                onEmptyCapture: {
                    model.selectedTab = .cat
                    model.openCapture()
                }
            )
            .tabItem {
                Label("记忆", systemImage: "tray.full.fill")
            }
            .tag(AppTab.memories)

            SettingsView(
                appVersion: Self.appVersion,
                databasePath: CoreClient.defaultDatabasePath,
                scheduledReminderCount: model.scheduledReminderCount,
                notificationPermission: model.notificationPermission,
                onOpenNotificationSettings: model.openNotificationSettings
            )
            .tabItem {
                Label("我", systemImage: "person.fill")
            }
            .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .sheet(isPresented: $model.isCapturePresented) {
            CaptureSheet(
                speechCapture: SpeechCapture(),
                onSave: model.captureNote
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            item: $model.reviewSession,
            onDismiss: {
                Task { @MainActor in
                    await model.reviewSessionDidDismiss()
                }
            }
        ) { session in
            ReviewSessionView(
                model: session,
                onReturnHome: {
                    model.selectedTab = .cat
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let toast = model.toastMessage {
                Text(toast)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(Theme.border, lineWidth: Theme.borderWidth)
                    }
                    .padding(.top, 10)
                    .accessibilityIdentifier("completion-toast")
            }
        }
        .task {
            await model.start()
        }
        .alert(
            "出了点问题",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("好") {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private static var appVersion: String {
        let versionObject = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        )
        let buildObject = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        )
        let version = (versionObject as? String) ?? "1.0"
        let build = (buildObject as? String) ?? "1"
        return "\(version) (\(build))"
    }
}
