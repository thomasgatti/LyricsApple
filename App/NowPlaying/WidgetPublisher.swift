import Foundation
import WidgetKit

/// Passa al widget il brano e le righe con i loro orari, e gli chiede di ricaricarsi solo quando serve
/// (nuovo brano, pausa/ripresa, salto nel brano, testo caricato).
@MainActor
final class WidgetPublisher {
    private var last: LyricsWidgetSnapshot?
    private var hasPublished = false
    private(set) var lastReload: Date?

    var isAvailable: Bool { AppGroup.defaults != nil }

    /// La prossima `publish` ricarica il widget anche se i dati non sono cambiati.
    func invalidate() {
        hasPublished = false
    }

    /// Diagnostica: ricariche chieste con l'iPhone bloccato / app in background.
    private(set) var backgroundReloads = 0
    private(set) var lastBackgroundReload: Date?

    func publish(inBackground: Bool = false, _ snapshot: LyricsWidgetSnapshot?) {
        guard isAvailable else { return }
        if hasPublished {
            switch (snapshot, last) {
            case (nil, nil): return
            case let (new?, old?) where new.isEquivalent(to: old): return
            default: break
            }
        }
        hasPublished = true
        last = snapshot
        lastReload = Date()
        if inBackground {
            backgroundReloads += 1
            lastBackgroundReload = lastReload
        }
        LyricsWidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: LyricsWidgetSnapshot.kind)
    }
}
