import AVFoundation
import AudioToolbox
import Foundation
import Speech

/// Orchestrates mic → (VI + EN speech-to-text, owner voice score) → routing → translation → voice.
///
/// - Owner speaks English → ignored.
/// - Owner speaks Vietnamese → simple English (Claude, Google fallback) played on the loudspeaker.
/// - Someone else speaks English → Vietnamese for the owner only + Claude reply suggestions.
@MainActor
final class LiveTranslator: ObservableObject {
    static let shared = LiveTranslator()

    enum State: Equatable {
        case idle
        case listening
        case paused
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let speaker: Speaker
        let language: Lang
        let source: String
        var translation: String
        var note: String
        var suggestions: [ReplySuggestion] = []
        var loadingSuggestions = false
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partial = ""
    @Published private(set) var lines: [Line] = []
    @Published private(set) var speakerStatus = ""
    /// The owner announced (button / Shortcut) that the next English utterance is theirs.
    @Published private(set) var ownerEnglishArmed = false
    @Published var errorMessage: String?

    @Published var speakForOthers: Bool { didSet { defaults.set(speakForOthers, forKey: Keys.speakForOthers) } }
    @Published var speakForMe: Bool { didSet { defaults.set(speakForMe, forKey: Keys.speakForMe) } }
    @Published var muteWhileSpeaking: Bool { didSet { defaults.set(muteWhileSpeaking, forKey: Keys.mute) } }
    @Published var saveHistory: Bool { didSet { defaults.set(saveHistory, forKey: Keys.history) } }
    @Published var suggestReplies: Bool { didSet { defaults.set(suggestReplies, forKey: Keys.suggest) } }
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: Keys.rate) } }
    @Published var ownerThreshold: Double { didSet { defaults.set(ownerThreshold, forKey: Keys.threshold) } }
    @Published var privateOutput: PrivateOutput {
        didSet {
            defaults.set(privateOutput.rawValue, forKey: Keys.privateOutput)
            voice.privateOutput = privateOutput
        }
    }
    @Published var claudeModel: ClaudeModel { didSet { defaults.set(claudeModel.rawValue, forKey: Keys.model) } }
    @Published var claudeKey: String {
        didSet { KeychainStore.set(claudeKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.claudeKey) }
    }

    let history = HistoryStore()

    private enum Keys {
        static let speakForOthers = "speakForOthers"
        static let speakForMe = "speakForMe"
        static let mute = "muteWhileSpeaking"
        static let history = "saveHistory"
        static let suggest = "suggestReplies"
        static let rate = "speechRate"
        static let threshold = "ownerThreshold"
        static let privateOutput = "privateOutput"
        static let model = "claudeModel"
        static let claudeKey = "claudeApiKey"
    }

    private let defaults = UserDefaults.standard
    private let speech = SpeechEngine()
    private let voice = VoiceOutput()
    private let nowPlaying = NowPlayingController()
    private let google = GoogleTranslator()
    private let inbox: AsyncStream<HeardUtterance>.Continuation
    private var ownerEnglishArmedAt: Date?
    private static let ownerEnglishWindow: TimeInterval = 30

    private var claude: ClaudeClient {
        ClaudeClient(apiKey: claudeKey.trimmingCharacters(in: .whitespacesAndNewlines), model: claudeModel)
    }

    private init() {
        defaults.register(defaults: [
            Keys.speakForOthers: true,
            Keys.speakForMe: true,
            Keys.mute: true,
            Keys.history: true,
            Keys.suggest: true,
            Keys.rate: Double(AVSpeechUtteranceDefaultSpeechRate),
            Keys.threshold: 0.5,
            Keys.privateOutput: PrivateOutput.earpiece.rawValue,
            Keys.model: ClaudeModel.haiku.rawValue
        ])
        speakForOthers = defaults.bool(forKey: Keys.speakForOthers)
        speakForMe = defaults.bool(forKey: Keys.speakForMe)
        muteWhileSpeaking = defaults.bool(forKey: Keys.mute)
        saveHistory = defaults.bool(forKey: Keys.history)
        suggestReplies = defaults.bool(forKey: Keys.suggest)
        speechRate = defaults.double(forKey: Keys.rate)
        ownerThreshold = defaults.double(forKey: Keys.threshold)
        privateOutput = PrivateOutput(rawValue: defaults.string(forKey: Keys.privateOutput) ?? "") ?? .earpiece
        claudeModel = ClaudeModel(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .haiku
        claudeKey = KeychainStore.get(Keys.claudeKey) ?? ""

        let (stream, inbox) = AsyncStream<HeardUtterance>.makeStream()
        self.inbox = inbox
        voice.privateOutput = privateOutput

        speech.onPartial = { [weak self] text in self?.partial = text }
        speech.onUtterance = { [weak self] heard in
            self?.partial = ""
            self?.inbox.yield(heard)
        }
        speech.onError = { [weak self] message in self?.errorMessage = message }
        voice.onStart = { [weak self] audience in
            guard let self else { return }
            if audience == .loud || self.muteWhileSpeaking { self.speech.setListening(false) }
        }
        voice.onFinishAll = { [weak self] in
            guard let self, self.state == .listening else { return }
            self.speech.setListening(true)
        }
        nowPlaying.configure(
            onToggle: { [weak self] in self?.toggle() },
            onSwap: { [weak self] in self?.repeatLast() }
        )
        reloadSpeakerID()

        Task { [weak self] in
            for await heard in stream {
                await self?.process(heard)
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
            errorMessage = "Cần quyền Micro và Nhận dạng lời nói: Cài đặt › Live Dich."
            return
        }
        do {
            reloadSpeakerID()
            try speech.start()
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
        voice.stop()
        state = .paused
        partial = ""
        AudioServicesPlaySystemSound(1114)
        refreshNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        state = .listening
        speech.setListening(!voice.isSpeaking)
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
        voice.stop()
        state = .idle
        partial = ""
        nowPlaying.clear()
    }

    func clearScreen() {
        lines.removeAll()
    }

    /// Plays the last translation again (AirPods double press / Shortcut).
    func repeatLast() {
        guard let line = lines.last(where: { !$0.translation.isEmpty && $0.translation != "…" }) else { return }
        switch (line.speaker, line.language) {
        case (.me, .vi):
            voice.speak(line.translation, language: .en, rate: Float(speechRate), audience: .loud)
        case (.other, .en):
            voice.speak(line.translation, language: .vi, rate: Float(speechRate), audience: .private)
        default:
            break
        }
    }

    /// Owner taps a suggested reply → read it aloud for the other person.
    func say(_ suggestion: ReplySuggestion) {
        voice.speak(suggestion.en, language: .en, rate: Float(speechRate), audience: .loud)
        append(Line(speaker: .me, language: .en, source: suggestion.en, translation: suggestion.vi, note: "Đã phát gợi ý"))
    }

    var hasVoiceProfile: Bool { VoiceProfileStore.exists }

    /// Re-reads the voice profile and (re)starts voice ID.
    func reloadSpeakerID() {
        if let problem = speech.speakerTracker.configure() {
            speakerStatus = "ℹ️ \(problem) — đang đoán theo ngôn ngữ. Trước khi nói tiếng Anh, bấm \"🙋 Tôi nói tiếng Anh\"."
        } else {
            speakerStatus = "✅ Đang nhận diện giọng của bạn (ngưỡng \(Int(ownerThreshold * 100))%)"
        }
    }

    func deleteVoiceProfile() {
        VoiceProfileStore.delete()
        reloadSpeakerID()
    }

    /// The next English utterance (within 30 s) belongs to the owner → don't translate it.
    func markOwnerSpeakingEnglish() {
        ownerEnglishArmed = true
        ownerEnglishArmedAt = Date()
        AudioServicesPlaySystemSound(1519)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ownerEnglishWindow) { [weak self] in
            guard let self, let armedAt = self.ownerEnglishArmedAt,
                  Date().timeIntervalSince(armedAt) >= Self.ownerEnglishWindow else { return }
            self.ownerEnglishArmed = false
            self.ownerEnglishArmedAt = nil
        }
    }

    func cancelOwnerEnglish() {
        ownerEnglishArmed = false
        ownerEnglishArmedAt = nil
    }

    /// Applies the manual "I'm speaking English" marker to an utterance that ended after the tap.
    private func applyOwnerMarker(_ heard: HeardUtterance) -> HeardUtterance {
        guard ownerEnglishArmed, let armedAt = ownerEnglishArmedAt, heard.endedAt >= armedAt,
              LanguageHeuristics.detect(heard) == .en else { return heard }
        var marked = heard
        marked.ownerScore = 1
        cancelOwnerEnglish()
        return marked
    }

    // MARK: - Pipeline

    private func process(_ utterance: HeardUtterance) async {
        let heard = applyOwnerMarker(utterance)
        let voiceNote = heard.ownerScore.map { " · giọng \(Int(($0 * 100).rounded()))%" } ?? ""
        switch TurnRouter.route(heard, ownerThreshold: Float(ownerThreshold)) {
        case let .ignore(reason, text, speaker, language):
            append(Line(speaker: speaker, language: language, source: text, translation: "", note: reason + voiceNote))

        case .speakForMe(let vietnamese):
            let id = append(Line(speaker: .me, language: .vi, source: vietnamese, translation: "…", note: ""))
            let (english, engine) = await interpretForOthers(vietnamese)
            guard let english else {
                update(id) { $0.translation = ""; $0.note = "⚠️ \(engine)" }
                return
            }
            update(id) { $0.translation = english; $0.note = engine + voiceNote }
            if saveHistory { history.add(direction: .viToEn, source: vietnamese, translation: english) }
            if speakForOthers && state == .listening {
                voice.speak(english, language: .en, rate: Float(speechRate), audience: .loud)
            }
            refreshNowPlaying(title: english, subtitle: "🗣 Bạn: \(vietnamese)")

        case .translateForMe(let english):
            let id = append(Line(speaker: .other, language: .en, source: english, translation: "…", note: ""))
            do {
                let vietnamese = try await translateWithRetry(english, direction: .enToVi)
                update(id) { $0.translation = vietnamese; $0.note = "Google" + voiceNote }
                if saveHistory { history.add(direction: .enToVi, source: english, translation: vietnamese) }
                if speakForMe && state == .listening {
                    voice.speak(vietnamese, language: .vi, rate: Float(speechRate), audience: .private)
                }
                refreshNowPlaying(title: vietnamese, subtitle: "👂 \(english)")
            } catch {
                update(id) { $0.translation = ""; $0.note = "⚠️ \(error.localizedDescription)" }
            }
            if suggestReplies && claude.isConfigured {
                Task { await loadSuggestions(for: id) }
            }
        }
    }

    /// Vietnamese → simple spoken English. Claude when configured, Google otherwise / on failure.
    private func interpretForOthers(_ vietnamese: String) async -> (String?, String) {
        if claude.isConfigured {
            do {
                return (try await claude.interpret(vietnamese: vietnamese, context: context()), "Claude")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        do {
            return (try await translateWithRetry(vietnamese, direction: .viToEn), "Google")
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func loadSuggestions(for id: UUID) async {
        update(id) { $0.loadingSuggestions = true }
        do {
            let suggestions = try await claude.suggestReplies(context: context())
            update(id) { $0.suggestions = suggestions; $0.loadingSuggestions = false }
        } catch {
            update(id) { $0.loadingSuggestions = false }
            errorMessage = error.localizedDescription
        }
    }

    private func translateWithRetry(_ text: String, direction: Direction) async throws -> String {
        do {
            return try await google.translate(text, direction: direction)
        } catch {
            try await Task.sleep(nanoseconds: 400_000_000)
            return try await google.translate(text, direction: direction)
        }
    }

    /// Recent conversation in English for Claude.
    private func context(limit: Int = 10) -> [ConversationTurn] {
        lines.suffix(limit).compactMap { line in
            switch (line.speaker, line.language) {
            case (.me, .vi):
                let english = line.translation
                return english.isEmpty || english == "…" ? nil : ConversationTurn(speaker: .me, text: english)
            case (_, .en):
                return ConversationTurn(speaker: line.speaker, text: line.source)
            default:
                return nil
            }
        }
    }

    @discardableResult
    private func append(_ line: Line) -> UUID {
        lines.append(line)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        return line.id
    }

    private func update(_ id: UUID, _ change: (inout Line) -> Void) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        change(&lines[index])
    }

    private func refreshNowPlaying(title: String? = nil, subtitle: String? = nil) {
        guard state != .idle else { return }
        let status = state == .listening ? "🎙 Đang nghe" : "⏸ Tạm dừng"
        nowPlaying.update(
            title: title ?? status,
            subtitle: subtitle.map { "\(status) · \($0)" } ?? "Live Dịch",
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
