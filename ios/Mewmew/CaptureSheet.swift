import SwiftUI

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var isSaving = false

    let onSave: (String) async -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TextField("想记住什么?", text: $text, axis: .vertical)
                    .font(.title2)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(4...10)
                    .focused($isFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)

                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("记一下")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isSaving = true
                    Task { @MainActor in
                        let saved = await onSave(trimmed)
                        isSaving = false
                        if saved {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("让猫记住")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .opacity(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
                        ? 0.55
                        : 1
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.background)
                .accessibilityIdentifier("capture-save-button")
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
