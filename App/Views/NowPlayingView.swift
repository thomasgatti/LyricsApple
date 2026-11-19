import SwiftUI

/// Schermata principale: copertina, titolo, artista e testo.
struct NowPlayingView: View {
    @Environment(NowPlayingViewModel.self) private var model
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("safetyNoticeAccepted") private var safetyNoticeAccepted = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if !network.isOnline {
                StatusBanner(text: "Nessuna connessione", systemImage: "wifi.slash")
            } else if let message = model.bannerMessage {
                StatusBanner(text: message, systemImage: "exclamationmark.circle")
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut, value: network.isOnline)
        .animation(.easeInOut, value: model.bannerMessage)
        // Lo sfondo è "dietro" il contenuto e non ne influenza più la larghezza.
        .background {
            ArtworkBackground(artworkURL: model.currentTrack?.artworkURL)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: Binding(
            get: { !safetyNoticeAccepted },
            set: { isPresented in if !isPresented { safetyNoticeAccepted = true } }
        )) {
            SafetyNoticeView { safetyNoticeAccepted = true }
                .interactiveDismissDisabled()
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
        .onChange(of: network.isOnline) { _, isOnline in
            if isOnline { model.networkRestored() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.playback {
        case .loading:
            VStack(spacing: 0) {
                TopBar(showSettings: $showSettings)
                ProgressView("Collegamento a Spotify…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .nothingPlaying:
            VStack(spacing: 0) {
                TopBar(showSettings: $showSettings)
                NothingPlayingView(onRefresh: model.refreshNow)
            }
        case .playing(let snapshot):
            if let track = snapshot.track {
                VStack(spacing: 0) {
                    TrackHeader(track: track, showSettings: $showSettings)
                    LyricsContainer()
                        .id(track.id)
                }
            }
        }
    }
}

private struct TopBar: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Spacer()
            SettingsButton(showSettings: $showSettings)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

private struct SettingsButton: View {
    @Binding var showSettings: Bool

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Impostazioni")
    }
}

/// Copertina + titolo + artista + barra di avanzamento.
private struct TrackHeader: View {
    @Environment(NowPlayingViewModel.self) private var model
    let track: Track
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AsyncImage(url: track.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1))
                        .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(radius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(track.artistLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if let url = track.spotifyURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Apri in Spotify")
                }
                SettingsButton(showSettings: $showSettings)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = model.snapshot?.estimatedProgress(at: context.date) ?? 0
                ProgressView(value: position, total: max(track.duration, 1))
                    .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct NothingPlayingView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            MessageView(
                title: "Niente in riproduzione",
                subtitle: "Avvia un brano su Spotify (anche dall'auto con CarPlay): il testo comparirà qui da solo.",
                systemImage: "music.note.list",
                actionTitle: "Aggiorna",
                action: onRefresh
            )
            .frame(maxHeight: 360)
            Link("Apri Spotify", destination: URL(string: "https://open.spotify.com")!)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
