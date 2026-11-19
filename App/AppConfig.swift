import Foundation

/// Configurazione statica dell'app.
enum AppConfig {
    /// Client ID Spotify, letto da Info.plist (valorizzato da Config/Secrets.xcconfig).
    static var spotifyClientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deve coincidere ESATTAMENTE con il Redirect URI registrato nella dashboard Spotify.
    static let spotifyRedirectURI = "lyricsapple://spotify-callback"
    static let spotifyCallbackScheme = "lyricsapple"

    /// Permessi minimi: solo lettura del brano in riproduzione.
    static let spotifyScopes = ["user-read-currently-playing", "user-read-playback-state"]

    /// LRCLIB chiede di identificare il client. Sostituisci l'URL con la pagina del tuo progetto, se ne hai una.
    static let lyricsUserAgent = "LyricsApple/1.0 (personal iOS app; https://lrclib.net)"
}
