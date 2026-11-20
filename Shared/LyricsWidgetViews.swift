import SwiftUI
import WidgetKit

// Viste del widget "Testo in corso". Stanno in Shared così le compila anche l'app,
// e i test possono disegnarne le anteprime (vedi Tests/PreviewRenderTests.swift).

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

    /// Una voce per ogni riga, all'orario in cui inizia: iOS le mostra una dopo l'altra.
    static func timeline(for snapshot: LyricsWidgetSnapshot?, now: Date, limit: Int) -> [LyricsEntry] {
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

/// Sfondo del widget.
struct LyricsWidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [LyricsPalette.background, Color(red: 0.2, green: 0.08, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// Legge dal sistema il formato del widget e sceglie il layout.
struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LyricsEntry

    var body: some View {
        LyricsWidgetContent(entry: entry, family: family)
    }
}

struct LyricsWidgetContent: View {
    let entry: LyricsEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryLyricsView(entry: entry)
        case .systemMedium:
            WidgetLyricsLayout(entry: entry, currentSize: 24, showsArtist: true, extraLines: true)
        default: // systemSmall: è il formato usato da CarPlay, testo grande
            WidgetLyricsLayout(entry: entry, currentSize: 23, showsArtist: false, extraLines: false)
        }
    }
}

/// Testi da mostrare per una voce di timeline.
struct WidgetTexts {
    var title = "Lyrics"
    var artist = ""
    var current = ""
    var next = ""
    var afterNext = ""
    var isPlaying = false
    var isMessage = false
    /// Identità delle righe (numero di riga nel testo): servono a iOS per capire che la riga "successiva"
    /// di prima è la "corrente" di adesso, e farla salire di un posto invece di ridisegnare tutto.
    var currentID = -100
    var nextID = -101
    var afterNextID = -102

    struct Row: Identifiable {
        let id: Int
        let text: String
    }

    /// Righe in ordine (corrente, successiva, quella dopo), senza quelle vuote.
    var rows: [Row] {
        [Row(id: currentID, text: current), Row(id: nextID, text: next), Row(id: afterNextID, text: afterNext)]
            .filter { !$0.text.isEmpty }
    }

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
            let next = snapshot.nextNonEmptyIndex(after: index)
            self.next = snapshot.text(at: next)
            afterNext = next.map { snapshot.text(at: snapshot.nextNonEmptyIndex(after: $0)) } ?? ""
            isPlaying = true
            currentID = index ?? -1
            if let next {
                nextID = next
                afterNextID = snapshot.nextNonEmptyIndex(after: next) ?? -102
            }
        case let .ended(snapshot):
            title = snapshot.title
            artist = snapshot.artist
            current = "♪"
            next = "Apri Lyrics se il brano è cambiato"
            isMessage = true
        }
    }
}

struct WidgetLyricsLayout: View {
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
            // Rullo: ogni riga ha la sua identità. Al cambio, la riga corrente esce in alto sfumando,
            // la successiva SALE al suo posto e si ingrandisce, e in fondo ne entra una nuova.
            // Si muove una riga alla volta, non tutto il blocco.
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(texts.rows.prefix(extraLines ? 3 : 2).enumerated()), id: \.element.id) { position, row in
                    Text(row.text)
                        .font(.system(size: size(for: position, isMessage: texts.isMessage),
                                      weight: position == 0 ? .heavy : .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(position == 0 ? 1 : (position == 1 ? 0.5 : 0.28)))
                        .lineLimit(position == 0 ? (extraLines ? 2 : 4) : 1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func size(for position: Int, isMessage: Bool) -> CGFloat {
        switch position {
        case 0: return isMessage ? currentSize * 0.85 : currentSize
        case 1: return currentSize * 0.62
        default: return currentSize * 0.55
        }
    }
}

/// Schermata di blocco (sotto l'orologio): due righe, in bianco e nero come vuole iOS.
struct AccessoryLyricsView: View {
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
