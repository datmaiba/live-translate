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

/// Continuous speech-to-text in Vietnamese AND English at the same time, plus an owner-voice
/// score per utterance. Keeps the audio engine running (so it survives in background) and cuts
/// the stream into utterances on silence.
final class SpeechEngine {
    var onPartial: ((String) -> Void)?
    var onUtterance: ((HeardUtterance) -> Void)?
    var onError: ((String) -> Void)?

    var silenceTimeout: TimeInterval = 1.2
    var maxSegmentDuration: TimeInterval = 45

    let speakerTracker = SpeakerTracker()

    private(set) var isRunning = false
    private(set) var isListening = false

    private let audioEngine = AVAudioEngine()
    private let silentPlayer = AVAudioPlayerNode()
    private let tap: TapState
    private var recognizers: [Lang: SFSpeechRecognizer] = [:]
    private var tasks: [Lang: SFSpeechRecognitionTask] = [:]
    private var finishedLanguages: Set<Lang> = []
    private var generation = 0
    private var latest: [Lang: String] = [:]
    private var segmentStart = Date()
    private var silenceWork: DispatchWorkItem?
    private var consecutiveErrors = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        tap = TapState(tracker: speakerTracker)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() throws {
        for lang in Lang.allCases {
            guard let recognizer = SFSpeechRecognizer(locale: lang.locale) else {
                throw SpeechEngineError.recognizerUnavailable(lang.bcp47)
            }
            recognizer.defaultTaskHint = .dictation
            recognizers[lang] = recognizer
        }
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
        }
    }

    // MARK: - Audio

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // No .defaultToSpeaker: without headphones private audio goes to the earpiece;
        // VoiceOutput overrides to the loudspeaker when the other person must hear it.
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetooth, .allowBluetoothA2DP]
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
        guard isRunning, isListening, !recognizers.isEmpty else { return }
        generation += 1
        let gen = generation
        latest = [:]
        finishedLanguages = []
        segmentStart = Date()
        speakerTracker.reset()

        var requests: [SFSpeechAudioBufferRecognitionRequest] = []
        for (lang, recognizer) in recognizers {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            // Online-first: Apple's server recognizer is more accurate for Vietnamese.
            request.requiresOnDeviceRecognition = false
            requests.append(request)
            tasks[lang] = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                DispatchQueue.main.async {
                    self?.handle(generation: gen, lang: lang, text: text, isFinal: isFinal, failed: failed)
                }
            }
        }
        tap.setRequests(requests)
    }

    private func cancelSegment() {
        generation += 1
        silenceWork?.cancel()
        silenceWork = nil
        tap.setRequests([]).forEach { $0.endAudio() }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        latest = [:]
    }

    private func handle(generation gen: Int, lang: Lang, text: String?, isFinal: Bool, failed: Bool) {
        guard gen == generation else { return }

        if let text, !text.isEmpty, text != latest[lang] {
            consecutiveErrors = 0
            latest[lang] = text
            onPartial?(displayText)
            if Date().timeIntervalSince(segmentStart) > maxSegmentDuration {
                commit()
                return
            }
            scheduleSilenceCommit()
        }

        guard isFinal || failed else { return }
        finishedLanguages.insert(lang)
        guard finishedLanguages.count == recognizers.count else { return }
        if hasText {
            commit()
        } else {
            restartAfterError()
        }
    }

    private var hasText: Bool {
        latest.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var displayText: String {
        let heard = currentUtterance(score: nil)
        return LanguageHeuristics.detect(heard) == .vi ? heard.vietnamese : heard.english
    }

    private func currentUtterance(score: Float?) -> HeardUtterance {
        HeardUtterance(
            vietnamese: (latest[.vi] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            english: (latest[.en] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            ownerScore: score
        )
    }

    private func scheduleSilenceCommit() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeout, execute: work)
    }

    private func commit() {
        let utterance = currentUtterance(score: speakerTracker.currentScore())
        cancelSegment()
        beginSegment()
        if !utterance.vietnamese.isEmpty || !utterance.english.isEmpty {
            onUtterance?(utterance)
        }
    }

    private func restartAfterError() {
        consecutiveErrors += 1
        cancelSegment()
        if consecutiveErrors == 8 {
            onError?("Nhận dạng giọng nói đang lỗi liên tục, kiểm tra mạng hoặc quyền truy cập.")
        }
        let delay = min(0.3 * pow(2, Double(min(consecutiveErrors, 5))), 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.tasks.isEmpty else { return }
            self.beginSegment()
        }
    }
}

/// Shared between the realtime audio thread (tap) and the main thread.
private final class TapState {
    private let lock = NSLock()
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    private let tracker: SpeakerTracker

    init(tracker: SpeakerTracker) {
        self.tracker = tracker
    }

    @discardableResult
    func setRequests(_ newValue: [SFSpeechAudioBufferRecognitionRequest]) -> [SFSpeechAudioBufferRecognitionRequest] {
        lock.lock()
        defer { lock.unlock() }
        let old = requests
        requests = newValue
        return old
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = requests
        lock.unlock()
        guard !current.isEmpty else { return }
        current.forEach { $0.append(buffer) }
        tracker.append(buffer)
    }
}
