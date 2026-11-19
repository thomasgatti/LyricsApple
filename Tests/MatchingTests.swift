import XCTest
@testable import LyricsApple

final class TitleCleanerTests: XCTestCase {
    func testRemovesRemasterSuffix() {
        XCTAssertEqual(TitleCleaner.clean("Bohemian Rhapsody - Remastered 2011"), "Bohemian Rhapsody")
    }

    func testRemovesFeaturing() {
        XCTAssertEqual(TitleCleaner.clean("Song Name (feat. Someone)"), "Song Name")
        XCTAssertEqual(TitleCleaner.clean("Song Name [ft. Someone]"), "Song Name")
    }

    func testKeepsMeaningfulDashTitles() {
        XCTAssertEqual(TitleCleaner.clean("Hold On - We're Going Home"), "Hold On - We're Going Home")
    }

    func testNormalizeIgnoresCaseAccentsAndLeadingThe() {
        XCTAssertEqual(TitleCleaner.normalize("The Beatles"), "beatles")
        XCTAssertEqual(TitleCleaner.normalize("Mån"), "man")
    }
}

final class LRCLIBMatchingTests: XCTestCase {
    private let query = LyricsQuery(title: "Song - Remastered", artist: "Artist", album: "Album", duration: 200)

    private func record(id: Int, artist: String = "Artist", title: String = "Song", duration: Double = 200,
                        synced: String? = nil, plain: String? = nil) -> LRCLIBProvider.Record {
        LRCLIBProvider.Record(id: id, trackName: title, artistName: artist, albumName: "Album", duration: duration,
                              instrumental: false, plainLyrics: plain, syncedLyrics: synced)
    }

    func testPrefersSyncedLyrics() {
        let best = LRCLIBProvider.bestMatch(in: [
            record(id: 1, plain: "plain"),
            record(id: 2, synced: "[00:01.00]x"),
        ], for: query)
        XCTAssertEqual(best?.id, 2)
    }

    func testRejectsWrongArtistAndDuration() {
        XCTAssertNil(LRCLIBProvider.bestMatch(in: [
            record(id: 1, artist: "Someone Else", synced: "[00:01.00]x"),
            record(id: 2, duration: 260, synced: "[00:01.00]x"),
        ], for: query))
    }

    func testRecordWithoutTextIsNotAResult() {
        XCTAssertNil(LRCLIBProvider.result(from: record(id: 1)))
    }
}
