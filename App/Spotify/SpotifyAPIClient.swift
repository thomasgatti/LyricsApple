import Foundation

enum SpotifyAPIError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval)
    case forbidden
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Spotify chiede di rallentare: riprovo tra poco."
        case .forbidden:
            return "Spotify ha negato l'accesso. Se l'app è in Development Mode, aggiungi la tua email in User Management nella dashboard Spotify."
        case .server(let status):
            return "Spotify non risponde correttamente (errore \(status))."
        }
    }
}

/// Client minimale della Spotify Web API: legge soltanto il brano in riproduzione.
@MainActor
final class SpotifyAPIClient {
    private let auth: SpotifyAuthService
    private let session: URLSession
    private static let currentlyPlayingURL = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!

    init(auth: SpotifyAuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    /// `nil` se non sta suonando nulla (HTTP 204).
    func currentlyPlaying() async throws -> PlaybackSnapshot? {
        let (data, response, receivedAt) = try await get(Self.currentlyPlayingURL, allowRetry: true)
        switch response.statusCode {
        case 204:
            return nil
        case 200:
            guard !data.isEmpty else { return nil }
            let dto = try CurrentlyPlayingDTO.decode(data)
            return PlaybackSnapshot(dto: dto, receivedAt: receivedAt)
        default:
            throw SpotifyAPIError.server(status: response.statusCode)
        }
    }

    /// Prossime canzoni nella coda di Spotify (al massimo `limit`).
    func upcomingTracks(limit: Int) async throws -> [Track] {
        let (data, response, _) = try await get(Self.queueURL, allowRetry: true)
        guard response.statusCode == 200, !data.isEmpty else { return [] }
        return Array(try QueueDTO.decode(data).upcomingTracks.prefix(limit))
    }

    private static let queueURL = URL(string: "https://api.spotify.com/v1/me/player/queue")!

    private func get(_ url: URL, allowRetry: Bool) async throws -> (Data, HTTPURLResponse, Date) {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let sentAt = Date()
        let (data, response) = try await session.data(for: request)
        let receivedAt = Date()
        guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.server(status: -1) }

        switch http.statusCode {
        case 401 where allowRetry:
            _ = try await auth.validAccessToken(forceRefresh: true)
            return try await get(url, allowRetry: false)
        case 403:
            throw SpotifyAPIError.forbidden
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 5
            throw SpotifyAPIError.rateLimited(retryAfter: retry)
        default:
            // La posizione restituita si riferisce circa a metà del tragitto di rete.
            let midpoint = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
            return (data, http, midpoint)
        }
    }
}
