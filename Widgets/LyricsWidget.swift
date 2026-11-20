import SwiftUI
import WidgetKit

/// Widget "Testo in corso": schermata Home, StandBy, schermata di blocco e (iOS 26/27) CarPlay.
///
/// L'app lascia nell'App Group le righe con l'orario d'inizio; il widget prepara una voce di timeline
/// per ogni riga, così iOS cambia riga da solo all'orario giusto. L'app lo ricarica solo quando cambia
/// qualcosa (brano, pausa, salto). Le viste sono in `Shared/LyricsWidgetViews.swift`.
struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LyricsWidgetSnapshot.kind, provider: LyricsTimelineProvider()) { entry in
            LyricsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LyricsWidgetBackground()
                }
        }
        .configurationDisplayName("Testo in corso")
        .description("La riga che stai ascoltando su Spotify. Tieni aperta Lyrics in sottofondo.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct LyricsTimelineProvider: TimelineProvider {
    /// Limite prudente di voci per timeline (4 canzoni da 40-90 righe ciascuna).
    private let maxEntries = 500

    func placeholder(in context: Context) -> LyricsEntry {
        LyricsEntry(date: .now, content: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsEntry) -> Void) {
        if context.isPreview, LyricsWidgetSnapshot.load() == nil {
            completion(placeholder(in: context))
        } else {
            completion(LyricsEntry.timeline(for: LyricsWidgetSnapshot.load(), now: .now, limit: 1).first
                ?? LyricsEntry(date: .now, content: .nothing))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsEntry>) -> Void) {
        let entries = LyricsEntry.timeline(for: LyricsWidgetSnapshot.load(), now: .now, limit: maxEntries)
        // Non serve richiedere aggiornamenti: è l'app a ricaricare il widget quando cambia qualcosa.
        completion(Timeline(entries: entries, policy: .never))
    }
}
