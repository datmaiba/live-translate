import Foundation

/// Pure math for voice ID: embedding similarity, profile building, silence filtering.
enum VoiceMatcher {
    static func normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Cosine similarity in [-1, 1]; nil when shapes differ or a vector is empty/zero.
    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var dot: Float = 0
        var lhsSquared: Float = 0
        var rhsSquared: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsSquared += lhs[index] * lhs[index]
            rhsSquared += rhs[index] * rhs[index]
        }
        guard lhsSquared > 0, rhsSquared > 0 else { return nil }
        return dot / (sqrt(lhsSquared) * sqrt(rhsSquared))
    }

    /// Mean of L2-normalized embeddings, normalized again. nil when empty or shapes differ.
    static func average(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty,
              vectors.allSatisfy({ $0.count == first.count }) else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors.map(normalized) {
            for index in vector.indices { sum[index] += vector[index] }
        }
        return normalized(sum)
    }

    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        let energy = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(energy / Float(samples.count))
    }

    /// Splits audio into fixed-size chunks and keeps the ones loud enough to contain speech.
    static func voicedChunks(_ samples: [Float], chunkSize: Int, minRMS: Float) -> [[Float]] {
        guard chunkSize > 0 else { return [] }
        return stride(from: 0, to: samples.count - chunkSize + 1, by: chunkSize)
            .map { Array(samples[$0..<($0 + chunkSize)]) }
            .filter { rms($0) >= minRMS }
    }
}

/// Owner voice profile (one embedding) stored on device with file protection.
enum VoiceProfileStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("owner-voice.embedding")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> [Float]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func save(_ embedding: [Float]) throws {
        let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
