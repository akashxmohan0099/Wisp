import AppKit
import Foundation

enum DictationMode: String {
    case dictate
    case compose

    var title: String {
        switch self {
        case .dictate:
            return "Dictate"
        case .compose:
            return "Compose"
        }
    }
}

@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusMessage = "Click the floating bubble to dictate or compose."
    @Published private(set) var autoPasteEnabled = true
    @Published private(set) var currentMode: DictationMode = .dictate

    var stateDidChange: (() -> Void)?

    private let recordingService = RecordingService()
    private let transcriptionService = TranscriptionService()
    private let refinementService = LLMRefinementService()
    private let clipboardService = ClipboardService()
    private let accessibilityService = AccessibilityService()

    private var lastFrontmostApp: NSRunningApplication?
    private var focusedTextElement: AccessibilityService.FocusedTextElement?

    func toggleAutoPaste() {
        setAutoPasteEnabled(!autoPasteEnabled)
    }

    func toggleDictation() async {
        DebugLogger.log("toggleDictation isRecording=\(isRecording)")
        if isRecording {
            await stopDictation()
        } else {
            await startDictation(mode: currentMode)
        }
    }

    func startDictation(mode: DictationMode) async {
        guard !isRecording && !isTranscribing else {
            await toggleDictation()
            return
        }

        await startRecording(mode: mode)
    }

    func stopCurrentDictation() async {
        guard isRecording else {
            return
        }

        await stopDictation()
    }

    func copyTranscriptToClipboard() {
        guard !transcript.isEmpty else {
            presentError("There is no transcript to copy yet.")
            return
        }

        clipboardService.copy(transcript)
        statusMessage = "Transcript copied to the clipboard."
        notifyStateChanged()
    }

    func pasteTranscriptIntoFrontmostApp() async {
        guard !transcript.isEmpty else {
            presentError("There is no transcript to paste yet.")
            return
        }

        let pasted = await pasteTranscript(transcript, promptForPermission: true)

        if pasted {
            statusMessage = "Transcript pasted into the frontmost app."
        } else {
            statusMessage = "Transcript copied to the clipboard. Grant Accessibility permission to auto-paste."
        }

        notifyStateChanged()
    }

    func presentError(_ message: String) {
        DebugLogger.log("error \(message)")
        statusMessage = message
        notifyStateChanged()
    }

    private func startRecording(mode: DictationMode) async {
        DebugLogger.log("startRecording begin mode=\(mode.rawValue)")
        currentMode = mode

        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastFrontmostApp = frontmostApp
            DebugLogger.log("captured frontmost bundle=\(frontmostApp.bundleIdentifier ?? "unknown")")
        }

        transcript = ""
        isTranscribing = false

        do {
            try transcriptionService.startStreaming { [weak self] event in
                self?.handleStreamingEvent(event)
            }
            DebugLogger.log("transcriptionService started")
            try await recordingService.startRecording { [weak self] data in
                try? self?.transcriptionService.sendPCMData(data)
            }
            DebugLogger.log("recordingService started")

            isRecording = true
            statusMessage = "\(mode.title) is listening. Click again to stop."

            if autoPasteEnabled {
                let isTrusted = accessibilityService.isTrusted(prompt: true)
                DebugLogger.log("accessibility trusted=\(isTrusted)")
                focusedTextElement = isTrusted ? accessibilityService.captureFocusedTextElement() : nil
                DebugLogger.log("captured focusedTextElement=\(focusedTextElement != nil)")

                if let lastFrontmostApp {
                    lastFrontmostApp.activate(options: [])
                }

                if !isTrusted {
                    statusMessage = "\(mode.title) is listening. Accessibility permission is needed to paste automatically."
                }
            }

            notifyStateChanged()
        } catch {
            DebugLogger.log("startRecording failed error=\(error.localizedDescription)")
            recordingService.stopRecording()
            try? await transcriptionService.stopStreaming()
            presentError(error.localizedDescription)
        }
    }

    private func stopDictation() async {
        DebugLogger.log("stopDictation begin")
        recordingService.stopRecording()

        isRecording = false
        isTranscribing = true
        statusMessage = "Finishing local transcription..."
        notifyStateChanged()

        do {
            try await transcriptionService.stopStreaming()
            DebugLogger.log("transcriptionService stopped rawTranscriptLength=\(transcript.count)")

            let finalText = await prepareFinalText(transcript, mode: currentMode)
            transcript = finalText
            isTranscribing = false
            clipboardService.copy(transcript)

            if transcript.isEmpty {
                statusMessage = "Stopped. No speech was detected."
            } else if autoPasteEnabled {
                let pasted = await pasteTranscript(transcript, promptForPermission: false)
                statusMessage = pasted
                    ? "\(currentMode.title) inserted."
                    : "\(currentMode.title) copied. Grant Accessibility permission to paste automatically."
            } else {
                statusMessage = "\(currentMode.title) copied to the clipboard."
            }

            focusedTextElement = nil
            notifyStateChanged()
        } catch {
            DebugLogger.log("stopDictation failed error=\(error.localizedDescription)")
            isTranscribing = false
            focusedTextElement = nil
            presentError(error.localizedDescription)
        }
    }

    private func pasteTranscript(_ text: String, promptForPermission: Bool = false) async -> Bool {
        DebugLogger.log("pasteTranscript length=\(text.count) prompt=\(promptForPermission)")
        clipboardService.copy(text)

        guard accessibilityService.isTrusted(prompt: promptForPermission) else {
            DebugLogger.log("pasteTranscript denied accessibility")
            return false
        }

        if let focusedTextElement,
           accessibilityService.insertText(text, into: focusedTextElement) {
            DebugLogger.log("pasteTranscript directInsert=true")
            return true
        }
        DebugLogger.log("pasteTranscript directInsert=false")

        if let lastFrontmostApp {
            lastFrontmostApp.activate(options: [])
            try? await Task.sleep(for: .milliseconds(200))
        }

        let pasted = accessibilityService.simulatePaste()
        DebugLogger.log("pasteTranscript simulatePaste=\(pasted)")
        return pasted
    }

    func setAutoPasteEnabled(_ enabled: Bool) {
        autoPasteEnabled = enabled
        notifyStateChanged()
    }

    private func prepareFinalText(_ text: String, mode: DictationMode) async -> String {
        let cleaned = Self.lightlyCleanTranscript(text)

        guard !cleaned.isEmpty else {
            return ""
        }

        switch mode {
        case .dictate:
            return cleaned
        case .compose:
            statusMessage = "Composing with AI..."
            notifyStateChanged()

            do {
                return try await refinementService.compose(from: cleaned)
            } catch {
                DebugLogger.log("compose failed error=\(error.localizedDescription)")
                statusMessage = "Compose unavailable. Using cleaned transcript."
                notifyStateChanged()
                return cleaned
            }
        }
    }

    private static func lightlyCleanTranscript(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fillerPatterns = [
            #"(?i)\b(um+|uh+|erm+|ah+)\b[, ]*"#,
            #"(?i)\b(you know|i mean|kind of|sort of)\b[, ]*"#
        ]

        for pattern in fillerPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        result = result
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else {
            return ""
        }

        let first = result.prefix(1).uppercased()
        let rest = result.dropFirst()
        result = first + rest

        if let last = result.last, !".!?".contains(last) {
            result += "."
        }

        return result
    }

    private func handleStreamingEvent(_ event: StreamingTranscriptEvent) {
        DebugLogger.log("streamEvent type=\(event.type) textLength=\(event.text?.count ?? 0) undo=\(event.undo ?? 0) message=\(event.message ?? "")")
        switch event.type {
        case "append":
            guard let text = event.text, !text.isEmpty else {
                return
            }

            transcript += text
            notifyStateChanged()
        case "replace":
            let undo = event.undo ?? 0
            let text = event.text ?? ""

            if undo > 0 {
                let drop = min(undo, transcript.count)
                transcript.removeLast(drop)
            }
            transcript += text
            notifyStateChanged()
        case "status":
            if let message = event.message {
                statusMessage = message
                notifyStateChanged()
            }
        case "error":
            presentError(event.message ?? "The local Whisper worker failed.")
        default:
            break
        }
    }

    private func notifyStateChanged() {
        stateDidChange?()
    }
}
