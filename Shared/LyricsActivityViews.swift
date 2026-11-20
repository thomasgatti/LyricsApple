import SwiftUI
import WidgetKit

// Viste della Live Activity. Stanno in Shared così le compila anche l'app,
// e i test possono disegnarne le anteprime (vedi Tests/PreviewRenderTests.swift).

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

// MARK: - CarPlay

/// Layout piccolo: pensato per lo schermo CarPlay. Testo grande, alto contrasto, poche righe.
struct SmallLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: state.isPlaying ? "quote.bubble.fill" : "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(LyricsPalette.accent)
                Text(state.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                // Testo grande che occupa tutto lo spazio libero: si rimpicciolisce da solo solo se non ci sta.
                Text(state.currentLine)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                KaraokeBar(state: state, height: 3)
                FadedLineText(text: state.nextLine, size: 15, opacity: 0.55)
            }
            .scrollingLines(state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .foregroundStyle(.white)
    }
}

// MARK: - Schermata di blocco

struct LockScreenLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "quote.bubble.fill")
                    .foregroundStyle(LyricsPalette.accentGradient)
                Text("\(state.title) · \(state.artist)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(LyricsPalette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                FadedLineText(text: state.previousLine, size: 13, opacity: 0.3)
                CurrentLineText(state: state, size: 20, lines: 2)
                KaraokeBar(state: state)
                FadedLineText(text: state.nextLine, size: 15, opacity: 0.55)
                FadedLineText(text: state.afterNextLine, size: 13, opacity: 0.28)
            }
            .scrollingLines(state)

            SongProgressBar(state: state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
    }
}

// MARK: - Dynamic Island

struct DynamicIslandLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CurrentLineText(state: state, size: 20, lines: 2)
            KaraokeBar(state: state)
            FadedLineText(text: state.nextLine, size: 15, opacity: 0.45)
        }
        .scrollingLines(state)
    }
}

// MARK: - Pezzi comuni

/// Riga cantata adesso: grande, in grassetto.
struct CurrentLineText: View {
    let state: LyricsActivityAttributes.ContentState
    let size: CGFloat
    let lines: Int

    var body: some View {
        Text(state.currentLine)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(lines)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Righe vicine: più piccole e sfumate. Se vuote non occupano spazio.
struct FadedLineText: View {
    let text: String
    let size: CGFloat
    let opacity: Double

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(opacity))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Barra sotto la riga corrente: si riempie da sola mentre la riga viene cantata.
struct KaraokeBar: View {
    let state: LyricsActivityAttributes.ContentState
    var height: CGFloat = 3

    var body: some View {
        if let start = state.lineStart, let end = state.lineEnd, end > start, state.isPlaying {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(LyricsPalette.accent)
            .frame(height: height)
            .scaleEffect(x: 1, y: height / 4, anchor: .center)
        }
    }
}

/// Avanzamento del brano, sottile, in fondo.
struct SongProgressBar: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        if let start = state.songStart, let end = state.songEnd, end > start, state.isPlaying {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.white.opacity(0.5))
            .scaleEffect(x: 1, y: 0.5, anchor: .center)
        }
    }
}

extension View {
    /// A ogni nuova riga il blocco di testo cambia identità ed entra dal basso: effetto "scorrimento".
    func scrollingLines(_ state: LyricsActivityAttributes.ContentState) -> some View {
        self
            .id(state.lineIndex)
            .transition(.push(from: .bottom))
    }
}
