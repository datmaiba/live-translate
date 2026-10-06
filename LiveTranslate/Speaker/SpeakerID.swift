import AVFoundation

/// Converts microphone buffers (usually 48 kHz Float32) into 16 kHz mono Float32 samples
/// for speaker-embedding models.
final class PCMConverter {
    static let sampleRate = 16_000

    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(sampleRate),
        channels: 1,
        interleaved: false
    )

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let outFormat = Self.targetFormat else { return [] }
        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
        }
        guard let converter else { return [] }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return [] }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// Scores how much each utterance sounds like the owner, on device (sherpa-onnx).
/// Audio is converted on the tap thread; embedding work runs on a private serial queue.
final class SpeakerTracker {
    /// Shortest audio worth scoring (0.75 s).
    static let minSamples = PCMConverter.sampleRate * 3 / 4
    /// Longest audio kept per utterance (12 s) — enough for a stable embedding.
    static let maxSamples = PCMConverter.sampleRate * 12

    private let queue = DispatchQueue(label: "speaker-tracker", qos: .userInitiated)
    private let converter = PCMConverter()
    private let lock = NSLock()
    private var enabled = false
    private var embedder: SpeakerEmbedder?
    private var profile: [Float]?
    private var samples: [Float] = []

    /// Returns a user-facing reason when voice ID is not active, nil when active.
    func configure() -> String? {
        let problem = queue.sync { () -> String? in
            guard let profile = VoiceProfileStore.load() else {
                self.profile = nil
                return "Chưa đăng ký giọng của bạn"
            }
            if embedder == nil { embedder = SpeakerEmbedder.makeDefault() }
            guard let embedder, embedder.dimension == profile.count else {
                self.profile = nil
                return "Giọng đã lưu không khớp model — hãy đăng ký lại"
            }
            self.profile = profile
            return nil
        }
        lock.lock()
        enabled = problem == nil
        lock.unlock()
        return problem
    }

    /// Called on the audio tap thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let isEnabled = enabled
        lock.unlock()
        guard isEnabled else { return }
        let converted = converter.convert(buffer)
        queue.async { [weak self] in
            guard let self else { return }
            self.samples.append(contentsOf: converted)
            if self.samples.count > Self.maxSamples {
                self.samples.removeFirst(self.samples.count - Self.maxSamples)
            }
        }
    }

    /// Starts a new utterance.
    func reset() {
        queue.async { [weak self] in self?.samples.removeAll(keepingCapacity: true) }
    }

    /// Scores the audio collected since the last reset, then clears it.
    /// `completion` runs on the main queue (also when voice ID is off, with nil) so ordering is preserved.
    func scoreCurrentUtterance(_ completion: @escaping (Float?) -> Void) {
        queue.async { [weak self] in
            var score: Float?
            if let self {
                let snapshot = self.samples
                self.samples.removeAll(keepingCapacity: true)
                if let profile = self.profile, let embedder = self.embedder, snapshot.count >= Self.minSamples,
                   let embedding = embedder.embedding(samples: snapshot) {
                    score = VoiceMatcher.cosine(embedding, profile)
                }
            }
            DispatchQueue.main.async { completion(score) }
        }
    }
}

/// Thread-safe sample collector for enrollment (filled from the tap thread).
private final class SampleCollector {
    private let lock = NSLock()
    private let converter = PCMConverter()
    private var samples: [Float] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        let converted = converter.convert(buffer)
        lock.lock()
        samples.append(contentsOf: converted)
        lock.unlock()
    }

    func take() -> [Float] {
        lock.lock()
        defer { samples.removeAll(); lock.unlock() }
        return samples
    }
}

enum EnrollmentConfig {
    static let duration: TimeInterval = 20
    static let chunkSeconds = 4
    static let minVoicedChunks = 3
    static let minRMS: Float = 0.01
}

enum EnrollmentError: LocalizedError {
    case modelMissing
    case tooQuiet

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Không tải được model nhận diện giọng"
        case .tooQuiet: return "Chưa nghe đủ giọng — đọc to, rõ hơn rồi thử lại"
        }
    }
}

/// Records ~20 s of the owner's voice once and stores the averaged embedding.
@MainActor
final class VoiceEnroller: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var message: String?
    @Published private(set) var finished = false

    private let engine = AVAudioEngine()
    private let collector = SampleCollector()
    private var startedAt: Date?
    private var timer: Timer?

    func start() {
        guard !isRecording, !isProcessing else { return }
        message = nil
        progress = 0
        finished = false
        _ = collector.take()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            let collector = self.collector
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                collector.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            startedAt = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.tick() }
            }
        } catch {
            message = "Không bắt đầu được: \(error.localizedDescription)"
        }
    }

    func cancel() {
        stopRecording()
        _ = collector.take()
    }

    private func tick() {
        guard isRecording, let startedAt else { return }
        progress = min(Date().timeIntervalSince(startedAt) / EnrollmentConfig.duration, 1)
        if progress >= 1 { finish() }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    private func finish() {
        stopRecording()
        isProcessing = true
        message = "Đang xử lý giọng…"
        let samples = collector.take()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = VoiceEnroller.buildProfile(from: samples)
            DispatchQueue.main.async { [weak self] in self?.complete(result) }
        }
    }

    private func complete(_ result: Result<[Float], EnrollmentError>) {
        isProcessing = false
        switch result {
        case .success(let embedding):
            do {
                try VoiceProfileStore.save(embedding)
                finished = true
                message = "Đã lưu giọng của bạn ✅"
            } catch {
                message = "Lưu giọng lỗi: \(error.localizedDescription)"
            }
        case .failure(let error):
            progress = 0
            message = error.localizedDescription
        }
    }

    nonisolated private static func buildProfile(from samples: [Float]) -> Result<[Float], EnrollmentError> {
        guard let embedder = SpeakerEmbedder.makeDefault() else { return .failure(.modelMissing) }
        let chunks = VoiceMatcher.voicedChunks(
            samples,
            chunkSize: PCMConverter.sampleRate * EnrollmentConfig.chunkSeconds,
            minRMS: EnrollmentConfig.minRMS
        )
        let embeddings = chunks.compactMap { embedder.embedding(samples: $0) }
        guard embeddings.count >= EnrollmentConfig.minVoicedChunks, let profile = VoiceMatcher.average(embeddings) else {
            return .failure(.tooQuiet)
        }
        return .success(profile)
    }
}
