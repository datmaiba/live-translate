import AVFoundation

final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var onFinishAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func speak(_ text: String, language: Lang, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.bcp47)
        utterance.rate = rate
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        notifyIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        notifyIfIdle()
    }

    private func notifyIfIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.synth.isSpeaking else { return }
            self.onFinishAll?()
        }
    }
}
