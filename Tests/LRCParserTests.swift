import XCTest
@testable import LyricsApple

final class LRCParserTests: XCTestCase {
    func testParsesLinesAndSkipsMetadata() throws {
        let lrc = """
        [ar:Artist]
        [ti:Title]
        [00:01.50] Hello
        [00:03.00]World
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(try XCTUnwrap(lines[0].time), 1.5, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Hello")
        XCTAssertEqual(lines[1].text, "World")
        XCTAssertEqual(lines.map(\.id), [0, 1])
    }

    func testMultipleTimestampsAreExpandedAndSorted() {
        let lines = LRCParser.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse")
        XCTAssertEqual(lines.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(lines.compactMap(\.time), [10, 20, 30])
    }

    func testThreeDigitMillisecondsAndColonCentiseconds() throws {
        let lines = LRCParser.parse("[01:02.345]a\n[01:03:50]b")
        XCTAssertEqual(try XCTUnwrap(lines[0].time), 62.345, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(lines[1].time), 63.5, accuracy: 0.0001)
    }

    func testOffsetTagShiftsLyricsEarlier() throws {
        let lines = LRCParser.parse("[offset:+500]\n[00:02.00]a")
        XCTAssertEqual(try XCTUnwrap(lines.first?.time), 1.5, accuracy: 0.001)
    }

    func testEmptyTimedLineIsKeptAsInstrumentalBreak() {
        let lines = LRCParser.parse("[00:05.00]")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "")
    }

    func testGarbageIsIgnored() {
        XCTAssertTrue(LRCParser.parse("no tags here\n[xx:yy]bad\n[length: 03:20]").isEmpty)
    }
}

final class LyricsTests: XCTestCase {
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 0, text: "a"),
            LyricLine(id: 1, time: 5, text: "b"),
            LyricLine(id: 2, time: 10, text: "c"),
        ],
        isSynced: true,
        source: "test"
    )

    func testLineIndex() {
        XCTAssertNil(lyrics.lineIndex(at: -1))
        XCTAssertEqual(lyrics.lineIndex(at: 0), 0)
        XCTAssertEqual(lyrics.lineIndex(at: 4.99), 0)
        XCTAssertEqual(lyrics.lineIndex(at: 5), 1)
        XCTAssertEqual(lyrics.lineIndex(at: 500), 2)
    }

    func testPlainLyricsAreNeverSynced() {
        let plain = Lyrics.plain("uno\ndue", source: "test")
        XCTAssertFalse(plain.isSynced)
        XCTAssertEqual(plain.lines.map(\.text), ["uno", "due"])
        XCTAssertNil(plain.lineIndex(at: 3))
    }

    func testLyricsResultRoundTripsThroughJSON() throws {
        let original = LyricsResult.lyrics(lyrics)
        let decoded = try JSONDecoder().decode(LyricsResult.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
