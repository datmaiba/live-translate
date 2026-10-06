import Foundation
@_implementationOnly import SherpaOnnxC

/// Thin wrapper over sherpa-onnx's C speaker-embedding API (on-device, no network, no account).
/// Not thread-safe: use from one queue at a time.
final class SpeakerEmbedder {
    static let modelName = "speaker-campplus"

    private let extractor: OpaquePointer
    let dimension: Int

    /// Loads the bundled model. Returns nil when the model is missing or fails to load.
    static func makeDefault() -> SpeakerEmbedder? {
        guard let path = Bundle.main.path(forResource: modelName, ofType: "onnx") else { return nil }
        return SpeakerEmbedder(modelPath: path)
    }

    init?(modelPath: String, threads: Int = 2) {
        var config = SherpaOnnxSpeakerEmbeddingExtractorConfig()
        let created: OpaquePointer? = modelPath.withCString { model in
            "cpu".withCString { provider in
                config.model = model
                config.provider = provider
                config.num_threads = Int32(threads)
                config.debug = 0
                return SherpaOnnxCreateSpeakerEmbeddingExtractor(&config)
            }
        }
        guard let created else { return nil }
        extractor = created
        dimension = Int(SherpaOnnxSpeakerEmbeddingExtractorDim(created))
    }

    deinit {
        SherpaOnnxDestroySpeakerEmbeddingExtractor(extractor)
    }

    /// Embedding for 16 kHz mono audio, nil when the audio is too short for the model.
    func embedding(samples: [Float], sampleRate: Int = PCMConverter.sampleRate) -> [Float]? {
        guard !samples.isEmpty, let stream = SherpaOnnxSpeakerEmbeddingExtractorCreateStream(extractor) else {
            return nil
        }
        defer { SherpaOnnxDestroyOnlineStream(stream) }
        SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(sampleRate), samples, Int32(samples.count))
        SherpaOnnxOnlineStreamInputFinished(stream)
        guard SherpaOnnxSpeakerEmbeddingExtractorIsReady(extractor, stream) == 1,
              let pointer = SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding(extractor, stream) else {
            return nil
        }
        defer { SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding(pointer) }
        return Array(UnsafeBufferPointer(start: pointer, count: dimension))
    }
}
