import Foundation

/// What the recognizers heard for one utterance.
struct HeardUtterance: Equatable {
    /// Transcript from the Vietnamese recognizer.
    var vietnamese: String
    /// Transcript from the English recognizer.
    var english: String
    /// Similarity to the owner's voice in [0, 1], `nil` when unknown.
    var ownerScore: Float?
    /// When the utterance finished (used to match the manual "I'm speaking English" marker).
    var endedAt = Date()
}

enum Speaker: String, Codable, Equatable {
    case me
    case other
}

/// The action to take for one utterance.
enum TurnAction: Equatable {
    /// Owner spoke Vietnamese → translate to simple English and play it out loud.
    case speakForMe(vietnamese: String)
    /// Someone else spoke English → translate to Vietnamese privately for the owner.
    case translateForMe(english: String)
    /// Nothing to do (owner speaking English, someone else speaking Vietnamese, or noise).
    case ignore(reason: String, text: String, speaker: Speaker, language: Lang)
}

enum LanguageHeuristics {
    private static let vietnameseLetters: Set<Character> = Set(
        "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    )

    /// Share of letters carrying Vietnamese diacritics. Real Vietnamese is typically > 0.3,
    /// while the Vietnamese recognizer fed with English speech mostly emits plain ASCII words.
    static func vietnameseRatio(_ text: String) -> Double {
        let letters = text.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        let marked = letters.filter { vietnameseLetters.contains($0) }.count
        return Double(marked) / Double(letters.count)
    }

    static func detect(_ heard: HeardUtterance, threshold: Double = 0.12) -> Lang? {
        let vi = heard.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = heard.english.trimmingCharacters(in: .whitespacesAndNewlines)
        if vi.isEmpty && en.isEmpty { return nil }
        if vi.isEmpty { return .en }
        if en.isEmpty { return vietnameseRatio(vi) >= threshold ? .vi : nil }
        return vietnameseRatio(vi) >= threshold ? .vi : .en
    }
}

enum TurnRouter {
    /// - Parameter ownerThreshold: voice-ID score at or above which the voice is considered the owner's.
    static func route(_ heard: HeardUtterance, ownerThreshold: Float) -> TurnAction {
        guard let language = LanguageHeuristics.detect(heard) else {
            return .ignore(reason: "Không rõ", text: heard.english, speaker: .other, language: .en)
        }
        let speaker: Speaker? = heard.ownerScore.map { $0 >= ownerThreshold ? .me : .other }

        switch (language, speaker) {
        case (.vi, .other):
            return .ignore(reason: "Người khác nói tiếng Việt", text: heard.vietnamese, speaker: .other, language: .vi)
        case (.vi, _):
            // Unknown speaker speaking Vietnamese is almost always the owner.
            return .speakForMe(vietnamese: heard.vietnamese)
        case (.en, .me):
            return .ignore(reason: "Bạn đang nói tiếng Anh", text: heard.english, speaker: .me, language: .en)
        case (.en, _):
            return .translateForMe(english: heard.english)
        }
    }
}
