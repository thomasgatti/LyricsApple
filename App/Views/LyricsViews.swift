import SwiftUI

/// Sceglie cosa mostrare in base allo stato dei testi.
struct LyricsContainer: View {
    @Environment(NowPlayingViewModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            switch model.lyricsState {
            case .idle, .loading:
                ProgressView("Cerco il testo…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let lyrics):
                if lyrics.isSynced {
                    SyncedLyricsView(lyrics: lyrics)
                } else {
                    PlainLyricsView(lyrics: lyrics)
                }
            case .instrumental:
                MessageView(title: "Brano strumentale", subtitle: "Goditi la musica.", systemImage: "pianokeys")
            case .notFound:
                MessageView(
                    title: "Testo non disponibile",
                    subtitle: "Non ho trovato il testo di questo brano.",
                    systemImage: "text.badge.xmark",
                    actionTitle: "Riprova",
                    action: model.retryLyrics
                )
            case .failed(let message):
                MessageView(
                    title: "Impossibile caricare il testo",
                    subtitle: message,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "Riprova",
                    action: model.retryLyrics
                )
            }

            if case .loaded(let lyrics) = model.lyricsState {
                Text(lyrics.isSynced ? "Testo sincronizzato · \(lyrics.source)" : "Testo non sincronizzato · \(lyrics.source)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }
}

/// Testo sincronizzato: la riga corrente è evidenziata e centrata automaticamente.
struct SyncedLyricsView: View {
    @Environment(NowPlayingViewModel.self) private var model
    let lyrics: Lyrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            LyricsScroll(lines: lyrics.lines, currentIndex: model.currentLineIndex(at: context.date))
        }
    }
}

private struct LyricsScroll: View {
    let lines: [LyricLine]
    let currentIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 80)
                    ForEach(lines) { line in
                        LyricLineView(text: line.text, state: state(for: line.id))
                            .id(line.id)
                    }
                    Color.clear.frame(height: 320)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if let currentIndex { proxy.scrollTo(currentIndex, anchor: Self.anchor) }
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(newIndex, anchor: Self.anchor)
                }
            }
        }
    }

    private static let anchor = UnitPoint(x: 0.5, y: 0.35)

    private func state(for index: Int) -> LyricLineView.LineState {
        guard let currentIndex else { return .upcoming }
        if index == currentIndex { return .current }
        return index < currentIndex ? .past : .upcoming
    }
}

private struct LyricLineView: View {
    enum LineState { case past, current, upcoming }

    let text: String
    let state: LineState

    var body: some View {
        Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .scaleEffect(state == .current ? 1.0 : 0.96, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: state)
            .accessibilityAddTraits(state == .current ? .isSelected : [])
    }

    private var color: Color {
        switch state {
        case .current: return .white
        case .past: return .white.opacity(0.3)
        case .upcoming: return .white.opacity(0.5)
        }
    }
}

/// Testo senza tempi: semplice scorrimento manuale.
struct PlainLyricsView: View {
    let lyrics: Lyrics

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lyrics.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
