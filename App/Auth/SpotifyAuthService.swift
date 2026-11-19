import AuthenticationServices
import Foundation
import Observation
import UIKit

struct SpotifyTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Rinnoviamo con 60 secondi di margine.
    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

enum SpotifyAuthError: LocalizedError, Equatable {
    case missingClientID
    case cancelled
    case cannotStart
    case stateMismatch
    case invalidCallback
    case accessDenied(String)
    case tokenRequestFailed(status: Int, body: String)
    case notSignedIn
    case sessionExpired
    case spotifyAppFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Manca il Client ID Spotify. Inseriscilo in Config/Secrets.xcconfig e ricompila."
        case .cancelled:
            return "Accesso annullato."
        case .cannotStart:
            return "Impossibile aprire la pagina di accesso a Spotify."
        case .stateMismatch, .invalidCallback:
            return "Risposta di Spotify non valida. Riprova."
        case .accessDenied(let reason):
            return reason == "access_denied"
                ? "Hai negato l'accesso a Spotify."
                : "Spotify ha rifiutato l'accesso (\(reason))."
        case .tokenRequestFailed(let status, _):
            return "Spotify non ha concesso l'accesso (errore \(status)). Controlla Client ID e Redirect URI."
        case .notSignedIn:
            return "Non sei collegato a Spotify."
        case .sessionExpired:
            return "La sessione Spotify è scaduta. Ricollegati."
        case .spotifyAppFailed(let detail):
            return "L'accesso tramite l'app Spotify non è riuscito (\(detail)). Prova «Accedi dal browser»."
        }
    }
}

/// Come collegare l'account Spotify.
enum SpotifySignInMethod: Equatable {
    /// Tramite l'app Spotify installata: nessuna password, funziona con account Google, Apple e Facebook.
    case spotifyApp
    /// Tramite la pagina web di Spotify (Safari): email/password o "Continua con Google/Apple/Facebook".
    case browser
}

/// Gestisce login Spotify (OAuth 2.0 Authorization Code + PKCE), salvataggio sicuro e refresh dei token.
@MainActor
@Observable
final class SpotifyAuthService {
    private(set) var tokens: SpotifyTokens?
    /// Metodo di accesso in corso, `nil` se nessun accesso è in corso.
    private(set) var signInInProgress: SpotifySignInMethod?

    var isSigningIn: Bool { signInInProgress != nil }
    var isAuthorized: Bool { tokens != nil }

    @ObservationIgnored private let appAuthenticator = SpotifyAppAuthenticator()
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let tokenKey = "spotify.tokens"
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let anchorProvider = PresentationAnchorProvider()
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private var refreshTask: Task<SpotifyTokens, Error>?

    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.keychain = KeychainStore(service: (Bundle.main.bundleIdentifier ?? "LyricsApple") + ".spotify")
        if let data = try? keychain.read(tokenKey),
           let saved = try? JSONDecoder().decode(SpotifyTokens.self, from: data) {
            tokens = saved
        }
    }

    // MARK: - Login

    /// `true` se sul telefono c'è l'app Spotify (accesso con un tocco).
    var isSpotifyAppInstalled: Bool { SpotifyAppAuthenticator.isSpotifyInstalled }

    func signIn(using method: SpotifySignInMethod) async throws {
        let clientID = AppConfig.spotifyClientID
        guard !clientID.isEmpty else { throw SpotifyAuthError.missingClientID }
        guard signInInProgress == nil else { return }

        signInInProgress = method
        defer { signInInProgress = nil }

        switch method {
        case .spotifyApp:
            store(try await appAuthenticator.authorize(clientID: clientID))
        case .browser:
            try await signInWithBrowser(clientID: clientID)
        }
    }

    /// Annulla un accesso in corso (es. l'utente è tornato senza confermare in Spotify).
    func cancelSignIn() {
        appAuthenticator.cancel()
        webSession?.cancel()
    }

    /// Gestisce il ritorno dall'app Spotify (`lyricsapple://spotify-callback?...`).
    func handleOpenURL(_ url: URL) {
        appAuthenticator.handleOpenURL(url)
    }

    private func signInWithBrowser(clientID: String) async throws {
        let verifier = PKCE.makeVerifier()
        let state = PKCE.makeVerifier(byteCount: 16)

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.spotifyRedirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: AppConfig.spotifyScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw SpotifyAuthError.invalidCallback }

        let callbackURL = try await runWebAuthentication(url: url)
        let code = try Self.extractAuthorizationCode(from: callbackURL, expectedState: state)

        let newTokens = try await requestTokens(
            [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": AppConfig.spotifyRedirectURI,
                "client_id": clientID,
                "code_verifier": verifier,
            ],
            fallbackRefreshToken: nil
        )
        store(newTokens)
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        keychain.delete(tokenKey)
    }

    // MARK: - Token

    /// Restituisce un access token valido, rinnovandolo se necessario (una sola richiesta alla volta).
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw SpotifyAuthError.notSignedIn }
        if !forceRefresh, !current.isExpiringSoon { return current.accessToken }

        if let inFlight = refreshTask {
            return try await inFlight.value.accessToken
        }

        let refreshToken = current.refreshToken
        let task = Task { () throws -> SpotifyTokens in
            try await self.requestTokens(
                [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": AppConfig.spotifyClientID,
                ],
                fallbackRefreshToken: refreshToken
            )
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let newTokens = try await task.value
            store(newTokens)
            return newTokens.accessToken
        } catch let error as SpotifyAuthError {
            // 400/401 sul refresh = token revocato o scaduto definitivamente: serve un nuovo login.
            if case .tokenRequestFailed(let status, _) = error, status == 400 || status == 401 {
                signOut()
                throw SpotifyAuthError.sessionExpired
            }
            throw error
        }
    }

    // MARK: - Helpers

    nonisolated static func extractAuthorizationCode(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw SpotifyAuthError.accessDenied(error) }
        guard value("state") == expectedState else { throw SpotifyAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw SpotifyAuthError.invalidCallback }
        return code
    }

    private func store(_ newTokens: SpotifyTokens) {
        tokens = newTokens
        if let data = try? JSONEncoder().encode(newTokens) {
            try? keychain.save(data, for: tokenKey)
        }
    }

    private func runWebAuthentication(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.spotifyCallbackScheme
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                        continuation.resume(throwing: SpotifyAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: SpotifyAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = anchorProvider
            // false = condivide i cookie di Safari: se in Safari sei già collegato a Spotify o a Google,
            // "Continua con Google" non chiede di nuovo la password.
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                webSession = nil
                continuation.resume(throwing: SpotifyAuthError.cannotStart)
            }
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
    }

    private func requestTokens(_ parameters: [String: String], fallbackRefreshToken: String?) async throws -> SpotifyTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(FormEncoder.encode(parameters).utf8)
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw SpotifyAuthError.tokenRequestFailed(status: status, body: String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(TokenResponse.self, from: data)
        // Spotify può restituire un nuovo refresh token (rotazione) oppure ometterlo.
        guard let refresh = decoded.refreshToken ?? fallbackRefreshToken else {
            throw SpotifyAuthError.invalidCallback
        }
        return SpotifyTokens(
            accessToken: decoded.accessToken,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }
}

/// Fornisce la finestra su cui mostrare il foglio di login.
final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { () -> ASPresentationAnchor in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let scene = scenes.first {
                return UIWindow(windowScene: scene)
            }
            return ASPresentationAnchor()
        }
    }
}
