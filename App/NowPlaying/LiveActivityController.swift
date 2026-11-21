import ActivityKit
import Foundation

/// Avvia, aggiorna e chiude la Live Activity "Lyrics".
///
/// - Invia i cambiamenti (nuova riga, nuovo brano, pausa) e, anche senza cambiamenti, un "segnale di vita"
///   ogni 30 secondi. Se i segnali smettono di arrivare (iOS ha sospeso Lyrics) dopo 75 secondi la
///   Live Activity risulta "non aggiornata" e invita ad aprire l'app.
/// - Ne tiene viva UNA sola: adotta quella già esistente invece di crearne un'altra, e chiude le copie.
///   (Una copia "orfana" resterebbe sulla schermata di blocco ferma sul vecchio brano.)
/// - Quando l'app torna in primo piano la ricrea da zero (`restart`), così una Live Activity che iOS
///   non aggiorna più viene sostituita.
@MainActor
final class LiveActivityController {
    typealias State = LyricsActivityAttributes.ContentState

    static let heartbeat: TimeInterval = 30
    static let staleAfter: TimeInterval = 75
    static let defaultBackgroundMinInterval: TimeInterval = 4
    /// Distanza minima tra due aggiornamenti a iPhone bloccato o in un'altra app (regolabile in Impostazioni).
    var backgroundMinInterval: TimeInterval = LiveActivityController.defaultBackgroundMinInterval

    private var activity: Activity<LyricsActivityAttributes>?
    private var lastState: State?
    private var lastSent: Date?
    private var needsRestart = false

    /// Diagnostica (Impostazioni).
    private(set) var lastUpdate: Date?
    private(set) var lastError: String?
    var systemActivityCount: Int { Activity<LyricsActivityAttributes>.activities.count }
    var stateDescription: String {
        guard let activity else { return "nessuna" }
        switch activity.activityState {
        case .active: return "attiva"
        case .stale: return "non aggiornata"
        case .ended: return "chiusa"
        case .dismissed: return "rimossa"
        @unknown default: return "sconosciuto"
        }
    }

    /// `false` se l'utente ha disattivato le Live Activity per Lyrics in Impostazioni iOS.
    var isAllowedBySystem: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    init() {
        // Chiude eventuali Live Activity rimaste da un avvio precedente.
        endAll(except: nil)
    }

    /// Da chiamare quando l'app torna in primo piano: al prossimo `show` la Live Activity viene ricreata.
    func restart() {
        needsRestart = true
    }

    /// Diagnostica: aggiornamenti mandati con l'iPhone bloccato / app in background.
    private(set) var backgroundUpdates = 0
    private(set) var lastBackgroundUpdate: Date?

    /// Restituisce dopo quanti secondi riprovare se l'aggiornamento è stato rimandato per il limite
    /// a iPhone bloccato: così la riga scartata arriva appena possibile, non alla riga successiva.
    @discardableResult
    func show(_ state: State, now: Date = Date(), inBackground: Bool = false) -> TimeInterval? {
        if needsRestart {
            needsRestart = false
            endAll(except: nil)
            activity = nil
            lastState = nil
        }

        if let activity, !Self.isUpdatable(activity) {
            self.activity = nil
            lastState = nil
        }
        if activity == nil {
            // Adotta una Live Activity già presente (per esempio creata prima di una sospensione).
            activity = Activity<LyricsActivityAttributes>.activities.first(where: Self.isUpdatable)
        }
        endAll(except: activity?.id)

        if let lastState, state.isEquivalent(to: lastState), activity != nil,
           let lastSent, now.timeIntervalSince(lastSent) < Self.heartbeat {
            return nil
        }
        // Con l'iPhone bloccato iOS accetta solo pochi aggiornamenti: li diradiamo (al massimo uno ogni
        // `backgroundMinInterval` secondi) tenendo subito quelli importanti (nuova canzone, pausa/ripresa).
        if inBackground, activity != nil, let lastState, let lastSent,
           lastState.title == state.title, lastState.isPlaying == state.isPlaying,
           now.timeIntervalSince(lastSent) < backgroundMinInterval {
            return backgroundMinInterval - now.timeIntervalSince(lastSent)
        }
        lastState = state
        lastSent = now
        if inBackground {
            backgroundUpdates += 1
            lastBackgroundUpdate = now
        }
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleAfter))

        if let activity {
            Task {
                await activity.update(content)
                self.lastUpdate = Date()
            }
            return nil
        }
        guard isAllowedBySystem else {
            lastError = "Live Activity disattivate nelle Impostazioni di iOS"
            return nil
        }
        do {
            activity = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: content,
                pushType: nil
            )
            lastUpdate = Date()
            lastError = nil
        } catch {
            activity = nil
            lastState = nil
            lastSent = nil
            lastError = error.localizedDescription
        }
        return nil
    }

    func end() {
        lastState = nil
        lastSent = nil
        activity = nil
        endAll(except: nil)
    }

    private static func isUpdatable(_ activity: Activity<LyricsActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    private func endAll(except keepID: String?) {
        for other in Activity<LyricsActivityAttributes>.activities where other.id != keepID {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
