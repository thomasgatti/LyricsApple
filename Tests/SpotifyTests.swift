import XCTest
@testable import LyricsApple

final class PKCETests: XCTestCase {
    /// Vettore di prova ufficiale, RFC 7636 Appendice B.
    func testChallengeMatchesRFC7636() {
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testVerifierIsURLSafeAndLongEnough() {
        let verifier = PKCE.makeVerifier()
        XCTAssertTrue((43...128).contains(verifier.count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertNotEqual(verifier, PKCE.makeVerifier())
    }

    func testFormEncoding() {
        XCTAssertEqual(FormEncoder.encode(["b": "x y+z", "a": "lyricsapple://cb"]),
                       "a=lyricsapple%3A%2F%2Fcb&b=x%20y%2Bz")
    }
}

final class AuthCallbackTests: XCTestCase {
    func testExtractsCode() throws {
        let url = URL(string: "lyricsapple://spotify-callback?code=abc&state=s1")!
        XCTAssertEqual(try SpotifyAuthService.extractAuthorizationCode(from: url, expectedState: "s1"), "abc")
    }

    func testRejectsStateMismatch() {
        let url = URL(string: "lyricsapple://spotify-callback?code=abc&state=evil")!
        XCTAssertThrowsError(try SpotifyAuthService.extractAuthorizationCode(from: url, expectedState: "s1")) {
            XCTAssertEqual($0 as? SpotifyAuthError, .stateMismatch)
        }
    }

    func testReportsAccessDenied() {
        let url = URL(string: "lyricsapple://spotify-callback?error=access_denied&state=s1")!
        XCTAssertThrowsError(try SpotifyAuthService.extractAuthorizationCode(from: url, expectedState: "s1")) {
            XCTAssertEqual($0 as? SpotifyAuthError, .accessDenied("access_denied"))
        }
    }
}

final class PlaybackDecodingTests: XCTestCase {
    private let json = """
    {
      "timestamp": 1700000000000,
      "progress_ms": 50000,
      "is_playing": true,
      "currently_playing_type": "track",
      "item": {
        "id": "track123",
        "uri": "spotify:track:track123",
        "name": "Canzone",
        "duration_ms": 200000,
        "artists": [{ "name": "Artista Uno" }, { "name": "Artista Due" }],
        "album": {
          "name": "Album",
          "images": [
            { "url": "https://i.scdn.co/image/small", "width": 64, "height": 64 },
            { "url": "https://i.scdn.co/image/large", "width": 640, "height": 640 }
          ]
        },
        "external_urls": { "spotify": "https://open.spotify.com/track/track123" }
      }
    }
    """

    func testDecodesCurrentlyPlaying() throws {
        let reference = Date(timeIntervalSince1970: 1_000)
        let snapshot = PlaybackSnapshot(dto: try CurrentlyPlayingDTO.decode(Data(json.utf8)), receivedAt: reference)
        let track = try XCTUnwrap(snapshot.track)
        XCTAssertEqual(track.id, "track123")
        XCTAssertEqual(track.title, "Canzone")
        XCTAssertEqual(track.artistLine, "Artista Uno, Artista Due")
        XCTAssertEqual(track.duration, 200)
        XCTAssertEqual(track.artworkURL?.absoluteString, "https://i.scdn.co/image/large")
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.estimatedProgress(at: reference.addingTimeInterval(10)), 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.estimatedProgress(at: reference.addingTimeInterval(1_000)), 200, accuracy: 0.001)
    }

    func testAdsAreNotTreatedAsTracks() throws {
        let ad = #"{"progress_ms": 1000, "is_playing": true, "currently_playing_type": "ad", "item": null}"#
        let snapshot = PlaybackSnapshot(dto: try CurrentlyPlayingDTO.decode(Data(ad.utf8)), receivedAt: Date())
        XCTAssertNil(snapshot.track)
    }

    func testPollsFasterNearTheEndOfATrack() throws {
        let reference = Date()
        let snapshot = PlaybackSnapshot(dto: try CurrentlyPlayingDTO.decode(Data(json.utf8)), receivedAt: reference)
        XCTAssertEqual(NowPlayingViewModel.nextPollDelay(for: snapshot, now: reference), 4)
        XCTAssertEqual(NowPlayingViewModel.nextPollDelay(for: snapshot, now: reference.addingTimeInterval(149)), 1.8, accuracy: 0.01)
    }
}

final class SignInMessagesTests: XCTestCase {
    func testSpotifyAppFailureSuggestsBrowser() {
        let message = SpotifyAuthError.spotifyAppFailed("test").errorDescription ?? ""
        XCTAssertTrue(message.contains("browser"))
    }
}
