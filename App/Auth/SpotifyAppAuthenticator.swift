import Foundation
import SpotifyiOS
import UIKit

/// Login tramite l'app Spotify installata (SDK ufficiale Spotify, flusso PKCE senza server).
///
/// L'utente è già collegato nell'app Spotify, qualunque sia il metodo usato per l'account
/// (email, Google, Apple, Facebook): basta toccare "Accetta", senza reinserire credenziali.
@MainActor
final class SpotifyAppAuthenticator: NSObject, SPTSessionManagerDelegate {
    private var sessionManager: SPTSessionManager?
    private var continuation: CheckedContinuation<SpotifyTokens, Error>?

    var isWaitingForSpotify: Bool { continuation != nil }

    /// Richiede "spotify" in LSApplicationQueriesSchemes (Info.plist).
    static var isSpotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func authorize(clientID: String) async throws -> SpotifyTokens {
        finish(.failure(SpotifyAuthError.cancelled)) // chiude un eventuale tentativo precedente

        guard let redirectURL = URL(string: AppConfig.spotifyRedirectURI) else {
            throw SpotifyAuthError.invalidCallback
        }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        let manager = SPTSessionManager(configuration: configuration, delegate: self)
        sessionManager = manager

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.initiateSession(
                with: [.userReadCurrentlyPlaying, .userReadPlaybackState],
                options: .clientOnly,
                campaign: nil
            )
        }
    }

    /// Da chiamare con l'URL `lyricsapple://...` con cui l'app Spotify ci riapre.
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let sessionManager else { return false }
        return sessionManager.application(UIApplication.shared, open: url, options: [:])
    }

    func cancel() {
        finish(.failure(SpotifyAuthError.cancelled))
    }

    private func finish(_ result: Result<SpotifyTokens, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: - SPTSessionManagerDelegate

    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let tokens = SpotifyTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expirationDate
        )
        Task { @MainActor in self.finish(.success(tokens)) }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let message = (error as NSError).localizedDescription
        Task { @MainActor in self.finish(.failure(SpotifyAuthError.spotifyAppFailed(message))) }
    }
}
