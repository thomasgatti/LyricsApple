import SwiftUI

/// Schermata iniziale: collegamento a Spotify (una sola volta).
struct ConnectView: View {
    @Environment(SpotifyAuthService.self) private var auth
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                AppMark()
                    .frame(width: 96, height: 96)

                VStack(spacing: 10) {
                    Text("Lyrics")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Collega Spotify una sola volta: l'app riconosce il brano in riproduzione e ne mostra il testo, sincronizzato quando disponibile.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(systemImage: "waveform", text: "Segue automaticamente ciò che ascolti")
                    FeatureRow(systemImage: "text.alignleft", text: "Evidenzia la riga cantata in quel momento")
                    FeatureRow(systemImage: "person.2", text: "Pensata per i passeggeri o ad auto ferma")
                }
                .padding(.top, 8)

                Spacer()

                if AppConfig.spotifyClientID.isEmpty {
                    Text("Configurazione incompleta: manca il Client ID Spotify (vedi README).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 10) {
                        if auth.isSigningIn {
                            ProgressView().tint(.black)
                        }
                        Text("Collega Spotify")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(auth.isSigningIn)

                Text("L'accesso avviene sulla pagina ufficiale di Spotify: l'app non vede né salva la tua password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    private func connect() async {
        errorMessage = nil
        do {
            try await auth.signIn()
        } catch SpotifyAuthError.cancelled {
            // L'utente ha chiuso il foglio: nessun errore da mostrare.
        } catch {
            errorMessage = ErrorMessages.userFacing(error)
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(text)
                .font(.callout)
        }
    }
}

/// Marchio dell'app: tre righe di testo, quella centrale evidenziata.
struct AppMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                VStack(alignment: .leading, spacing: w * 0.1) {
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: w * 0.46, height: w * 0.07)
                    Capsule().fill(Theme.accentGradient).frame(width: w * 0.58, height: w * 0.07)
                    Capsule().fill(Color.white.opacity(0.4)).frame(width: w * 0.38, height: w * 0.07)
                }
                .frame(width: w * 0.6, alignment: .leading)
            }
        }
    }
}
