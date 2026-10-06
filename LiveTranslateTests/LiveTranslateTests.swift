import XCTest
@testable import LiveTranslate

final class DirectionTests: XCTestCase {
    func testTargetIsOppositeLanguage() {
        XCTAssertEqual(Direction.viToEn.target, .en)
        XCTAssertEqual(Direction.enToVi.target, .vi)
    }

    func testSwapped() {
        XCTAssertEqual(Direction.viToEn.swapped(), .enToVi)
        XCTAssertEqual(Direction.enToVi.swapped().swapped(), .enToVi)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Direction.enToVi)
        XCTAssertEqual(try JSONDecoder().decode(Direction.self, from: data), .enToVi)
    }

    func testLocales() {
        XCTAssertEqual(Lang.vi.bcp47, "vi-VN")
        XCTAssertEqual(Lang.en.bcp47, "en-US")
    }
}

final class GoogleResponseParserTests: XCTestCase {
    func testParsesSingleSegment() throws {
        let json = #"[[["Hello world","Xin chào thế giới",null,null,10]],null,"vi"]"#
        XCTAssertEqual(try GoogleResponseParser.parse(Data(json.utf8)), "Hello world")
    }

    func testJoinsMultipleSegments() throws {
        let json = #"[[["Hello. ","Xin chào. ",null,null,3],["How are you?","Bạn khỏe không?",null,null,3]],null,"vi"]"#
        XCTAssertEqual(try GoogleResponseParser.parse(Data(json.utf8)), "Hello. How are you?")
    }

    func testEmptyResultThrows() {
        let json = #"[[],null,"vi"]"#
        XCTAssertThrowsError(try GoogleResponseParser.parse(Data(json.utf8)))
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try GoogleResponseParser.parse(Data("{}".utf8)))
    }

    func testURLEncodesSpecialCharacters() throws {
        let url = try XCTUnwrap(GoogleResponseParser.url(for: "a+b & c=d?", direction: .viToEn))
        let query = try XCTUnwrap(url.query)
        XCTAssertTrue(query.contains("sl=vi"))
        XCTAssertTrue(query.contains("tl=en"))
        XCTAssertTrue(query.contains("q=a%2Bb%20%26%20c%3Dd%3F"), query)
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testAddPersistsAcrossInstances() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(direction: .viToEn, source: "Xin chào", translation: "Hello")
        let reloaded = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.translation, "Hello")
        XCTAssertEqual(reloaded.entries.first?.direction, .viToEn)
    }

    func testDeleteRemovesOnlySelected() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(direction: .viToEn, source: "a", translation: "A")
        store.add(direction: .enToVi, source: "b", translation: "B")
        let firstID = store.entries[0].id
        store.delete(ids: [firstID])
        XCTAssertEqual(store.entries.map(\.source), ["b"])
        XCTAssertEqual(HistoryStore(fileURL: fileURL).entries.count, 1)
    }

    func testClear() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(direction: .viToEn, source: "a", translation: "A")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(HistoryStore(fileURL: fileURL).entries.isEmpty)
    }
}

final class LanguageHeuristicsTests: XCTestCase {
    func testVietnameseRatio() {
        XCTAssertGreaterThan(LanguageHeuristics.vietnameseRatio("Tôi muốn hỏi đường đến khách sạn"), 0.2)
        XCTAssertEqual(LanguageHeuristics.vietnameseRatio("Where is the hotel"), 0)
        XCTAssertEqual(LanguageHeuristics.vietnameseRatio(""), 0)
    }

    func testDetectVietnamese() {
        let heard = HeardUtterance(vietnamese: "Cảm ơn bạn rất nhiều", english: "Come on bun rat new", ownerScore: nil)
        XCTAssertEqual(LanguageHeuristics.detect(heard), .vi)
    }

    func testDetectEnglish() {
        let heard = HeardUtterance(vietnamese: "where is the station", english: "Where is the station?", ownerScore: nil)
        XCTAssertEqual(LanguageHeuristics.detect(heard), .en)
    }

    func testDetectNothing() {
        XCTAssertNil(LanguageHeuristics.detect(HeardUtterance(vietnamese: " ", english: "", ownerScore: nil)))
    }
}

final class TurnRouterTests: XCTestCase {
    private let vietnamese = "Tôi muốn đặt một bàn cho hai người"
    private let english = "How many people are in your party?"

    func testOwnerSpeakingVietnameseIsSpokenForOthers() {
        let heard = HeardUtterance(vietnamese: vietnamese, english: "toy moon dat", ownerScore: 0.9)
        XCTAssertEqual(TurnRouter.route(heard, ownerThreshold: 0.5), .speakForMe(vietnamese: vietnamese))
    }

    func testOwnerSpeakingEnglishIsIgnored() {
        let heard = HeardUtterance(vietnamese: "how many people", english: english, ownerScore: 0.8)
        guard case .ignore(_, _, let speaker, let language) = TurnRouter.route(heard, ownerThreshold: 0.5) else {
            return XCTFail("expected ignore")
        }
        XCTAssertEqual(speaker, .me)
        XCTAssertEqual(language, .en)
    }

    func testOtherSpeakingEnglishIsTranslatedForOwner() {
        let heard = HeardUtterance(vietnamese: "how many people", english: english, ownerScore: 0.1)
        XCTAssertEqual(TurnRouter.route(heard, ownerThreshold: 0.5), .translateForMe(english: english))
    }

    func testOtherSpeakingVietnameseIsIgnored() {
        let heard = HeardUtterance(vietnamese: vietnamese, english: "toy moon", ownerScore: 0.1)
        guard case .ignore(_, _, let speaker, let language) = TurnRouter.route(heard, ownerThreshold: 0.5) else {
            return XCTFail("expected ignore")
        }
        XCTAssertEqual(speaker, .other)
        XCTAssertEqual(language, .vi)
    }

    func testWithoutVoiceProfileFallsBackToLanguage() {
        let vi = HeardUtterance(vietnamese: vietnamese, english: "toy", ownerScore: nil)
        XCTAssertEqual(TurnRouter.route(vi, ownerThreshold: 0.5), .speakForMe(vietnamese: vietnamese))
        let en = HeardUtterance(vietnamese: "how many", english: english, ownerScore: nil)
        XCTAssertEqual(TurnRouter.route(en, ownerThreshold: 0.5), .translateForMe(english: english))
    }
}

final class ClaudePromptsTests: XCTestCase {
    func testParsesSuggestionsInsideProse() {
        let text = """
        Here you go:
        [{"en": "Yes, please.", "vi": "Vâng, làm ơn."}, {"en": "Can you say that again?", "vi": "Bạn nói lại được không?"},
         {"en": "Thank you!", "vi": "Cảm ơn!"}, {"en": "Extra", "vi": "Thừa"}]
        """
        let suggestions = ClaudePrompts.parseSuggestions(text)
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.first, ReplySuggestion(en: "Yes, please.", vi: "Vâng, làm ơn."))
    }

    func testBadSuggestionsReturnEmpty() {
        XCTAssertTrue(ClaudePrompts.parseSuggestions("no json here").isEmpty)
        XCTAssertTrue(ClaudePrompts.parseSuggestions("[{\"oops\": 1}]").isEmpty)
    }

    func testParseTextJoinsTextBlocks() throws {
        let json = #"{"content":[{"type":"text","text":"Hello, "},{"type":"text","text":"nice to meet you."}]}"#
        XCTAssertEqual(try ClaudePrompts.parseText(Data(json.utf8)), "Hello, nice to meet you.")
    }

    func testRequestBody() {
        let body = ClaudePrompts.requestBody(model: .haiku, system: "sys", user: "hi", maxTokens: 100)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "hi")
    }

    func testInterpretMessageIncludesContext() {
        let message = ClaudePrompts.interpretUserMessage(
            vietnamese: "Bao nhiêu tiền?",
            context: [ConversationTurn(speaker: .other, text: "This one is nice.")]
        )
        XCTAssertTrue(message.contains("Other: This one is nice."))
        XCTAssertTrue(message.hasSuffix("Dat says (Vietnamese): Bao nhiêu tiền?"))
    }
}
