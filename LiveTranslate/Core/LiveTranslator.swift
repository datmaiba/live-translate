import AVFoundation
import AudioToolbox
import Foundation
import Speech

/// Orchestrates mic → speech-to-text → translation → TTS / lock screen.
@MainActor
final class LiveTranslator: ObservableObject {
    static let shared = LiveTranslator()

    enum State: Equatable {
        case idle
        case listening
        case paused
    }

    enum Engine: String, CaseIterable, Identifiable {
        case auto
        case apple
        case google

        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Tự động (Apple offline → Google)"
            case .apple: return "Chỉ Apple (offline)"
            case .google: return "Chỉ Google (cần mạng)"
            }
        }
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let direction: Direction
        let source: String
        var translation: String
        var engine: String
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partial = ""
    @Published private(set) var lines: [Line] = []
    @Published var errorMessage: String?

    @Published var direction: Direction {
        didSet {
            defaults.set(direction.source.rawValue, forKey: Keys.direction)
            directionChanged()
        }
    }
    @Published var speakOutput: Bool { didSet { defaults.set(speakOutput, forKey: Keys.speak) } }
    @Published var muteWhileSpeaking: Bool { didSet { defaults.set(muteWhileSpeaking, forKey: Keys.mute) } }
    @Published var saveHistory: Bool { didSet { defaults.set(saveHistory, forKey: Keys.history) } }
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: Keys.rate) } }
    @Published var engine: Engine { didSet { defaults.set(engine.rawValue, forKey: Keys.engine) } }

    let history = HistoryStore()

    private enum Keys {
        static let direction = "direction"
        static let speak = "speakOutput"
        static let mute = "muteWhileSpeaking"
        static let history = "saveHistory"
        static let rate = "speechRate"
        static let engine = "engine"
    }

    private let defaults = UserDefaults.standard
    private let speech = SpeechEngine()
    private let speaker = Speaker()
    private let nowPlaying = NowPlayingController()
    private let google = GoogleTranslator()
    private let inbox: AsyncStream<(String, Direction)>.Continuation
    private var appleBridgeStorage: AnyObject?

    @available(iOS 18.0, *)
    var appleBridge: AppleTranslationBridge {
        // swiftlint:disable:next force_cast
        appleBridgeStorage as! AppleTranslationBridge
    }

    private init() {
        defaults.register(defaults: [
            Keys.direction: Lang.en.rawValue,
            Keys.speak: true,
            Keys.mute: true,
            Keys.history: true,
            Keys.rate: Double(AVSpeechUtteranceDefaultSpeechRate),
            Keys.engine: Engine.auto.rawValue
        ])
        direction = Direction(source: Lang(rawValue: defaults.string(forKey: Keys.direction) ?? "") ?? .en)
        speakOutput = defaults.bool(forKey: Keys.speak)
        muteWhileSpeaking = defaults.bool(forKey: Keys.mute)
        saveHistory = defaults.bool(forKey: Keys.history)
        speechRate = defaults.double(forKey: Keys.rate)
        engine = Engine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .auto

        let (stream, inbox) = AsyncStream<(String, Direction)>.makeStream()
        self.inbox = inbox
        if #available(iOS 18.0, *) {
            appleBridgeStorage = AppleTranslationBridge()
        }

        speech.onPartial = { [weak self] text in self?.partial = text }
        speech.onUtterance = { [weak self] text in
            guard let self else { return }
            self.partial = ""
            self.inbox.yield((text, self.direction))
        }
        speech.onError = { [weak self] message in self?.errorMessage = message }
        speaker.onFinishAll = { [weak self] in
            guard let self, self.state == .listening else { return }
            self.speech.setListening(true)
        }
        nowPlaying.configure(
            onToggle: { [weak self] in self?.toggle() },
            onSwap: { [weak self] in self?.swapDirection() }
        )

        Task { [weak self] in
            for await (text, direction) in stream {
                await self?.process(text, direction: direction)
            }
        }
    }

    // MARK: - Controls

    func start() async {
        switch state {
        case .listening: return
        case .paused: resume(); return
        case .idle: break
        }
        guard await requestPermissions() else {
            errorMessage = "Cần quyền Micro và Nhận dạng lời nói: Cài đặt › Live Dịch."
            return
        }
        do {
            try speech.start(locale: direction.source.locale)
            state = .listening
            errorMessage = nil
            AudioServicesPlaySystemSound(1113)
            refreshNowPlaying()
        } catch {
            errorMessage = "Không bật được micro: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .listening else { return }
        speech.setListening(false)
        speaker.stop()
        state = .paused
        partial = ""
        AudioServicesPlaySystemSound(1114)
        refreshNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        state = .listening
        speech.setListening(!speaker.isSpeaking)
        AudioServicesPlaySystemSound(1113)
        refreshNowPlaying()
    }

    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .listening: pause()
        case .paused: resume()
        }
    }

    func stopCompletely() {
        speech.stop()
        speaker.stop()
        state = .idle
        partial = ""
        nowPlaying.clear()
    }

    func swapDirection() {
        direction = direction.swapped()
    }

    func clearScreen() {
        lines.removeAll()
    }

    // MARK: - Pipeline

    private func directionChanged() {
        partial = ""
        if state != .idle {
            do {
                try speech.setLocale(direction.source.locale)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        refreshNowPlaying()
    }

    private func process(_ text: String, direction: Direction) async {
        let line = Line(direction: direction, source: text, translation: "…", engine: "")
        lines.append(line)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }

        let result: (text: String, engine: String)
        do {
            result = try await translate(text, direction: direction)
        } catch {
            update(line.id, translation: "⚠️ \(error.localizedDescription)", engine: "")
            return
        }
        let translated = result.text
        update(line.id, translation: translated, engine: result.engine)

        if saveHistory {
            history.add(direction: direction, source: text, translation: translated)
        }
        refreshNowPlaying(title: translated, subtitle: text)

        if speakOutput && state == .listening {
            if muteWhileSpeaking { speech.setListening(false) }
            speaker.speak(translated, language: direction.target, rate: Float(speechRate))
        }
    }

    private func translate(_ text: String, direction: Direction) async throws -> (String, String) {
        if engine != .google, #available(iOS 18.0, *) {
            do {
                return (try await appleBridge.translate(text, direction: direction), "Apple")
            } catch {
                if engine == .apple { throw error }
            }
        }
        return (try await google.translate(text, direction: direction), "Google")
    }

    private func update(_ id: UUID, translation: String, engine: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translation = translation
        lines[index].engine = engine
    }

    private func refreshNowPlaying(title: String? = nil, subtitle: String? = nil) {
        guard state != .idle else { return }
        let status = state == .listening ? "🎙 Đang nghe" : "⏸ Tạm dừng"
        let last = lines.last
        nowPlaying.update(
            title: title ?? last?.translation ?? "\(status) \(direction.label)",
            subtitle: "\(status) · \(direction.label)" + ((subtitle ?? last?.source).map { " · \($0)" } ?? ""),
            isListening: state == .listening
        )
    }

    private func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        return speechOK && micOK
    }
}
