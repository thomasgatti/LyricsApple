import Foundation

/// Testi da LRCLIB (https://lrclib.net): database aperto e gratuito, senza chiave API.
/// Documentazione: https://lrclib.net/docs
struct LRCLIBProvider: LyricsProvider {
    let name = "LRCLIB"
    private let session: URLSession
    private let baseURL = URL(string: "https://lrclib.net/api")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct Record: Decodable, Equatable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult {
        // 1) Corrispondenza esatta (titolo, artista, album, durata ±2 s).
        if let record = try await getExact(title: query.title, artist: query.artist, album: query.album, duration: query.duration),
           let result = Self.result(from: record) {
            return result
        }
        // 2) Titolo "pulito" (senza "- Remastered", "(feat. ...)").
        let cleanedTitle = TitleCleaner.clean(query.title)
        if cleanedTitle != query.title,
           let record = try await getExact(title: cleanedTitle, artist: query.artist, album: nil, duration: query.duration),
           let result = Self.result(from: record) {
            return result
        }
        // 3) Ricerca e scelta del candidato migliore.
        let candidates = try await search(title: cleanedTitle, artist: query.artist)
        if let best = Self.bestMatch(in: candidates, for: query), let result = Self.result(from: best) {
            return result
        }
        return .notFound
    }

    // MARK: - Rete

    private func getExact(title: String, artist: String, album: String?, duration: TimeInterval) async throws -> Record? {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration >= 1 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        let (data, status) = try await request(path: "get", items: items)
        if status == 404 { return nil }
        guard status == 200 else { throw LyricsError.server(status: status) }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func search(title: String, artist: String) async throws -> [Record] {
        let (data, status) = try await request(path: "search", items: [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ])
        if status == 404 { return [] }
        guard status == 200 else { throw LyricsError.server(status: status) }
        return try JSONDecoder().decode([Record].self, from: data)
    }

    private func request(path: String, items: [URLQueryItem]) async throws -> (Data, Int) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(AppConfig.lyricsUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 429 { throw LyricsError.rateLimited }
        return (data, status)
    }

    // MARK: - Logica di scelta (testabile)

    static func result(from record: Record) -> LyricsResult? {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .lyrics(Lyrics(lines: lines, isSynced: true, source: "LRCLIB")) }
        }
        if let plain = record.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .lyrics(.plain(plain, source: "LRCLIB"))
        }
        if record.instrumental == true { return .instrumental }
        return nil
    }

    static func bestMatch(in records: [Record], for query: LyricsQuery) -> Record? {
        let wantedArtist = TitleCleaner.normalize(query.artist)
        let wantedTitle = TitleCleaner.normalize(TitleCleaner.clean(query.title))

        let scored: [(Record, Double)] = records.compactMap { record in
            guard result(from: record) != nil else { return nil }

            let artist = TitleCleaner.normalize(record.artistName ?? "")
            guard !artist.isEmpty, !wantedArtist.isEmpty,
                  artist.contains(wantedArtist) || wantedArtist.contains(artist) else { return nil }

            var score = 0.0
            if let duration = record.duration, query.duration > 0 {
                let difference = abs(duration - query.duration)
                guard difference <= 4 else { return nil }
                score -= difference
            }
            if !(record.syncedLyrics ?? "").isEmpty { score += 10 }
            if TitleCleaner.normalize(record.trackName ?? "") == wantedTitle { score += 5 }
            return (record, score)
        }
        return scored.max { $0.1 < $1.1 }?.0
    }
}

/// Normalizza i titoli Spotify per la ricerca dei testi.
enum TitleCleaner {
    private static let suffixKeywords = [
        "remaster", "live", "version", "edit", "mix", "mono", "stereo",
        "acoustic", "demo", "deluxe", "bonus", "feat", "from ", "recorded", "session",
    ]
    private static let featMarkers = ["(feat.", "(ft.", "(featuring", "(with ", "[feat.", "[ft."]

    static func clean(_ title: String) -> String {
        var result = title
        if let dash = result.range(of: " - ") {
            let suffix = result[dash.upperBound...].lowercased()
            if suffixKeywords.contains(where: { suffix.contains($0) }) {
                result = String(result[..<dash.lowerBound])
            }
        }
        for marker in featMarkers {
            if let range = result.range(of: marker, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ text: String) -> String {
        var value = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("the ") { value = String(value.dropFirst(4)) }
        return value
    }
}
