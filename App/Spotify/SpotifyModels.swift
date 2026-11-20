import Foundation

/// Brano normalizzato, indipendente dal formato JSON di Spotify.
struct Track: Equatable, Codable, Identifiable {
    let id: String
    let title: String
    let artists: [String]
    let album: String
    let duration: TimeInterval
    let artworkURL: URL?
    let spotifyURL: URL?

    var artistLine: String { artists.joined(separator: ", ") }
    var primaryArtist: String { artists.first ?? "" }
}

/// Stato di riproduzione in un istante preciso; la posizione viene stimata localmente tra un polling e l'altro.
struct PlaybackSnapshot: Equatable {
    let track: Track?
    let isPlaying: Bool
    /// Posizione nel brano (secondi) al momento `referenceDate`.
    let progress: TimeInterval
    let referenceDate: Date

    func estimatedProgress(at date: Date) -> TimeInterval {
        guard let track else { return 0 }
        let raw = isPlaying ? progress + date.timeIntervalSince(referenceDate) : progress
        return min(max(0, raw), track.duration)
    }
}

// MARK: - DTO JSON (GET /v1/me/player/currently-playing)

struct CurrentlyPlayingDTO: Decodable {
    let progressMs: Int?
    let isPlaying: Bool?
    let currentlyPlayingType: String?
    let item: ItemDTO?

    struct ItemDTO: Decodable {
        let id: String?
        let uri: String?
        /// "track" o "episode" (podcast).
        let type: String?
        let name: String
        let durationMs: Int?
        let artists: [ArtistDTO]?
        let album: AlbumDTO?
        let externalUrls: [String: String]?
    }

    struct ArtistDTO: Decodable { let name: String }

    struct AlbumDTO: Decodable {
        let name: String?
        let images: [ImageDTO]?
    }

    struct ImageDTO: Decodable {
        let url: String
        let width: Int?
    }

    static func decode(_ data: Data) throws -> CurrentlyPlayingDTO {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CurrentlyPlayingDTO.self, from: data)
    }
}

extension Track {
    init(item: CurrentlyPlayingDTO.ItemDTO) {
        let images = item.album?.images ?? []
        let artwork = images.max { ($0.width ?? 0) < ($1.width ?? 0) }
        self.init(
            id: item.id ?? item.uri ?? "local:\(item.name)",
            title: item.name,
            artists: item.artists?.map(\.name) ?? [],
            album: item.album?.name ?? "",
            duration: TimeInterval(item.durationMs ?? 0) / 1000,
            artworkURL: artwork.flatMap { URL(string: $0.url) },
            spotifyURL: item.externalUrls?["spotify"].flatMap { URL(string: $0) }
        )
    }
}

// MARK: - DTO JSON (GET /v1/me/player/queue)

/// Coda di riproduzione: le canzoni che Spotify suonerà dopo quella attuale.
struct QueueDTO: Decodable {
    let queue: [CurrentlyPlayingDTO.ItemDTO]?

    /// Solo brani musicali, nell'ordine in cui verranno suonati.
    var upcomingTracks: [Track] {
        (queue ?? [])
            .filter { ($0.type ?? "track") == "track" && ($0.durationMs ?? 0) > 0 }
            .map(Track.init(item:))
    }

    static func decode(_ data: Data) throws -> QueueDTO {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(QueueDTO.self, from: data)
    }
}

extension PlaybackSnapshot {
    init(dto: CurrentlyPlayingDTO, receivedAt: Date) {
        var track: Track?
        // Gestiamo solo brani musicali (non podcast o pubblicità).
        if let item = dto.item, dto.currentlyPlayingType == nil || dto.currentlyPlayingType == "track" {
            track = Track(item: item)
        }
        self.init(
            track: track,
            isPlaying: dto.isPlaying ?? false,
            progress: TimeInterval(dto.progressMs ?? 0) / 1000,
            referenceDate: receivedAt
        )
    }
}
