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
        static let liveActivityLead = "liveActivityLead"
    }

    /// Anticipo predefinito per schermata di blocco e CarPlay: copre il tempo che iOS impiega a ridisegnarle.
    static let defaultLiveActivityLead: TimeInterval = 0.5

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
            if !showLiveActivity {
                liveActivity.end()
                keepAlive.stop()
            } else if !isInBackground, auth.isAuthorized {
                keepAlive.start()
            }
        }
    }

    /// Secondi di anticipo in più, solo per schermata di blocco e CarPlay (che si aggiornano con un po' di ritardo).
    var liveActivityLead: TimeInterval {
        didSet { UserDefaults.standard.set(liveActivityLead, forKey: Keys.liveActivityLead) }
    }

    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let widgetPublisher = WidgetPublisher()
    @ObservationIgnored private let keepAlive = BackgroundKeepAlive()
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var nothingPlayingSince: Date?
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
        self.liveActivityLead = defaults.object(forKey: Keys.liveActivityLead) as? Double ?? Self.defaultLiveActivityLead
    }

    /// Tasti rapidi nella schermata del testo: sposta l'anticipo di `delta` secondi (limitato a ±5 s).
    func nudgeSyncOffset(by delta: TimeInterval) {
        let rounded = ((syncOffset + delta) * 4).rounded() / 4 // passi di 0,25 s
        syncOffset = min(5, max(-5, rounded))
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

    /// L'app torna in primo piano: riparte il controllo su Spotify e (con la Live Activity) l'audio silenzioso.
    func enterForeground() {
        isInBackground = false
        // L'audio silenzioso va avviato ORA, ad app aperta: iOS spesso non permette di avviarlo
        // quando l'app è già passata in background, e in quel caso Lyrics verrebbe sospesa
        // (Live Activity ferma su una riga). È un audio "mixWithOthers": non disturba Spotify.
        if showLiveActivity, auth.isAuthorized {
            keepAlive.start()
        } else {
            keepAlive.stop()
        }
        // Le richieste di aggiornamento fatte in background iOS può rimandarle o ignorarle:
        // appena l'app è aperta ricarichiamo comunque il widget.
        widgetPublisher.invalidate()
        // Live Activity ricreata da zero: se iOS aveva smesso di aggiornarla, ora riparte.
        liveActivity.restart()
        start()
        applyIdleTimer()
    }

    // MARK: - Diagnostica (Impostazioni)

    /// Ultima volta che, con l'app in background, abbiamo chiesto a Spotify cosa suona.
    private(set) var lastBackgroundPoll: Date?
    var keepAliveRestarts: Int { keepAlive.restartCount }
    var appGroupName: String? { widgetPublisher.isAvailable ? AppGroup.identifier : nil }
    var lastWidgetReload: Date? { widgetPublisher.lastReload }
    var liveActivityLastUpdate: Date? { liveActivity.lastUpdate }
    var liveActivityError: String? { liveActivity.lastError }
    var liveActivitySummary: String {
        "\(liveActivity.stateDescription) · \(liveActivity.systemActivityCount) sul sistema"
    }

    /// iPhone bloccato o app in background: con la Live Activity attiva continuiamo a seguire il testo.
    func enterBackground() {
        isInBackground = true
        guard showLiveActivity, auth.isAuthorized else {
            stop()
            return
        }
        start()
        keepAlive.start()
        if !keepAlive.isRunning { stop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        lineTask?.cancel()
        lineTask = nil
        keepAlive.stop()
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
        widgetPublisher.publish(nil)
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
            let now = Date()
            publishWidget(now: now)
            let delay = refreshLiveActivity(now: now)
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
            position: playbackPosition(at: now) + liveActivityLead,
            now: now
        )
        if let state = result.state { liveActivity.show(state) }
        return result.nextChange
    }

    private func publishWidget(now: Date) {
        widgetPublisher.publish(Self.widgetSnapshot(
            snapshot: snapshot,
            lyricsState: lyricsState,
            position: playbackPosition(at: now) + liveActivityLead,
            now: now
        ))
    }

    /// Dati per il widget: righe con l'orario (sull'orologio dell'iPhone) in cui iniziano.
    nonisolated static func widgetSnapshot(
        snapshot: PlaybackSnapshot?,
        lyricsState: LyricsState,
        position: TimeInterval,
        now: Date
    ) -> LyricsWidgetSnapshot? {
        guard let snapshot, let track = snapshot.track else { return nil }
        let playStart = now.addingTimeInterval(-position)
        var widget = LyricsWidgetSnapshot(
            trackID: track.id,
            title: track.title,
            artist: track.artistLine,
            isPlaying: snapshot.isPlaying,
            statusLine: nil,
            lines: [],
            songEnd: snapshot.isPlaying ? playStart.addingTimeInterval(max(track.duration, position + 1)) : nil
        )
        switch lyricsState {
        case .loaded(let lyrics) where lyrics.isSynced:
            if snapshot.isPlaying {
                widget.lines = lyrics.lines.compactMap { line in
                    line.time.map { .init(start: playStart.addingTimeInterval($0), text: line.text) }
                }
            } else {
                let index = lyrics.lineIndex(at: position)
                let text = index.map { lyrics.lines[$0].text } ?? ""
                widget.statusLine = text.isEmpty ? "In pausa" : text
            }
        case .loaded(let lyrics):
            widget.statusLine = lyrics.lines.first { !$0.text.isEmpty }?.text ?? "♪"
        case .idle, .loading:
            widget.statusLine = "Cerco il testo…"
        case .instrumental:
            widget.statusLine = "♪ Brano strumentale"
        case .notFound:
            widget.statusLine = "Testo non disponibile"
        case .failed:
            widget.statusLine = "Testo non caricato"
        }
        return widget
    }

    /// Calcola cosa mostrare e fra quanti secondi cambierà (funzione pura, testabile).
    nonisolated static func liveActivityState(
        snapshot: PlaybackSnapshot,
        lyricsState: LyricsState,
        position: TimeInterval,
        now: Date = Date()
    ) -> (state: LyricsActivityAttributes.ContentState?, nextChange: TimeInterval) {
        guard let track = snapshot.track else { return (nil, 1) }

        var current = ""
        var next = ""
        var previous = ""
        var afterNext = ""
        var lineIndex = -1
        var lineStart: Date?
        var lineEnd: Date?
        var hasLyrics = false
        var nextChange: TimeInterval = 1

        // Istante (sull'orologio dell'iPhone) in cui il brano è partito: serve alle barre che si muovono da sole.
        let playStart = now.addingTimeInterval(-position)
        let songStart: Date? = snapshot.isPlaying ? playStart : nil
        let songEnd: Date? = snapshot.isPlaying ? playStart.addingTimeInterval(max(track.duration, position + 1)) : nil

        switch lyricsState {
        case .loaded(let lyrics) where lyrics.isSynced:
            hasLyrics = true
            let lines = lyrics.lines
            let index = lyrics.lineIndex(at: position)
            let following = (index ?? -1) + 1
            lineIndex = index ?? -1
            current = index.map { lines[$0].text } ?? "♪"
            if let index, index > 0 { previous = lines[index - 1].text }
            if lines.indices.contains(following + 1) { afterNext = lines[following + 1].text }
            if lines.indices.contains(following) {
                next = lines[following].text
                if snapshot.isPlaying, let start = lines[following].time {
                    nextChange = min(1, max(0.05, start - position + 0.02))
                }
            }
            if snapshot.isPlaying {
                let start = index.flatMap { lines[$0].time } ?? 0
                let end = lines.indices.contains(following) ? lines[following].time : nil
                lineStart = playStart.addingTimeInterval(start)
                lineEnd = end.map { playStart.addingTimeInterval($0) } ?? songEnd
                if let s = lineStart, let e = lineEnd, e <= s { lineStart = nil; lineEnd = nil }
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
            hasLyrics: hasLyrics,
            previousLine: previous,
            afterNextLine: afterNext,
            lineIndex: lineIndex,
            lineStart: lineStart,
            lineEnd: lineEnd,
            songStart: songStart,
            songEnd: songEnd
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
            if isInBackground { keepAlive.ensureRunning() }
            let snapshot = try await api.currentlyPlaying()
            consecutiveErrors = 0
            bannerMessage = nil
            if isInBackground { lastBackgroundPoll = Date() }

            guard let snapshot, let track = snapshot.track else {
                playback = .nothingPlaying
                // In background, dopo 10 minuti senza musica smettiamo per non consumare batteria.
                let since = nothingPlayingSince ?? Date()
                nothingPlayingSince = since
                if isInBackground, Date().timeIntervalSince(since) > 600 {
                    stop()
                    liveActivity.end()
                }
                return 5
            }
            nothingPlayingSince = nil
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
