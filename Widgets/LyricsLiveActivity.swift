import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity con il testo che scorre.
/// - Schermata di blocco / banner: riga precedente, corrente (con barra karaoke), due successive.
/// - Famiglia `.small`: CarPlay (iOS 26+) e Smart Stack di Apple Watch.
/// - Dynamic Island: compatta (icona + stato) ed espansa (riga corrente e successiva).
/// Le viste sono in `Shared/LyricsActivityViews.swift` (così i test possono disegnarne le anteprime).
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityContentView(state: context.state)
                .activityBackgroundTint(LyricsPalette.background.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(LyricsPalette.accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandLyricsView(state: context.state)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "quote.bubble.fill")
                    .foregroundStyle(LyricsPalette.accent)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(LyricsPalette.accent)
            } minimal: {
                Image(systemName: "quote.bubble.fill")
                    .foregroundStyle(LyricsPalette.accent)
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
