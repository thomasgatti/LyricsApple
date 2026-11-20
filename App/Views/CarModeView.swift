import SwiftUI
import UIKit

/// Modalità auto: da tenere aperta sull'iPhone nel supporto.
/// Con Lyrics in primo piano iOS applica subito gli aggiornamenti, quindi il riquadro su CarPlay
/// e il widget seguono in tempo reale salti, pause e cambi di canzone.
/// Schermo nero (consuma poco sugli schermi OLED), luminosità ridotta, solo la riga in corso.
struct CarModeView: View {
    @Environment(NowPlayingViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("carModeDimScreen") private var dimScreen = true
    @State private var savedBrightness: CGFloat?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            CarModeContent(texts: texts(at: context.date), dimScreen: $dimScreen) {
                dismiss()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            model.setCarMode(true)
            applyBrightness()
        }
        .onDisappear {
            model.setCarMode(false)
            restoreBrightness()
        }
        .onChange(of: dimScreen) { _, _ in applyBrightness() }
    }

    private func texts(at date: Date) -> CarModeTexts {
        guard let track = model.currentTrack else {
            return CarModeTexts(title: "Lyrics", current: "Niente in riproduzione", next: "Avvia una canzone su Spotify")
        }
        let title = "\(track.title) · \(track.artistLine)"
        switch model.lyricsState {
        case .loaded(let lyrics) where lyrics.isSynced:
            let index = model.currentLineIndex(at: date)
            let current = index.map { lyrics.lines[$0].text } ?? ""
            let nextText = lyrics.lines[((index ?? -1) + 1)...].first { !$0.text.isEmpty }?.text ?? ""
            return CarModeTexts(title: title, current: current.isEmpty ? "♪" : current, next: nextText,
                                isPaused: !(model.snapshot?.isPlaying ?? false))
        case .loaded:
            return CarModeTexts(title: title, current: "Testo non sincronizzato", next: "")
        case .idle, .loading:
            return CarModeTexts(title: title, current: "Cerco il testo…", next: "")
        case .instrumental:
            return CarModeTexts(title: title, current: "♪ Brano strumentale", next: "")
        case .notFound:
            return CarModeTexts(title: title, current: "Testo non disponibile", next: "")
        case .failed:
            return CarModeTexts(title: title, current: "Testo non caricato", next: "")
        }
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private func applyBrightness() {
        guard let screen else { return }
        if dimScreen {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 0.12
        } else {
            restoreBrightness()
        }
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        screen?.brightness = saved
        savedBrightness = nil
    }
}

struct CarModeTexts: Equatable {
    var title: String
    var current: String
    var next: String
    var isPaused = false
}

/// Parte grafica della Modalità auto (separata per poterne disegnare l'anteprima nei test).
struct CarModeContent: View {
    let texts: CarModeTexts
    @Binding var dimScreen: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: texts.isPaused ? "pause.fill" : "car.fill")
                    .foregroundStyle(LyricsPalette.accent)
                Text(texts.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    dimScreen.toggle()
                } label: {
                    Image(systemName: dimScreen ? "sun.min.fill" : "sun.max.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(dimScreen ? "Schermo più luminoso" : "Schermo più scuro")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Esci dalla modalità auto")
            }
            .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text(texts.current)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(5)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(texts.current)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            if !texts.next.isEmpty {
                Text(texts.next)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            SyncNudgeBar()
                .frame(maxWidth: .infinity)
            Text("Lascia Lyrics aperta: così CarPlay segue il testo in tempo reale. Solo per passeggeri o ad auto ferma.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: texts.current)
    }
}
