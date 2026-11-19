import ActivityKit
import Foundation

/// Avvia, aggiorna e chiude la Live Activity "Lyrics".
/// Gli aggiornamenti partono dall'app mentre è aperta: invia solo i cambiamenti (nuova riga, nuovo brano, pausa).
@MainActor
final class LiveActivityController {
    typealias State = LyricsActivityAttributes.ContentState

    private var activity: Activity<LyricsActivityAttributes>?
    private var lastState: State?

    /// `false` se l'utente ha disattivato le Live Activity per Lyrics in Impostazioni iOS.
    var isAllowedBySystem: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    init() {
        // Chiude eventuali Live Activity rimaste da un avvio precedente.
        for leftover in Activity<LyricsActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func show(_ state: State) {
        if let lastState, state.isEquivalent(to: lastState), activity?.activityState == .active { return }
        lastState = state
        // Se non riceve aggiornamenti per 10 minuti, iOS la mostra come "non aggiornata".
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))

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
        }
    }

    func end() {
        lastState = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
