import Foundation

/// Cache su disco dei testi già trovati: utile in galleria o con poco segnale.
struct LyricsCache {
    private let directory: URL

    init(fileManager: FileManager = .default) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("lyrics", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for trackID: String) -> URL {
        let safe = trackID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(trackID.hashValue)
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func load(trackID: String) -> LyricsResult? {
        guard let data = try? Data(contentsOf: fileURL(for: trackID)) else { return nil }
        return try? JSONDecoder().decode(LyricsResult.self, from: data)
    }

    func save(_ result: LyricsResult, trackID: String) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: fileURL(for: trackID), options: .atomic)
    }
}

/// Unisce fonte dei testi e cache.
struct LyricsService {
    let provider: any LyricsProvider
    let cache: LyricsCache

    var sourceName: String { provider.name }

    func lyrics(for track: Track, bypassCache: Bool) async throws -> LyricsResult {
        if !bypassCache, let cached = cache.load(trackID: track.id) {
            return cached
        }
        let result = try await provider.fetchLyrics(for: LyricsQuery(track: track))
        // "Non trovato" non viene salvato: il database cresce e il brano potrebbe arrivare in seguito.
        if result != .notFound {
            cache.save(result, trackID: track.id)
        }
        return result
    }
}
