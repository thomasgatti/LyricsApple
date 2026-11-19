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
        static let showLiveActivity = "showLiveActivity"
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

    /// Live Activity con la riga corrente: schermata di blocco, Dynamic Island e CarPlay (iOS 26).
    var showLiveActivity: Bool {
        didSet {
            UserDefaults.standard.set(showLiveActivity, forKey: Keys.showLiveActivity)
            if !showLiveActivity { liveActivity.end() }
        }
    }

    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private var lineTask: Task<Void, Never>?
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
        self.showLiveActivity = defaults.object(forKey: Keys.showLiveActivity) as? Bool ?? true
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
        lineTask = Task { [weak self] in
            await self?.lineLoop()
        }
        applyIdleTimer()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        lineTask?.cancel()
        lineTask = nil
        applyIdleTimer()
        // In background iOS sospende l'app: lo diciamo nella Live Activity invece di lasciarla ferma.
        if showLiveActivity, let track = currentTrack {
            liveActivity.show(.init(
                title: track.title,
                artist: track.artistLine,
                currentLine: "Apri Lyrics per seguire il testo",
                nextLine: "",
                isPlaying: false,
                hasLyrics: false
            ))
        }
    }

    func reset() {
        stop()
        liveActivity.end()
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

    // MARK: - Live Activity

    /// Aggiorna la Live Activity esattamente quando inizia la riga successiva.
    private func lineLoop() async {
        while !Task.isCancelled {
            let delay = refreshLiveActivity(now: Date())
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0.1) * 1_000_000_000))
        }
    }

    private func refreshLiveActivity(now: Date) -> TimeInterval {
        guard showLiveActivity else { return 1 }
        guard let snapshot, snapshot.track != nil else {
            liveActivity.end()
            return 1
        }
        let result = Self.liveActivityState(
            snapshot: snapshot,
            lyricsState: lyricsState,
            position: playbackPosition(at: now)
        )
        if let state = result.state { liveActivity.show(state) }
        return result.nextChange
    }

    /// Calcola cosa mostrare e fra quanti secondi cambierà (funzione pura, testabile).
    nonisolated static func liveActivityState(
        snapshot: PlaybackSnapshot,
        lyricsState: LyricsState,
        position: TimeInterval
    ) -> (state: LyricsActivityAttributes.ContentState?, nextChange: TimeInterval) {
        guard let track = snapshot.track else { return (nil, 1) }

        var current = ""
        var next = ""
        var hasLyrics = false
        var nextChange: TimeInterval = 1

        switch lyricsState {
        case .loaded(let lyrics) where lyrics.isSynced:
            hasLyrics = true
            let index = lyrics.lineIndex(at: position)
            let following = (index ?? -1) + 1
            current = index.map { lyrics.lines[$0].text } ?? "♪"
            if lyrics.lines.indices.contains(following) {
                next = lyrics.lines[following].text
                if snapshot.isPlaying, let start = lyrics.lines[following].time {
                    nextChange = min(1, max(0.05, start - position + 0.02))
                }
            }
        case .loaded(let lyrics):
            hasLyrics = true
            current = lyrics.lines.first { !$0.text.isEmpty }?.text ?? "♪"
            next = "Testo non sincronizzato: aprilo sull'iPhone"
        case .idle, .loading:
            current = "Cerco il testo…"
        case .instrumental:
            current = "♪ Brano strumentale"
        case .notFound:
            current = "Testo non disponibile"
        case .failed:
            current = "Testo non caricato"
        }

        let state = LyricsActivityAttributes.ContentState(
            title: track.title,
            artist: track.artistLine,
            currentLine: current.isEmpty ? "♪" : current,
            nextLine: next,
            isPlaying: snapshot.isPlaying,
            hasLyrics: hasLyrics
        )
        return (state, nextChange)
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
