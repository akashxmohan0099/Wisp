import AVFoundation
import Foundation
import Speech
import SwiftUI
import UIKit

@MainActor
final class DictationModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var mode: WispMode = .dictate
    @Published var transcript = ""
    @Published var finalText = ""
    @Published var status = "Choose Dictate or Compose."
    @Published var apiKey = UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func handleURL(_ url: URL) {
        guard url.scheme == "wisp" else {
            return
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let rawMode = components.queryItems?.first(where: { $0.name == "mode" })?.value,
           let requestedMode = WispMode(rawValue: rawMode) {
            Task {
                await start(requestedMode)
            }
        }
    }

    func handlePendingKeyboardRequest() {
        guard let pendingMode = SharedStore.consumePendingMode() else {
            return
        }

        Task {
            await start(pendingMode)
        }
    }

    func saveAPIKey() {
        UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "openAIAPIKey")
        status = "Compose key saved on this iPhone."
    }

    func start(_ selectedMode: WispMode) async {
        guard !isRecording && !isProcessing else {
            return
        }

        mode = selectedMode
        transcript = ""
        finalText = ""
        status = "\(selectedMode.title) is listening."

        do {
            try await requestPermissions()
            try configureRecognition()
            try startAudioEngine()
            isRecording = true
        } catch {
            stopAudioEngine()
            status = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else {
            return
        }

        isRecording = false
        isProcessing = true
        status = "Finishing \(mode.title.lowercased())..."
        stopAudioEngine()

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await finish()
        }
    }

    private func finish() async {
        recognitionTask?.cancel()
        recognitionTask = nil

        let cleaned = TranscriptCleaner.cleaned(transcript)
        guard !cleaned.isEmpty else {
            finalText = ""
            isProcessing = false
            status = "No speech was detected."
            return
        }

        switch mode {
        case .dictate:
            saveResult(cleaned)
        case .compose:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                saveResult(cleaned)
                status = "Compose needs an OpenAI key. Saved cleaned dictation instead."
                return
            }

            do {
                status = "Composing with AI..."
                let composed = try await OpenAIComposer(apiKey: key).compose(cleaned)
                saveResult(composed)
            } catch {
                saveResult(cleaned)
                status = "Compose failed. Saved cleaned dictation instead."
            }
        }
    }

    private func saveResult(_ text: String) {
        finalText = text
        SharedStore.saveLatestText(text)
        UIPasteboard.general.string = text
        isProcessing = false
        status = "\(mode.title) saved. Return to Wisp Keyboard and tap Insert."
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw DictationError.speechDenied
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            throw DictationError.microphoneDenied
        }
    }

    private func configureRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw DictationError.speechUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self.status = error.localizedDescription
                }
            }
        }
    }

    private func startAudioEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum DictationError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case speechUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone permission is needed to dictate."
        case .speechDenied: "Speech Recognition permission is needed to transcribe."
        case .speechUnavailable: "Speech Recognition is not available right now."
        }
    }
}
