import SwiftUI

@MainActor
struct CaptureSheet<SpeechCaptureType: SpeechCapturing>: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @StateObject private var speechCapture: SpeechCaptureType
    @State private var text: String
    @State private var isSaving = false

    let onSave: (String) async -> Bool

    init(
        speechCapture: SpeechCaptureType,
        onSave: @escaping (String) async -> Bool
    ) {
        _speechCapture = StateObject(wrappedValue: speechCapture)
        _text = State(initialValue: speechCapture.transcript)
        self.onSave = onSave
    }

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

                if speechCapture.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 10, height: 10)
                        Text("正在听…")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityIdentifier("capture-recording-indicator")
                }

                if let errorMessage = speechCapture.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.overdue)
                        .accessibilityIdentifier("capture-speech-error")
                }

                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("记一下")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        speechCapture.stop()
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        if speechCapture.isRecording {
                            speechCapture.stop()
                            isFocused = true
                        } else {
                            isFocused = false
                            Task { @MainActor in
                                guard await speechCapture.requestPermissions() else {
                                    return
                                }
                                speechCapture.start()
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: speechCapture.isRecording
                                    ? "stop.fill"
                                    : "mic.fill"
                            )
                            Text(speechCapture.isRecording ? "结束录音" : "语音输入")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        speechCapture.isRecording ? Theme.accent : Color.white
                    )
                    .background(
                        speechCapture.isRecording ? Theme.surface : Theme.accent
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    )
                    .overlay {
                        if speechCapture.isRecording {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.accent, lineWidth: Theme.borderWidth)
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("capture-microphone-button")

                    Button {
                        let trimmed = text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !trimmed.isEmpty else { return }
                        speechCapture.stop()
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
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    )
                    .disabled(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSaving
                    )
                    .opacity(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSaving
                            ? 0.55
                            : 1
                    )
                    .accessibilityIdentifier("capture-save-button")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.background)
            }
        }
        .onChange(of: speechCapture.transcript) { _, transcript in
            text = transcript
        }
        .onAppear {
            if !speechCapture.isRecording {
                isFocused = true
            }
        }
        .onDisappear {
            speechCapture.stop()
        }
    }
}
