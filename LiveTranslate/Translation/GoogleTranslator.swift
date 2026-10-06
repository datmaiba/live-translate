import Foundation

enum TranslationError: LocalizedError {
    case emptyResult
    case badResponse
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .emptyResult: return "Không có kết quả dịch"
        case .badResponse: return "Máy chủ dịch trả về lỗi"
        case .unavailable: return "Bộ dịch offline chưa sẵn sàng"
        case .timeout: return "Dịch quá thời gian"
        }
    }
}

/// Parses the response of Google's public `translate_a/single?client=gtx` endpoint:
/// `[[["translated", "original", ...], ...], null, "vi", ...]`.
enum GoogleResponseParser {
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?#")
        return set
    }()

    static func url(for text: String, direction: Direction) -> URL? {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        let params: [(String, String)] = [
            ("client", "gtx"),
            ("sl", direction.source.rawValue),
            ("tl", direction.target.rawValue),
            ("dt", "t"),
            ("q", text)
        ]
        components?.percentEncodedQuery = params
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
        return components?.url
    }

    static func parse(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            throw TranslationError.badResponse
        }
        let text = segments
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationError.emptyResult }
        return text
    }
}

struct GoogleTranslator {
    var session: URLSession = .shared

    func translate(_ text: String, direction: Direction) async throws -> String {
        guard let url = GoogleResponseParser.url(for: text, direction: direction) else {
            throw TranslationError.badResponse
        }
        let request = URLRequest(url: url, timeoutInterval: 8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TranslationError.badResponse
        }
        return try GoogleResponseParser.parse(data)
    }
}
