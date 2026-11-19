import Foundation

struct LyricLine: Identifiable, Equatable, Codable {
    /// Indice della riga (0...n-1).
    let id: Int
    /// Istante di inizio in secondi; `nil` per testi non sincronizzati.
    let time: TimeInterval?
    let text: String
}

struct Lyrics: Equatable, Codable {
    let lines: [LyricLine]
    let isSynced: Bool
    let source: String

    /// Indice dell'ultima riga iniziata alla posizione data (ricerca binaria). `nil` prima della prima riga.
    func lineIndex(at position: TimeInterval) -> Int? {
        guard isSynced, !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if (lines[mid].time ?? 0) <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    static func plain(_ text: String, source: String) -> Lyrics {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        return Lyrics(lines: lines, isSynced: false, source: source)
    }
}

enum LyricsResult: Equatable, Codable {
    case lyrics(Lyrics)
    case instrumental
    case notFound
}

struct LyricsQuery: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

extension LyricsQuery {
    init(track: Track) {
        self.init(title: track.title, artist: track.primaryArtist, album: track.album, duration: track.duration)
    }
}

/// Qualunque fonte di testi (LRCLIB oggi, un fornitore con licenza domani) implementa questo protocollo.
protocol LyricsProvider: Sendable {
    var name: String { get }
    func fetchLyrics(for query: LyricsQuery) async throws -> LyricsResult
}

enum LyricsError: LocalizedError {
    case rateLimited
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "Troppe richieste al servizio dei testi. Riprova tra poco."
        case .server(let status): return "Il servizio dei testi non è disponibile (errore \(status))."
        }
    }
}
