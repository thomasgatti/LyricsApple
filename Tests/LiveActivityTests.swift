import XCTest
@testable import LyricsApple

final class LiveActivityStateTests: XCTestCase {
    private let track = Track(id: "t", title: "Canzone", artists: ["Artista"], album: "A",
                              duration: 200, artworkURL: nil, spotifyURL: nil)
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 10, text: "Prima"),
            LyricLine(id: 1, time: 15, text: "Seconda"),
            LyricLine(id: 2, time: 20, text: "Terza"),
        ],
        isSynced: true,
        source: "test"
    )

    private func snapshot(playing: Bool = true) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, isPlaying: playing, progress: 0, referenceDate: Date())
    }

    func testShowsCurrentAndNextLineAndWaitsForNextStart() throws {
        let result = NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 15.5)
        let state = try XCTUnwrap(result.state)
        XCTAssertEqual(state.currentLine, "Seconda")
        XCTAssertEqual(state.nextLine, "Terza")
        XCTAssertEqual(result.nextChange, 1, accuracy: 0.001) // 4.5 s mancanti, limitato a 1
        let near = NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 19.7)
        XCTAssertEqual(near.nextChange, 0.32, accuracy: 0.001)
    }

    func testBeforeFirstLineShowsMusicNote() throws {
        let state = try XCTUnwrap(NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 2).state)
        XCTAssertEqual(state.currentLine, "♪")
        XCTAssertEqual(state.nextLine, "Prima")
    }

    func testStatusMessages() throws {
        let missing = try XCTUnwrap(NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .notFound, position: 0).state)
        XCTAssertEqual(missing.currentLine, "Testo non disponibile")
        XCTAssertFalse(missing.hasLyrics)
    }
}
