import Foundation
import WidgetKit

/// Passa al widget il brano e le righe con i loro orari, e gli chiede di ricaricarsi solo quando serve
/// (nuovo brano, pausa/ripresa, salto nel brano, testo caricato).
@MainActor
final class WidgetPublisher {
    private var last: LyricsWidgetSnapshot?
    private var hasPublished = false

    var isAvailable: Bool { AppGroup.defaults != nil }

    func publish(_ snapshot: LyricsWidgetSnapshot?) {
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
        LyricsWidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: LyricsWidgetSnapshot.kind)
    }
}
