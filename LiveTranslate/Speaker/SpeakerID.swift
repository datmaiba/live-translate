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

/// Scores how much the current utterance sounds like the owner.
/// Placeholder until on-device voice ID ships (D-018 A): always "unknown",
/// so routing falls back to language + the "Tôi nói tiếng Anh" marker.
final class SpeakerTracker {
    /// Returns a user-facing reason when voice ID is not active, nil when active.
    func configure() -> String? {
        "Chưa có nhận diện giọng tự động"
    }

    func append(_ buffer: AVAudioPCMBuffer) {}

    func reset() {}

    func currentScore() -> Float? { nil }
}
