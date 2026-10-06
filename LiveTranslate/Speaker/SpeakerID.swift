import AVFoundation
import Eagle

/// Converts microphone buffers (usually 48 kHz Float32) into 16 kHz mono Int16 samples for Eagle.
final class PCMConverter {
    static let eagleFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(EagleBase.sampleRate),
        channels: 1,
        interleaved: true
    )

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> [Int16] {
        guard let outFormat = Self.eagleFormat else { return [] }
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
        guard error == nil, let channel = output.int16ChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// Stores the owner's voice profile on device (Application Support, file protection on).
enum VoiceProfileStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("owner-voice.eagle")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> EagleProfile? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return EagleProfile(profileBytes: [UInt8](data))
    }

    static func save(_ profile: EagleProfile) throws {
        try Data(profile.getBytes()).write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Scores how much the current utterance sounds like the owner. Fed from the audio tap,
/// all Eagle work happens on a private serial queue.
final class SpeakerTracker {
    private let queue = DispatchQueue(label: "speaker-tracker", qos: .userInitiated)
    private let converter = PCMConverter()
    private var eagle: Eagle?
    private var profile: EagleProfile?
    private var pending: [Int16] = []
    private var chunk = 0
    private var scores: [Float] = []

    /// Returns an error message when Eagle can't start (bad key, no profile…), nil on success.
    func configure(accessKey: String?) -> String? {
        queue.sync { () -> String? in
            eagle?.delete()
            eagle = nil
            pending.removeAll()
            scores.removeAll()
            guard let accessKey, !accessKey.isEmpty else { return "Chưa nhập Picovoice AccessKey" }
            guard let profile = VoiceProfileStore.load() else { return "Chưa đăng ký giọng của bạn" }
            do {
                let engine = try Eagle(accessKey: accessKey)
                let minimum = try engine.minProcessSamples()
                chunk = max(minimum, EagleBase.sampleRate / 4)
                self.eagle = engine
                self.profile = profile
                return nil
            } catch {
                return "Eagle lỗi: \(error.localizedDescription)"
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, let eagle = self.eagle, let profile = self.profile else { return }
            self.pending.append(contentsOf: self.converter.convert(buffer))
            while self.pending.count >= self.chunk {
                let frame = Array(self.pending.prefix(self.chunk))
                self.pending.removeFirst(self.chunk)
                if let score = try? eagle.process(pcm: frame, speakerProfiles: [profile])?.first {
                    self.scores.append(score)
                }
            }
        }
    }

    /// Starts a new utterance.
    func reset() {
        queue.async { [weak self] in
            self?.pending.removeAll()
            self?.scores.removeAll()
        }
    }

    /// Average owner score for the utterance so far, `nil` when not active or not enough voice.
    func currentScore() -> Float? {
        queue.sync { () -> Float? in
            guard eagle != nil, !scores.isEmpty else { return nil }
            return scores.reduce(0, +) / Float(scores.count)
        }
    }
}

/// Feeds microphone audio to `EagleProfiler` off the main thread.
private final class EnrollmentWorker {
    private let queue = DispatchQueue(label: "voice-enroller")
    private let converter = PCMConverter()
    private let profiler: EagleProfiler
    private var pending: [Int16] = []
    private let onUpdate: @Sendable (Float?, String?) -> Void

    init(profiler: EagleProfiler, onUpdate: @escaping @Sendable (Float?, String?) -> Void) {
        self.profiler = profiler
        self.onUpdate = onUpdate
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            pending.append(contentsOf: converter.convert(buffer))
            let frameLength = EagleProfiler.frameLength
            var latest: Float?
            var failure: String?
            while pending.count >= frameLength {
                let frame = Array(pending.prefix(frameLength))
                pending.removeFirst(frameLength)
                do {
                    latest = try profiler.enroll(pcm: frame)
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
            if latest != nil || failure != nil { onUpdate(latest, failure) }
        }
    }

    func export() throws -> EagleProfile {
        try queue.sync { try profiler.export() }
    }

    func close() {
        queue.sync { profiler.delete() }
    }
}

/// Records the owner's voice once to build the Eagle profile.
@MainActor
final class VoiceEnroller: ObservableObject {
    @Published private(set) var progress: Float = 0
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    @Published private(set) var finished = false

    private let engine = AVAudioEngine()
    private var worker: EnrollmentWorker?

    func start(accessKey: String) {
        guard !isRecording else { return }
        message = nil
        progress = 0
        finished = false
        do {
            let profiler = try EagleProfiler(accessKey: accessKey)
            let worker = EnrollmentWorker(profiler: profiler) { [weak self] progress, error in
                DispatchQueue.main.async { self?.update(progress: progress, error: error) }
            }
            self.worker = worker
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                worker.feed(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            message = "Không bắt đầu được: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    func cancel() {
        stop()
        worker?.close()
        worker = nil
    }

    private func update(progress newValue: Float?, error: String?) {
        if let error { message = error }
        guard let newValue, isRecording else { return }
        progress = newValue
        if newValue >= 100 { complete() }
    }

    private func complete() {
        stop()
        guard let worker else { return }
        do {
            try VoiceProfileStore.save(try worker.export())
            finished = true
            message = "Đã lưu giọng của bạn ✅"
        } catch {
            message = "Lưu giọng lỗi: \(error.localizedDescription)"
        }
        worker.close()
        self.worker = nil
    }
}
