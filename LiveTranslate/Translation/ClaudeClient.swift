import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .haiku: return "Haiku 4.5 — nhanh"
        case .sonnet: return "Sonnet 5.5 — thông minh hơn, chậm hơn"
        }
    }
}

struct ReplySuggestion: Codable, Equatable, Hashable {
    let en: String
    let vi: String
}

struct ConversationTurn: Equatable {
    let speaker: Speaker
    let text: String
}

enum ClaudeError: LocalizedError {
    case missingKey
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Chưa nhập Claude API key"
        case .http(let code, let message): return "Claude lỗi \(code): \(message)"
        case .emptyResponse: return "Claude không trả lời"
        }
    }
}

/// Prompt building and response parsing — pure, unit tested.
enum ClaudePrompts {
    static let interpreterSystem = """
    You are a live interpreter for Dat, a Vietnamese speaker talking face to face with English speakers.
    Translate what Dat says from Vietnamese into spoken English that is SHORT, SIMPLE and COMMON:
    everyday words (CEFR A2–B1), short sentences, natural and polite, no idioms or rare words.
    Keep his meaning; fix obvious speech-recognition mistakes using the conversation context.
    Output ONLY the English sentence(s) to be read aloud — no quotes, no notes.
    """

    static let suggestionSystem = """
    You help Dat, a Vietnamese speaker with basic English, reply in a live face-to-face conversation.
    Given the conversation, suggest 3 different short replies Dat could say next.
    Each reply: simple common English (CEFR A2–B1), at most 12 words, easy to pronounce, natural and polite.
    Make the replies genuinely useful (answer the question, ask for clarification, or keep the talk going).
    Respond with ONLY a JSON array: [{"en": "...", "vi": "nghĩa tiếng Việt"}, ...]
    """

    static func transcript(_ turns: [ConversationTurn]) -> String {
        turns.map { "\($0.speaker == .me ? "Dat" : "Other"): \($0.text)" }.joined(separator: "\n")
    }

    static func interpretUserMessage(vietnamese: String, context: [ConversationTurn]) -> String {
        var message = ""
        if !context.isEmpty {
            message += "Conversation so far (English):\n\(transcript(context))\n\n"
        }
        message += "Dat says (Vietnamese): \(vietnamese)"
        return message
    }

    static func suggestionUserMessage(context: [ConversationTurn]) -> String {
        "Conversation so far:\n\(transcript(context))\n\nSuggest Dat's next reply."
    }

    static func parseSuggestions(_ text: String) -> [ReplySuggestion] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let items = try? JSONDecoder().decode([ReplySuggestion].self, from: data) else {
            return []
        }
        return items
            .filter { !$0.en.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(3)
            .map { $0 }
    }

    static func requestBody(model: ClaudeModel, system: String, user: String, maxTokens: Int) -> [String: Any] {
        [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
    }

    static func parseText(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ClaudeError.emptyResponse
        }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.emptyResponse }
        return text
    }
}

struct ClaudeClient {
    var apiKey: String?
    var model: ClaudeModel
    var session: URLSession = .shared

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    func interpret(vietnamese: String, context: [ConversationTurn]) async throws -> String {
        try await complete(
            system: ClaudePrompts.interpreterSystem,
            user: ClaudePrompts.interpretUserMessage(vietnamese: vietnamese, context: context),
            maxTokens: 300
        )
    }

    func suggestReplies(context: [ConversationTurn]) async throws -> [ReplySuggestion] {
        let text = try await complete(
            system: ClaudePrompts.suggestionSystem,
            user: ClaudePrompts.suggestionUserMessage(context: context),
            maxTokens: 400
        )
        return ClaudePrompts.parseSuggestions(text)
    }

    private func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw ClaudeError.missingKey }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ClaudePrompts.requestBody(model: model, system: system, user: user, maxTokens: maxTokens)
        )
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String ?? ""
            throw ClaudeError.http(status, message)
        }
        return try ClaudePrompts.parseText(data)
    }
}
