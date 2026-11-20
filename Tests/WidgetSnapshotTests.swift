import XCTest
@testable import LyricsApple

final class WidgetSnapshotTests: XCTestCase {
    private let track = Track(id: "t", title: "Canzone", artists: ["Artista"], album: "A",
                              duration: 200, artworkURL: nil, spotifyURL: nil)
    private let lyrics = Lyrics(
        lines: [
            LyricLine(id: 0, time: 10, text: "Prima"),
            LyricLine(id: 1, time: 15, text: ""),
            LyricLine(id: 2, time: 20, text: "Terza"),
        ],
        isSynced: true,
        source: "test"
    )

    private func playback(_ playing: Bool) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, isPlaying: playing, progress: 0, referenceDate: Date())
    }

    func testPlayingSnapshotHasAbsoluteLineTimes() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let widget = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(
            snapshot: playback(true), lyricsState: .loaded(lyrics), position: 12, now: now))
        XCTAssertNil(widget.statusLine)
        XCTAssertEqual(widget.lines.count, 3)
        XCTAssertEqual(widget.lines[0].start.timeIntervalSince(now), -2, accuracy: 0.001)
        XCTAssertEqual(widget.lines[2].start.timeIntervalSince(now), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(widget.songEnd).timeIntervalSince(now), 188, accuracy: 0.001)

        XCTAssertEqual(widget.lineIndex(at: now), 0)
        XCTAssertEqual(widget.text(at: 0), "Prima")
        XCTAssertEqual(widget.text(at: 1), "♪")
        XCTAssertNil(widget.lineIndex(at: now.addingTimeInterval(-5)))
    }

    func testPausedAndStatusSnapshots() throws {
        let now = Date()
        let paused = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(
            snapshot: playback(false), lyricsState: .loaded(lyrics), position: 21, now: now))
        XCTAssertEqual(paused.statusLine, "Terza")
        XCTAssertTrue(paused.lines.isEmpty)

        let missing = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(
            snapshot: playback(true), lyricsState: .notFound, position: 0, now: now))
        XCTAssertEqual(missing.statusLine, "Testo non disponibile")

        XCTAssertNil(NowPlayingViewModel.widgetSnapshot(snapshot: nil, lyricsState: .idle, position: 0, now: now))
    }

    func testSmallDriftDoesNotReloadButJumpsDo() throws {
        let now = Date()
        let a = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(snapshot: playback(true), lyricsState: .loaded(lyrics), position: 12, now: now))
        let b = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(snapshot: playback(true), lyricsState: .loaded(lyrics), position: 12.3, now: now))
        let jumped = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(snapshot: playback(true), lyricsState: .loaded(lyrics), position: 60, now: now))
        XCTAssertTrue(a.isEquivalent(to: b))
        XCTAssertFalse(a.isEquivalent(to: jumped))
    }

    func testNextLineSkipsEmptyLines() throws {
        let widget = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(
            snapshot: playback(true), lyricsState: .loaded(lyrics), position: 12, now: Date()))
        XCTAssertEqual(widget.nextNonEmptyIndex(after: 0), 2) // la riga 1 è vuota
        XCTAssertEqual(widget.nextNonEmptyIndex(after: nil), 0)
        XCTAssertNil(widget.nextNonEmptyIndex(after: 2))
    }

    func testSilentAudioIsValidWAV() {
        let wav = BackgroundKeepAlive.silentWAV
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(wav.count, 44 + 16_000)
    }

    func testStaleLiveActivityStopsBarsAndAsksToOpenApp() {
        let state = LyricsActivityAttributes.ContentState(
            title: "T", artist: "A", currentLine: "Riga", nextLine: "Dopo", isPlaying: true, hasLyrics: true)
        let stale = state.staleVersion()
        XCTAssertFalse(stale.isPlaying)
        XCTAssertEqual(stale.currentLine, "Riga")
        XCTAssertTrue(stale.nextLine.contains("apri Lyrics"))
    }

    func testSaveAndLoadRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WidgetSnapshotTests"))
        defer { defaults.removePersistentDomain(forName: "WidgetSnapshotTests") }
        let snapshot = try XCTUnwrap(NowPlayingViewModel.widgetSnapshot(
            snapshot: playback(true), lyricsState: .loaded(lyrics), position: 12, now: Date()))
        LyricsWidgetSnapshot.save(snapshot, to: defaults)
        XCTAssertEqual(LyricsWidgetSnapshot.load(from: defaults), snapshot)
        LyricsWidgetSnapshot.save(nil, to: defaults)
        XCTAssertNil(LyricsWidgetSnapshot.load(from: defaults))
    }

    func testReadsAppGroupFromProvisioningProfile() {
        let profile = """
        garbage-before\u{0}<?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key>
        <array><string>group.com.esempio.lyricsapple.ABCDE12345</string></array>
        </dict></dict></plist>\u{0}garbage-after
        """
        XCTAssertEqual(AppGroup.parseGroups(fromProfile: Data(profile.utf8)),
                       ["group.com.esempio.lyricsapple.ABCDE12345"])
        XCTAssertEqual(AppGroup.parseGroups(fromProfile: Data("niente".utf8)), [])
    }
}
