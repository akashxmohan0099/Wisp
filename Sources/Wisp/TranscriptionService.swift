import Foundation

struct StreamingTranscriptEvent: Decodable {
    let type: String
    let text: String?
    let undo: Int?
    let runtime: String?
    let model: String?
    let message: String?
}

enum TranscriptionServiceError: LocalizedError {
    case missingScript(String)
    case alreadyRunning
    case notRunning
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScript(let file):
            return "The bundled transcription script \(file) is missing."
        case .alreadyRunning:
            return "Live transcription is already running."
        case .notRunning:
            return "Live transcription is not running."
        case .processFailed(let message):
            return message
        }
    }
}

@MainActor
final class TranscriptionService {
    private let model = ProcessInfo.processInfo.environment["WISP_MODEL"]
        ?? ProcessInfo.processInfo.environment["VOICE_TO_TEXT_MODEL"]
        ?? "base.en"

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var bufferedOutput = Data()
    private var terminationContinuation: CheckedContinuation<Void, Error>?
    private var isStopping = false

    func startStreaming(
        onEvent: @escaping @MainActor (StreamingTranscriptEvent) -> Void
    ) throws {
        guard process == nil else {
            DebugLogger.log("TranscriptionService startStreaming alreadyRunning")
            throw TranscriptionServiceError.alreadyRunning
        }

        guard let scriptURL = Bundle.module.url(forResource: "stream_transcribe", withExtension: "py") else {
            DebugLogger.log("TranscriptionService missing script")
            throw TranscriptionServiceError.missingScript("stream_transcribe.py")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvePythonExecutable())
        process.arguments = [
            scriptURL.path,
            "--model",
            model
        ]
        DebugLogger.log("TranscriptionService starting python=\(process.executableURL?.path ?? "") script=\(scriptURL.path) model=\(model)")

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                return
            }

            Task { @MainActor in
                self?.consumeOutputData(data, onEvent: onEvent)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.finishTermination(process: process, stderrPipe: stderrPipe)
            }
        }

        try process.run()
        DebugLogger.log("TranscriptionService process started pid=\(process.processIdentifier)")

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.isStopping = false
    }

    func sendPCMData(_ data: Data) throws {
        guard let fileHandle = stdinPipe?.fileHandleForWriting else {
            DebugLogger.log("TranscriptionService sendPCMData notRunning")
            throw TranscriptionServiceError.notRunning
        }

        try fileHandle.write(contentsOf: data)
    }

    func stopStreaming() async throws {
        guard let process else {
            DebugLogger.log("TranscriptionService stopStreaming noProcess")
            return
        }

        if isStopping {
            DebugLogger.log("TranscriptionService stopStreaming alreadyStopping")
            return
        }

        DebugLogger.log("TranscriptionService stopStreaming pid=\(process.processIdentifier)")

        try await withCheckedThrowingContinuation { continuation in
            terminationContinuation = continuation
            isStopping = true

            do {
                try stdinPipe?.fileHandleForWriting.close()
            } catch {
                DebugLogger.log("TranscriptionService stopStreaming closeError=\(error.localizedDescription)")
                terminationContinuation = nil
                isStopping = false
                continuation.resume(throwing: error)
                return
            }

            if !process.isRunning {
                finishTermination(process: process, stderrPipe: stderrPipe)
            }
        }
    }

    private func finishTermination(process: Process, stderrPipe: Pipe?) {
        DebugLogger.log("TranscriptionService finishTermination status=\(process.terminationStatus)")
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        self.stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let continuation = terminationContinuation {
            terminationContinuation = nil

            if process.terminationStatus == 0 {
                continuation.resume()
            } else {
                let errorData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let errorText = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = errorText.isEmpty ? "The local Whisper worker failed." : errorText
                DebugLogger.log("TranscriptionService processFailed message=\(message)")
                continuation.resume(throwing: TranscriptionServiceError.processFailed(message))
            }
        }

        self.process = nil
        stdinPipe = nil
        stdoutPipe = nil
        self.stderrPipe = nil
        bufferedOutput.removeAll(keepingCapacity: false)
        isStopping = false
    }

    private func consumeOutputData(
        _ data: Data,
        onEvent: @escaping @MainActor (StreamingTranscriptEvent) -> Void
    ) {
        bufferedOutput.append(data)

        while let newlineRange = bufferedOutput.range(of: Data([0x0A])) {
            let lineData = bufferedOutput.subdata(in: 0..<newlineRange.lowerBound)
            bufferedOutput.removeSubrange(0...newlineRange.lowerBound)

            guard !lineData.isEmpty,
                  let event = try? JSONDecoder().decode(StreamingTranscriptEvent.self, from: lineData) else {
                continue
            }

            onEvent(event)
        }
    }

    private func resolvePythonExecutable() -> String {
        let environment = ProcessInfo.processInfo.environment

        if let explicit = environment["WISP_PYTHON"] ?? environment["VOICE_TO_TEXT_PYTHON"],
           FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            homeDirectory.appendingPathComponent(".wisp/venv/bin/python3").path,
            homeDirectory.appendingPathComponent(".voice-to-text/venv/bin/python3").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".venv/bin/python3").path,
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3"
        ]

        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/python3"
    }
}
