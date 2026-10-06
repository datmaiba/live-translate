import AVFoundation
import Speech

enum SpeechEngineError: LocalizedError {
    case recognizerUnavailable(String)
    case noAudioInput

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let locale): return "Không có bộ nhận dạng giọng nói cho \(locale)"
        case .noAudioInput: return "Không tìm thấy micro"
        }
    }
}

/// Continuous speech-to-text. Keeps the audio engine running (so it survives in background)
/// and cuts the stream into utterances on silence, restarting recognition tasks as needed.
final class SpeechEngine {
    var onPartial: ((String) -> Void)?
    var onUtterance: ((String) -> Void)?
    var onError: ((String) -> Void)?

    var silenceTimeout: TimeInterval = 1.2
    var maxSegmentDuration: TimeInterval = 45

    private(set) var isRunning = false
    private(set) var isListening = false

    private let audioEngine = AVAudioEngine()
    private let silentPlayer = AVAudioPlayerNode()
    private let tap = TapState()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var latestText = ""
    private var segmentStart = Date()
    private var silenceWork: DispatchWorkItem?
    private var consecutiveErrors = 0
    private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start(locale: Locale) throws {
        try setRecognizer(locale: locale)
        try activateSession()
        try startAudio()
        isRunning = true
        isListening = true
        observeSystemEvents()
        beginSegment()
    }

    func stop() {
        isRunning = false
        isListening = false
        cancelSegment()
        latestText = ""
        silentPlayer.stop()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Pauses/resumes recognition while keeping the microphone session alive,
    /// so listening can be resumed later even from background.
    func setListening(_ listening: Bool) {
        guard isRunning, listening != isListening else { return }
        isListening = listening
        if listening {
            beginSegment()
        } else {
            cancelSegment()
            latestText = ""
        }
    }

    func setLocale(_ locale: Locale) throws {
        try setRecognizer(locale: locale)
        guard isRunning, isListening else { return }
        cancelSegment()
        latestText = ""
        beginSegment()
    }

    // MARK: - Audio

    private func setRecognizer(locale: Locale) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechEngineError.recognizerUnavailable(locale.identifier)
        }
        recognizer.defaultTaskHint = .dictation
        self.recognizer = recognizer
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    private func startAudio() throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechEngineError.noAudioInput }

        input.removeTap(onBus: 0)
        let tap = self.tap
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            tap.append(buffer)
        }

        // A looping silent buffer keeps the output side active, which makes iOS treat us
        // as the "Now Playing" app (lock screen card + AirPods remote controls).
        let silence = Self.makeSilentBuffer()
        if silentPlayer.engine == nil, let silence {
            audioEngine.attach(silentPlayer)
            audioEngine.connect(silentPlayer, to: audioEngine.mainMixerNode, format: silence.format)
        }

        audioEngine.prepare()
        try audioEngine.start()

        if let silence, silentPlayer.engine != nil {
            silentPlayer.stop()
            silentPlayer.scheduleBuffer(silence, at: nil, options: .loops)
            silentPlayer.play()
        }
    }

    private static func makeSilentBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        if let channel = buffer.floatChannelData?[0] {
            channel.initialize(repeating: 0, count: Int(buffer.frameLength))
        }
        return buffer
    }

    private func observeSystemEvents() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.recoverAudio(after: 0.5)
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            self?.recoverAudio(after: 0.2)
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.recoverAudio(after: 1)
        })
    }

    private func recoverAudio(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.cancelSegment()
            self.audioEngine.stop()
            do {
                try self.activateSession()
                try self.startAudio()
                if self.isListening { self.beginSegment() }
            } catch {
                self.onError?("Mất micro (\(error.localizedDescription)), đang thử lại…")
                self.recoverAudio(after: 2)
            }
        }
    }

    // MARK: - Recognition segments

    private func beginSegment() {
        guard isRunning, isListening, let recognizer else { return }
        generation += 1
        let gen = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        tap.setRequest(request)
        latestText = ""
        segmentStart = Date()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                self?.handle(generation: gen, text: text, isFinal: isFinal, error: error)
            }
        }
    }

    private func cancelSegment() {
        generation += 1
        silenceWork?.cancel()
        silenceWork = nil
        tap.setRequest(nil)?.endAudio()
        task?.cancel()
        task = nil
    }

    private func handle(generation gen: Int, text: String?, isFinal: Bool, error: Error?) {
        guard gen == generation else { return }

        if let text, !text.isEmpty, text != latestText {
            consecutiveErrors = 0
            latestText = text
            onPartial?(text)
            if Date().timeIntervalSince(segmentStart) > maxSegmentDuration {
                commit()
                return
            }
            scheduleSilenceCommit()
        }

        if isFinal {
            commit()
        } else if error != nil {
            if latestText.isEmpty {
                restartAfterError()
            } else {
                commit()
            }
        }
    }

    private func scheduleSilenceCommit() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeout, execute: work)
    }

    private func commit() {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        latestText = ""
        cancelSegment()
        beginSegment()
        if !text.isEmpty { onUtterance?(text) }
    }

    private func restartAfterError() {
        consecutiveErrors += 1
        cancelSegment()
        if consecutiveErrors == 8 {
            onError?("Nhận dạng giọng nói đang lỗi liên tục, kiểm tra mạng hoặc quyền truy cập.")
        }
        let delay = min(0.3 * pow(2, Double(min(consecutiveErrors, 5))), 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.task == nil else { return }
            self.beginSegment()
        }
    }
}

/// Shared between the realtime audio thread (tap) and the main thread.
private final class TapState {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    @discardableResult
    func setRequest(_ newValue: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = newValue
        return old
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}
