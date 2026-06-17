@preconcurrency import AVFoundation
import Foundation

enum RecordingError: LocalizedError {
    case microphonePermissionDenied
    case inputUnavailable
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone."
        case .inputUnavailable:
            return "No microphone input is available."
        case .converterUnavailable:
            return "The microphone audio could not be converted for Whisper."
        }
    }
}

@MainActor
final class RecordingService {
    private let audioEngine = AVAudioEngine()
    private let processor = AudioBufferProcessor()
    private var isRunning = false

    func startRecording(onPCMData: @escaping @MainActor (Data) -> Void) async throws {
        DebugLogger.log("RecordingService startRecording")
        try await ensureMicrophonePermission()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw RecordingError.inputUnavailable
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw RecordingError.converterUnavailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecordingError.converterUnavailable
        }

        processor.configure(
            converter: converter,
            inputFormat: inputFormat,
            outputFormat: outputFormat,
            onPCMData: onPCMData
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat,
            block: processor.makeTapHandler()
        )

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        DebugLogger.log("RecordingService audioEngine started")
    }

    func stopRecording() {
        guard isRunning else {
            DebugLogger.log("RecordingService stopRecording ignored")
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        processor.reset()
        isRunning = false
        DebugLogger.log("RecordingService stopped")
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DebugLogger.log("microphone authorized")
            return
        case .notDetermined:
            DebugLogger.log("microphone permission prompt")
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }

            if !granted {
                DebugLogger.log("microphone permission denied after prompt")
                throw RecordingError.microphonePermissionDenied
            }
            DebugLogger.log("microphone permission granted after prompt")
        default:
            DebugLogger.log("microphone permission denied existingStatus")
            throw RecordingError.microphonePermissionDenied
        }
    }
}

private final class AudioBufferProcessor: @unchecked Sendable {
    private let processingQueue = DispatchQueue(label: "Wisp.AudioProcessing")
    private let lock = NSLock()

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var onPCMData: (@MainActor (Data) -> Void)?

    func configure(
        converter: AVAudioConverter,
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        onPCMData: @escaping @MainActor (Data) -> Void
    ) {
        lock.lock()
        self.converter = converter
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.onPCMData = onPCMData
        lock.unlock()
    }

    func reset() {
        lock.lock()
        converter = nil
        inputFormat = nil
        outputFormat = nil
        onPCMData = nil
        lock.unlock()
    }

    func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let converter, let inputFormat, let outputFormat, let onPCMData else {
            lock.unlock()
            return
        }
        lock.unlock()

        processingQueue.async {
            let outputFrameCapacity = AVAudioFrameCount(
                (Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate).rounded(.up)
            ) + 256

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                return
            }

            final class InputState: @unchecked Sendable {
                var consumed = false
            }

            let inputState = InputState()
            var error: NSError?

            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if inputState.consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }

                inputState.consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil, status != .error else {
                return
            }

            guard convertedBuffer.frameLength > 0,
                  let channelData = convertedBuffer.int16ChannelData else {
                return
            }

            let sampleCount = Int(convertedBuffer.frameLength)
            let byteCount = sampleCount * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData.pointee, count: byteCount)

            Task { @MainActor in
                onPCMData(data)
            }
        }
    }

    func makeTapHandler() -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }
    }
}
