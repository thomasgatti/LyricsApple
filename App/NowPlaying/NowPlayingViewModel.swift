import Foundation
import Observation
import UIKit

/// Cuore dell'app: interroga Spotify, rileva il cambio di brano, carica i testi e calcola la riga corrente.
@MainActor
@Observable
final class NowPlayingViewModel {
    enum PlaybackState: Equatable {
        case loading
        case nothingPlaying
        case playing(PlaybackSnapshot)
    }

    enum LyricsState: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case instrumental
        case notFound
        case failed(String)
    }

    private enum Keys {
        static let syncOffset = "syncOffset"
        static let keepScreenOn = "keepScreenOn"
    }

    private(set) var playback: PlaybackState = .loading
    private(set) var lyricsState: LyricsState = .idle
    /// Avviso non bloccante (offline, limiti di richieste, ...).
    private(set) var bannerMessage: String?

    /// Secondi di anticipo del testo (positivo = il testo scorre prima).
    var syncOffset: TimeInterval {
        didSet { UserDefaults.standard.set(syncOffset, forKey: Keys.syncOffset) }
    }

    var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)
            applyIdleTimer()
        }
    }

    @ObservationIgnored private let auth: SpotifyAuthService
    @ObservationIgnored private let api: SpotifyAPIClient
    @ObservationIgnored private let lyricsService: LyricsService
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var consecutiveErrors = 0

    init(auth: SpotifyAuthService, lyricsProvider: any LyricsProvider = LRCLIBProvider()) {
        self.auth = auth
        self.api = SpotifyAPIClient(auth: auth)
        self.lyricsService = LyricsService(provider: lyricsProvider, cache: LyricsCache())
        let defaults = UserDefaults.standard
        self.syncOffset = defaults.double(forKey: Keys.syncOffset)
        self.keepScreenOn = defaults.object(forKey: Keys.keepScreenOn) as? Bool ?? true
    }

    // MARK: - Stato derivato

    var snapshot: PlaybackSnapshot? {
        if case .playing(let snapshot) = playback { return snapshot }
        return nil
    }

    var currentTrack: Track? { snapshot?.track }
    var lyricsSourceName: String { lyricsService.sourceName }

    func playbackPosition(at date: Date) -> TimeInterval {
        (snapshot?.estimatedProgress(at: date) ?? 0) + syncOffset
    }

    func currentLineIndex(at date: Date) -> Int? {
        guard case .loaded(let lyrics) = lyricsState else { return nil }
        return lyrics.lineIndex(at: playbackPosition(at: date))
    }

    // MARK: - Ciclo di aggiornamento

    func start() {
        guard pollTask == nil, auth.isAuthorized else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
        applyIdleTimer()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        applyIdleTimer()
    }

    func reset() {
        stop()
        lyricsTask?.cancel()
        currentTrackID = nil
        playback = .loading
        lyricsState = .idle
        bannerMessage = nil
    }

    func refreshNow() {
        Task { _ = await pollOnce() }
    }

    func retryLyrics() {
        guard let track = currentTrack else { return }
        loadLyrics(for: track, bypassCache: true)
    }

    func networkRestored() {
        bannerMessage = nil
        if case .failed = lyricsState { retryLyrics() }
        refreshNow()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            let delay = await pollOnce()
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0.5) * 1_000_000_000))
        }
    }

    /// Esegue una lettura e restituisce dopo quanti secondi ripetere.
    private func pollOnce() async -> TimeInterval {
        do {
            let snapshot = try await api.currentlyPlaying()
            consecutiveErrors = 0
            bannerMessage = nil

            guard let snapshot, let track = snapshot.track else {
                playback = .nothingPlaying
                return 5
            }
            playback = .playing(snapshot)
            if track.id != currentTrackID {
                currentTrackID = track.id
                loadLyrics(for: track, bypassCache: false)
            }
            return Self.nextPollDelay(for: snapshot, now: Date())
        } catch let error as SpotifyAuthError {
            if error == .sessionExpired || error == .notSignedIn {
                reset()
                auth.signOut()
                return 60
            }
            return registerFailure(error)
        } catch SpotifyAPIError.rateLimited(let retryAfter) {
            bannerMessage = SpotifyAPIError.rateLimited(retryAfter: retryAfter).errorDescription
            return max(retryAfter, 5)
        } catch is CancellationError {
            return 1
        } catch {
            return registerFailure(error)
        }
    }

    private func registerFailure(_ error: Error) -> TimeInterval {
        if (error as? URLError)?.code == .cancelled { return 1 }
        consecutiveErrors += 1
        bannerMessage = ErrorMessages.userFacing(error)
        // Backoff esponenziale: 3, 6, 12, 24, 30 secondi.
        return min(30, 3 * pow(2, Double(min(consecutiveErrors - 1, 4))))
    }

    /// Più frequente vicino alla fine del brano, così il testo cambia subito col pezzo successivo.
    nonisolated static func nextPollDelay(for snapshot: PlaybackSnapshot, now: Date) -> TimeInterval {
        guard snapshot.isPlaying, let track = snapshot.track else { return 5 }
        let remaining = track.duration - snapshot.estimatedProgress(at: now)
        return min(4, max(1, remaining + 0.8))
    }

    // MARK: - Testi

    private func loadLyrics(for track: Track, bypassCache: Bool) {
        lyricsTask?.cancel()
        lyricsState = .loading
        let service = lyricsService
        lyricsTask = Task { [weak self] in
            do {
                let result = try await service.lyrics(for: track, bypassCache: bypassCache)
                guard let self, !Task.isCancelled, self.currentTrackID == track.id else { return }
                switch result {
                case .lyrics(let lyrics): self.lyricsState = .loaded(lyrics)
                case .instrumental: self.lyricsState = .instrumental
                case .notFound: self.lyricsState = .notFound
                }
            } catch {
                guard let self, !Task.isCancelled, self.currentTrackID == track.id else { return }
                self.lyricsState = .failed(ErrorMessages.userFacing(error))
            }
        }
    }

    // MARK: - Schermo

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && pollTask != nil
    }
}
