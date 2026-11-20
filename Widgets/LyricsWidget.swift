import SwiftUI
import WidgetKit

/// Widget "Testo in corso": schermata Home, StandBy, schermata di blocco e (iOS 26/27) CarPlay.
///
/// L'app lascia nell'App Group le righe con l'orario d'inizio; il widget prepara una voce di timeline
/// per ogni riga, così iOS cambia riga da solo all'orario giusto. L'app lo ricarica solo quando cambia
/// qualcosa (brano, pausa, salto).
struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LyricsWidgetSnapshot.kind, provider: LyricsTimelineProvider()) { entry in
            LyricsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [LyricsPalette.background, Color(red: 0.2, green: 0.08, blue: 0.22)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Testo in corso")
        .description("La riga che stai ascoltando su Spotify. Tieni aperta Lyrics in sottofondo.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct LyricsEntry: TimelineEntry {
    enum Content {
        case placeholder
        case nothing
        case status(LyricsWidgetSnapshot, String)
        case line(LyricsWidgetSnapshot, index: Int?)
        case ended(LyricsWidgetSnapshot)
    }

    let date: Date
    let content: Content
}

struct LyricsTimelineProvider: TimelineProvider {
    /// Limite prudente di voci per timeline (un brano ha in genere 40-90 righe).
    private let maxEntries = 180

    func placeholder(in context: Context) -> LyricsEntry {
        LyricsEntry(date: .now, content: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        if context.isPreview, LyricsWidgetSnapshot.load() == nil {
            completion(placeholder(in: context))
        } else {
            completion(Self.entries(for: LyricsWidgetSnapshot.load(), now: .now, limit: 1).first
                ?? LyricsEntry(date: .now, content: .nothing))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        let entries = Self.entries(for: LyricsWidgetSnapshot.load(), now: .now, limit: maxEntries)
        // Non serve richiedere aggiornamenti: è l'app a ricaricare il widget quando cambia qualcosa.
        completion(Timeline(entries: entries, policy: .never))
    }

    static func entries(for snapshot: LyricsWidgetSnapshot?, now: Date, limit: Int) -> [LyricsEntry] {
        guard let snapshot else { return [LyricsEntry(date: now, content: .nothing)] }
        if let status = snapshot.statusLine {
            return [LyricsEntry(date: now, content: .status(snapshot, status))]
        }
        guard snapshot.isPlaying, !snapshot.lines.isEmpty else {
            return [LyricsEntry(date: now, content: .status(snapshot, "♪"))]
        }
        let current = snapshot.lineIndex(at: now)
        var entries = [LyricsEntry(date: now, content: .line(snapshot, index: current))]
        let firstNext = (current ?? -1) + 1
        for index in snapshot.lines.indices where index >= firstNext {
            guard entries.count < limit else { break }
            entries.append(LyricsEntry(date: snapshot.lines[index].start, content: .line(snapshot, index: index)))
        }
        if let end = snapshot.songEnd, end > (entries.last?.date ?? now), entries.count < limit {
            entries.append(LyricsEntry(date: end, content: .ended(snapshot)))
        }
        return entries
    }
}

// MARK: - Viste

struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LyricsEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryLyricsView(entry: entry)
        case .systemMedium:
            WidgetLyricsLayout(entry: entry, currentSize: 22, showsArtist: true, extraLines: true)
        default:
            WidgetLyricsLayout(entry: entry, currentSize: 18, showsArtist: false, extraLines: false)
        }
    }
}

/// Testi da mostrare per una voce di timeline.
private struct WidgetTexts {
    var title = "Lyrics"
    var artist = ""
    var current = ""
    var next = ""
    var afterNext = ""
    var isPlaying = false
    var isMessage = false

    init(_ entry: LyricsEntry) {
        switch entry.content {
        case .placeholder:
            title = "Titolo del brano"
            artist = "Artista"
            current = "La riga che stai ascoltando"
            next = "e quella che arriva dopo"
            isPlaying = true
        case .nothing:
            current = "Niente in riproduzione"
            next = "Apri Lyrics e avvia Spotify"
            isMessage = true
        case let .status(snapshot, text):
            title = snapshot.title
            artist = snapshot.artist
            current = text
            isPlaying = snapshot.isPlaying
            isMessage = true
        case let .line(snapshot, index):
            title = snapshot.title
            artist = snapshot.artist
            current = index == nil ? "♪" : snapshot.text(at: index)
            let next = (index ?? -1) + 1
            self.next = snapshot.text(at: next)
            afterNext = snapshot.text(at: next + 1)
            isPlaying = true
        case let .ended(snapshot):
            title = snapshot.title
            artist = snapshot.artist
            current = "♪"
            next = "Apri Lyrics se il brano è cambiato"
            isMessage = true
        }
    }
}

private struct WidgetLyricsLayout: View {
    let entry: LyricsEntry
    let currentSize: CGFloat
    let showsArtist: Bool
    let extraLines: Bool

    var body: some View {
        let texts = WidgetTexts(entry)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: texts.isPlaying ? "quote.bubble.fill" : "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(LyricsPalette.accent)
                Text(showsArtist && !texts.artist.isEmpty ? "\(texts.title) · \(texts.artist)" : texts.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(texts.current)
                .font(.system(size: texts.isMessage ? currentSize * 0.8 : currentSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
            if !texts.next.isEmpty {
                Text(texts.next)
                    .font(.system(size: currentSize * 0.68, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(extraLines ? 1 : 2)
            }
            if extraLines, !texts.afterNext.isEmpty {
                Text(texts.afterNext)
                    .font(.system(size: currentSize * 0.6, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Schermata di blocco (sotto l'orologio): due righe, in bianco e nero come vuole iOS.
private struct AccessoryLyricsView: View {
    let entry: LyricsEntry

    var body: some View {
        let texts = WidgetTexts(entry)
        VStack(alignment: .leading, spacing: 1) {
            Text(texts.current)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if !texts.next.isEmpty {
                Text(texts.next)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }
}
