import ActivityKit
import SwiftUI

/// Dati della Live Activity "Lyrics", condivisi tra l'app e l'estensione widget.
/// La Live Activity compare sulla schermata di blocco, nella Dynamic Island e (iOS 26) su CarPlay.
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        /// Riga cantata in questo momento (o un messaggio di stato).
        var currentLine: String
        /// Riga successiva, mostrata più tenue.
        var nextLine: String
        var isPlaying: Bool
        var hasLyrics: Bool
        /// Riga appena cantata (sopra, sfumata).
        var previousLine: String = ""
        /// Riga dopo la successiva (sotto, molto sfumata).
        var afterNextLine: String = ""
        /// Numero della riga corrente: quando cambia, il testo "scorre" verso l'alto.
        var lineIndex: Int = -1
        /// Inizio e fine della riga corrente: la barra sotto la riga si riempie da sola.
        var lineStart: Date?
        var lineEnd: Date?
        /// Inizio e fine del brano: barra di avanzamento che si muove da sola.
        var songStart: Date?
        var songEnd: Date?
    }
}

extension LyricsActivityAttributes.ContentState {
    /// Versione da mostrare quando Lyrics non manda aggiornamenti da troppo (iOS l'ha sospesa):
    /// niente barre che avanzano e un invito ad aprire l'app, invece di righe che non corrispondono.
    func staleVersion() -> Self {
        var copy = self
        copy.isPlaying = false
        copy.nextLine = "Testo fermo: apri Lyrics per riprendere"
        copy.afterNextLine = ""
        return copy
    }

    /// Uguale a parte piccole differenze negli orari (dovute ai controlli periodici su Spotify):
    /// in quel caso non serve aggiornare la Live Activity.
    func isEquivalent(to other: Self, tolerance: TimeInterval = 0.75) -> Bool {
        func close(_ a: Date?, _ b: Date?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): abs(a.timeIntervalSince(b)) < tolerance
            default: false
            }
        }
        var lhs = self, rhs = other
        lhs.lineStart = nil; lhs.lineEnd = nil; lhs.songStart = nil; lhs.songEnd = nil
        rhs.lineStart = nil; rhs.lineEnd = nil; rhs.songStart = nil; rhs.songEnd = nil
        return lhs == rhs
            && close(lineStart, other.lineStart) && close(lineEnd, other.lineEnd)
            && close(songStart, other.songStart) && close(songEnd, other.songEnd)
    }
}

/// Colori comuni ad app ed estensione.
enum LyricsPalette {
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.38)
    static let accentSecondary = Color(red: 1.0, green: 0.37, blue: 0.47)
    static let background = Color(red: 0.09, green: 0.08, blue: 0.19)
    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary], startPoint: .leading, endPoint: .trailing
    )
}
