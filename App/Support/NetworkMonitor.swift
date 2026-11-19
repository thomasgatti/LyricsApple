import Foundation
import Network
import Observation

/// Indica se il telefono ha accesso a Internet.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "LyricsApple.NetworkMonitor"))
    }
}

enum ErrorMessages {
    /// Messaggio comprensibile per l'utente.
    static func userFacing(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Sei offline. Riprovo appena torna la connessione."
            case .timedOut:
                return "La connessione è lenta. Riprovo…"
            default:
                return "Problema di rete. Riprovo…"
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Si è verificato un errore imprevisto."
    }
}
