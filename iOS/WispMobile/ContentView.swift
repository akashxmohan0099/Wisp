import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DictationModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                statusHeader
                modeButtons
                transcriptPanel
                resultPanel
                keyPanel
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Wisp")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    model.handlePendingKeyboardRequest()
                }
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isRecording ? "mic.circle.fill" : "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(model.isRecording ? .green : .primary)

            Text(model.status)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var modeButtons: some View {
        HStack(spacing: 12) {
            actionButton(title: "Dictate", icon: "textformat", mode: .dictate)
            actionButton(title: "Compose", icon: "sparkles", mode: .compose)
        }
    }

    private func actionButton(title: String, icon: String, mode: WispMode) -> some View {
        Button {
            if model.isRecording {
                model.stop()
            } else {
                Task {
                    await model.start(mode)
                }
            }
        } label: {
            Label(model.isRecording && model.mode == mode ? "Stop" : title, systemImage: model.isRecording && model.mode == mode ? "stop.fill" : icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(mode == .dictate ? .green : .purple)
        .disabled(model.isProcessing || (model.isRecording && model.mode != mode))
    }

    private var transcriptPanel: some View {
        panel(title: "Transcript", text: model.transcript.isEmpty ? "Your words will appear here while recording." : model.transcript)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panel(title: "Latest Insert Text", text: model.finalText.isEmpty ? SharedStore.latestText().isEmpty ? "The finished text will be saved here for the keyboard." : SharedStore.latestText() : model.finalText)

            Text("Return to the Wisp Keyboard and tap Insert Latest.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func panel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 150)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var keyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compose Key")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            SecureField("OpenAI API key", text: $model.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)

            Button("Save Key") {
                model.saveAPIKey()
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
