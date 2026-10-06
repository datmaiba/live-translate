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
