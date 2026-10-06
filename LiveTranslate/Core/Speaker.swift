import AVFoundation

/// Where private (owner-only) audio goes when no headphones are connected.
enum PrivateOutput: String, CaseIterable, Identifiable {
    case earpiece
    case speaker
    case textOnly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .earpiece: return "Áp tai (loa thoại)"
        case .speaker: return "Loa ngoài"
        case .textOnly: return "Chỉ hiện chữ"
        }
    }
}

/// Text-to-speech with per-utterance routing, played one at a time from a FIFO:
/// - `.loud`: for the other person — always the iPhone loudspeaker.
/// - `.private`: for the owner — headphones if connected, else the chosen `PrivateOutput`.
/// All methods are called on the main thread.
final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {
    enum Audience: Equatable {
        case loud
        case `private`
    }

    private struct Item {
        let text: String
        let language: Lang
        let rate: Float
        let audience: Audience
    }

    var privateOutput: PrivateOutput = .earpiece
    /// Called right before an item starts playing (main thread).
    var onStart: ((Audience) -> Void)?
    /// Called when the queue is empty again (main thread).
    var onFinishAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queue: [Item] = []
    private var current: Item?

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    var isSpeaking: Bool { current != nil }

    static var headphonesConnected: Bool {
        let ports: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
    }

    /// Returns false when nothing will be played (private audio in text-only mode).
    @discardableResult
    func speak(_ text: String, language: Lang, rate: Float, audience: Audience) -> Bool {
        if audience == .private && !Self.headphonesConnected && privateOutput == .textOnly {
            return false
        }
        queue.append(Item(text: text, language: language, rate: rate, audience: audience))
        playNextIfIdle()
        return true
    }

    func stop() {
        queue.removeAll()
        synth.stopSpeaking(at: .immediate)
    }

    private func playNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        let item = queue.removeFirst()
        current = item
        let loud = item.audience == .loud || (!Self.headphonesConnected && privateOutput == .speaker)
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(loud ? .speaker : .none)
        onStart?(item.audience)

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = AVSpeechSynthesisVoice(language: item.language.bcp47)
        utterance.rate = item.rate
        utterance.preUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    private func finishedCurrent() {
        current = nil
        if queue.isEmpty {
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            onFinishAll?()
        } else {
            playNextIfIdle()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.finishedCurrent() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.finishedCurrent() }
    }
}
