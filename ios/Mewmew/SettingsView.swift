import SwiftUI

struct SettingsView: View {
    let appVersion: String
    let databasePath: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("App 版本", value: appVersion)
                }
                .listRowBackground(Theme.surface)

#if DEBUG
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("数据库路径")
                            .foregroundStyle(Theme.primaryText)
                        Text(databasePath)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }

                    Button("清空数据", role: .destructive) {}
                        .disabled(true)
                } header: {
                    Text("调试")
                } footer: {
                    Text("Phase 1 暂不执行清空操作。")
                }
                .listRowBackground(Theme.surface)
#endif
            }
            .font(.body)
            .foregroundStyle(Theme.primaryText)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("我")
        }
    }
}
