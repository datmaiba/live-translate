import SwiftUI
import Translation

/// Apple's on-device Translation framework only hands out a `TranslationSession`
/// inside a SwiftUI `.translationTask` closure. We keep that closure alive and feed it
/// jobs through a stream, so the session is never used outside its closure.
@available(iOS 18.0, *)
@MainActor
final class AppleTranslationBridge: ObservableObject {
    enum Kind {
        case translate(String)
        case prepare
    }

    struct Job {
        let id: UUID
        let kind: Kind
    }

    let configurations: [Direction: TranslationSession.Configuration] = [
        .viToEn: TranslationSession.Configuration(
            source: Locale.Language(identifier: "vi"),
            target: Locale.Language(identifier: "en")
        ),
        .enToVi: TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "vi")
        )
    ]

    private var inboxes: [Direction: AsyncStream<Job>.Continuation] = [:]
    private var pending: [UUID: CheckedContinuation<String, Error>] = [:]

    func translate(_ text: String, direction: Direction, timeout: TimeInterval = 4) async throws -> String {
        try await submit(.translate(text), direction: direction, timeout: timeout)
    }

    /// Asks the system to download the offline language pack (shows a system prompt; app must be in foreground).
    func prepare(direction: Direction) async throws {
        _ = try await submit(.prepare, direction: direction, timeout: 300)
    }

    func statusText() async -> String {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "vi"),
            to: Locale.Language(identifier: "en")
        )
        switch status {
        case .installed: return "Đã tải — dịch offline"
        case .supported: return "Chưa tải gói offline"
        case .unsupported: return "Máy không hỗ trợ"
        @unknown default: return "Không rõ"
        }
    }

    func serve(session: TranslationSession, direction: Direction) async {
        let (stream, inbox) = AsyncStream<Job>.makeStream()
        inboxes[direction] = inbox
        for await job in stream {
            switch job.kind {
            case .translate(let text):
                do {
                    let response = try await session.translate(text)
                    finish(job.id, .success(response.targetText))
                } catch {
                    finish(job.id, .failure(error))
                }
            case .prepare:
                do {
                    try await session.prepareTranslation()
                    finish(job.id, .success(""))
                } catch {
                    finish(job.id, .failure(error))
                }
            }
        }
        inboxes[direction] = nil
    }

    private func submit(_ kind: Kind, direction: Direction, timeout: TimeInterval) async throws -> String {
        guard let inbox = inboxes[direction] else { throw TranslationError.unavailable }
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            inbox.yield(Job(id: id, kind: kind))
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(id, .failure(TranslationError.timeout))
            }
        }
    }

    private func finish(_ id: UUID, _ result: Result<String, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }
}

@available(iOS 18.0, *)
struct TranslationHost: View {
    @ObservedObject var bridge: AppleTranslationBridge

    var body: some View {
        ZStack {
            Color.clear
                .translationTask(bridge.configurations[.viToEn]) { session in
                    await bridge.serve(session: session, direction: .viToEn)
                }
            Color.clear
                .translationTask(bridge.configurations[.enToVi]) { session in
                    await bridge.serve(session: session, direction: .enToVi)
                }
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
