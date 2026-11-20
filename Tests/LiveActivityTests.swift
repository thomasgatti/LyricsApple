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

    func testScrollingLinesAndKaraokeTimes() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = try XCTUnwrap(NowPlayingViewModel.liveActivityState(
            snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 16, now: now
        ).state)
        XCTAssertEqual(state.previousLine, "Prima")
        XCTAssertEqual(state.currentLine, "Seconda")
        XCTAssertEqual(state.nextLine, "Terza")
        XCTAssertEqual(state.afterNextLine, "")
        XCTAssertEqual(state.lineIndex, 1)
        // Il brano è partito 16 s fa: la riga 2 va da 15 a 20 s.
        XCTAssertEqual(try XCTUnwrap(state.lineStart).timeIntervalSince(now), -1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.lineEnd).timeIntervalSince(now), 4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.songEnd).timeIntervalSince(now), 184, accuracy: 0.001)

        let paused = try XCTUnwrap(NowPlayingViewModel.liveActivityState(
            snapshot: snapshot(playing: false), lyricsState: .loaded(lyrics), position: 16, now: now
        ).state)
        XCTAssertNil(paused.lineStart)
        XCTAssertNil(paused.songStart)
    }

    func testSmallTimeDifferencesDoNotTriggerUpdates() throws {
        let now = Date()
        let a = try XCTUnwrap(NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 16, now: now).state)
        let b = try XCTUnwrap(NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 16, now: now.addingTimeInterval(0.2)).state)
        XCTAssertTrue(a.isEquivalent(to: b))
        let c = try XCTUnwrap(NowPlayingViewModel.liveActivityState(snapshot: snapshot(), lyricsState: .loaded(lyrics), position: 21, now: now).state)
        XCTAssertFalse(a.isEquivalent(to: c))
    }

    @MainActor
    func testNudgeSyncOffsetRoundsAndClamps() {
        let model = NowPlayingViewModel(auth: SpotifyAuthService())
        let saved = model.syncOffset
        defer { model.syncOffset = saved }
        model.syncOffset = 0.1
        model.nudgeSyncOffset(by: 0.5)
        XCTAssertEqual(model.syncOffset, 0.5, accuracy: 0.001)
        model.syncOffset = 4.75
        model.nudgeSyncOffset(by: 0.5)
        XCTAssertEqual(model.syncOffset, 5, accuracy: 0.001)
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
