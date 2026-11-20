import Foundation

/// App Group condiviso tra l'app e il widget: è lo "scaffale" dove l'app lascia il testo per il widget.
///
/// Con un Apple ID gratuito l'App Group lo registra il programma di installazione (iloader) e il nome
/// potrebbe non essere esattamente quello previsto: per questo lo leggiamo dal profilo di installazione
/// (`embedded.mobileprovision`) e solo in mancanza usiamo il nome scritto in Info.plist.
enum AppGroup {
    static let identifier: String? = {
        if let fromProfile = groupsFromProvisioningProfile().first { return fromProfile }
        return Bundle.main.object(forInfoDictionaryKey: "LyricsAppGroup") as? String
    }()

    static var defaults: UserDefaults? {
        identifier.flatMap { UserDefaults(suiteName: $0) }
    }

    static func groupsFromProvisioningProfile() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return parseGroups(fromProfile: data)
    }

    /// Il profilo è un plist XML dentro una busta firmata: estraiamo solo la parte XML.
    static func parseGroups(fromProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return [] }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups.filter { !$0.contains("*") }
    }
}

/// Quello che il widget deve sapere: brano e righe del testo con l'orario esatto in cui iniziano.
/// Con questi orari il widget prepara da solo la sequenza delle righe, senza che l'app debba aggiornarlo a ogni riga.
struct LyricsWidgetSnapshot: Codable, Equatable {
    struct Line: Codable, Equatable {
        var start: Date
        var text: String
        /// Titolo e artista se la riga appartiene a una canzone successiva (nil = canzone attuale).
        var title: String? = nil
        var artist: String? = nil
    }

    static let kind = "LyricsWidget"
    private static let storageKey = "widgetSnapshot"

    var trackID: String
    var title: String
    var artist: String
    var isPlaying: Bool
    /// Messaggio fisso (pausa, testo non sincronizzato, testo non trovato...). Se presente, `lines` è vuoto.
    var statusLine: String?
    var lines: [Line]
    var songEnd: Date?

    // MARK: Lettura / scrittura nell'App Group

    static func load(from defaults: UserDefaults? = AppGroup.defaults) -> LyricsWidgetSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func save(_ snapshot: LyricsWidgetSnapshot?, to defaults: UserDefaults? = AppGroup.defaults) {
        guard let defaults else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    // MARK: Calcoli

    /// Indice della riga cantata all'istante `date` (nil = prima della prima riga).
    func lineIndex(at date: Date) -> Int? {
        lines.lastIndex { $0.start <= date }
    }

    func text(at index: Int?) -> String {
        guard let index, lines.indices.contains(index) else { return "" }
        return lines[index].text.isEmpty ? "♪" : lines[index].text
    }

    /// Prima riga con del testo dopo `index` (le righe vuote, pause strumentali, vengono saltate).
    func nextNonEmptyIndex(after index: Int?) -> Int? {
        let from = (index ?? -1) + 1
        guard from < lines.count else { return nil }
        return lines[from...].firstIndex { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Uguale a parte piccole differenze di orario: in quel caso non serve ricaricare il widget.
    func isEquivalent(to other: LyricsWidgetSnapshot, tolerance: TimeInterval = 1) -> Bool {
        guard trackID == other.trackID, title == other.title, artist == other.artist,
              isPlaying == other.isPlaying, statusLine == other.statusLine,
              lines.count == other.lines.count,
              lines.map(\.text) == other.lines.map(\.text)
        else { return false }
        guard let a = lines.first?.start, let b = other.lines.first?.start else { return true }
        return abs(a.timeIntervalSince(b)) < tolerance
    }
}
