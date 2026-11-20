import ActivityKit
import Foundation

/// Avvia, aggiorna e chiude la Live Activity "Lyrics".
/// Gli aggiornamenti partono dall'app: invia i cambiamenti (nuova riga, nuovo brano, pausa) e,
/// anche senza cambiamenti, un "segnale di vita" ogni 30 secondi. Se i segnali smettono di arrivare
/// (iOS ha sospeso Lyrics) dopo 75 secondi la Live Activity risulta "non aggiornata" e invita ad aprire l'app,
/// invece di mostrare righe sbagliate.
@MainActor
final class LiveActivityController {
    typealias State = LyricsActivityAttributes.ContentState

    static let heartbeat: TimeInterval = 30
    static let staleAfter: TimeInterval = 75

    private var activity: Activity<LyricsActivityAttributes>?
    private var lastState: State?
    private var lastSent: Date?

    /// `false` se l'utente ha disattivato le Live Activity per Lyrics in Impostazioni iOS.
    var isAllowedBySystem: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    init() {
        // Chiude eventuali Live Activity rimaste da un avvio precedente.
        for leftover in Activity<LyricsActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func show(_ state: State, now: Date = Date()) {
        if let lastState, state.isEquivalent(to: lastState), activity?.activityState == .active,
           let lastSent, now.timeIntervalSince(lastSent) < Self.heartbeat {
            return
        }
        lastState = state
        lastSent = now
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleAfter))

        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        guard isAllowedBySystem else { return }
        do {
            activity = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: content,
                pushType: nil
            )
        } catch {
            activity = nil
            lastState = nil
            lastSent = nil
        }
    }

    func end() {
        lastState = nil
        lastSent = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
