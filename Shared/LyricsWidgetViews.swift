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
    /// Identità della riga: quando cambia, il blocco di testo scorre verso l'alto.
    var lineID = -2

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
            lineID = index ?? -1
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
            // Blocco righe: grandezza fissa (niente "salti" tra una riga e l'altra);
            // a ogni nuova riga entra dal basso e spinge su la precedente, come un rullo.
            VStack(alignment: .leading, spacing: 5) {
                Text(texts.current)
                    .font(.system(size: texts.isMessage ? currentSize * 0.85 : currentSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(extraLines ? 2 : 3)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                if !texts.next.isEmpty {
                    Text(texts.next)
                        .font(.system(size: currentSize * 0.62, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(extraLines ? 1 : 2)
                }
                if extraLines, !texts.afterNext.isEmpty {
                    Text(texts.afterNext)
                        .font(.system(size: currentSize * 0.55, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(texts.lineID)
            .transition(.push(from: .bottom))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
