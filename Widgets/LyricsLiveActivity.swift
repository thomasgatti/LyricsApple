import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity con la riga del testo in corso.
/// - Schermata di blocco / banner: copertina testuale, titolo, riga corrente e successiva.
/// - Famiglia `.small`: CarPlay (iOS 26) e Smart Stack di Apple Watch.
/// - Dynamic Island: compatta (icona + stato) ed espansa (riga corrente e successiva).
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
                    LyricLinesView(state: context.state, currentSize: 20, nextSize: 15)
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

/// Sceglie il layout in base a dove viene mostrata la Live Activity.
struct LyricsActivityContentView: View {
    @Environment(\.activityFamily) private var family
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        switch family {
        case .small:
            SmallLyricsView(state: state)
        default:
            LockScreenLyricsView(state: state)
        }
    }
}

/// Layout piccolo: pensato per lo schermo CarPlay. Testo grande, poche parole, alto contrasto.
struct SmallLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "quote.bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(LyricsPalette.accent)
                Text(state.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(state.currentLine)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(8)
    }
}

/// Layout schermata di blocco.
struct LockScreenLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .foregroundStyle(LyricsPalette.accentGradient)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(LyricsPalette.accent)
            }
            LyricLinesView(state: state, currentSize: 22, nextSize: 16)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

struct LyricLinesView: View {
    let state: LyricsActivityAttributes.ContentState
    let currentSize: CGFloat
    let nextSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.currentLine)
                .font(.system(size: currentSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.system(size: nextSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
