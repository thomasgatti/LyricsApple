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
