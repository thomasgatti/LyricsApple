import SwiftUI

/// Schermata iniziale: collegamento a Spotify (una sola volta).
///
/// Se l'app Spotify è installata, il metodo consigliato è "Continua con l'app Spotify": l'utente è già
/// collegato lì (anche con Google, Apple o Facebook) e deve solo toccare "Accetta".
/// In alternativa si usa la pagina web di Spotify, dove sono disponibili tutti i metodi di accesso.
struct ConnectView: View {
    @Environment(SpotifyAuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorMessage: String?
    @State private var spotifyInstalled = false
    @State private var showReturnHint = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
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
                .padding(.top, 4)

                Spacer()

                messages

                if auth.isSigningIn {
                    signingInPanel
                } else {
                    signInButtons
                }

                Text("L'accesso avviene da Spotify: l'app non vede né salva la tua password, nemmeno quella di Google.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .onAppear { spotifyInstalled = auth.isSpotifyAppInstalled }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            spotifyInstalled = auth.isSpotifyAppInstalled
            // Se l'utente torna qui senza aver confermato in Spotify, proponiamo come proseguire.
            if auth.signInInProgress == .spotifyApp {
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if auth.signInInProgress == .spotifyApp { showReturnHint = true }
                }
            }
        }
    }

    // MARK: - Sezioni

    @ViewBuilder
    private var messages: some View {
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
    }

    @ViewBuilder
    private var signInButtons: some View {
        VStack(spacing: 12) {
            if spotifyInstalled {
                Button {
                    connect(using: .spotifyApp)
                } label: {
                    Label("Continua con l'app Spotify", systemImage: "music.note")
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Consigliato: usa l'account già attivo nell'app Spotify, anche se accedi con Google, Apple o Facebook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Accedi dal browser") { connect(using: .browser) }
                    .font(.callout.weight(.semibold))
                    .padding(.top, 2)
            } else {
                Button {
                    connect(using: .browser)
                } label: {
                    Label("Accedi a Spotify", systemImage: "person.crop.circle")
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("Si apre la pagina di Spotify. Se il tuo account è collegato a Google, tocca «Continua con Google» (o Apple, Facebook).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var signingInPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text(auth.signInInProgress == .spotifyApp
                     ? "Conferma l'accesso nell'app Spotify…"
                     : "Completa l'accesso nella pagina di Spotify…")
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white.opacity(0.08), in: Capsule())

            if showReturnHint {
                Text("Non hai confermato in Spotify? Puoi riprovare oppure accedere dal browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                Button("Annulla") { auth.cancelSignIn() }
                if showReturnHint {
                    Button("Usa il browser") {
                        auth.cancelSignIn()
                        Task {
                            // lascia chiudere il tentativo precedente
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            connect(using: .browser)
                        }
                    }
                }
            }
            .font(.callout.weight(.semibold))
        }
    }

    // MARK: - Azioni

    private func connect(using method: SpotifySignInMethod) {
        errorMessage = nil
        showReturnHint = false
        Task {
            do {
                try await auth.signIn(using: method)
            } catch SpotifyAuthError.cancelled {
                // Annullato dall'utente: nessun errore da mostrare.
            } catch {
                errorMessage = ErrorMessages.userFacing(error)
            }
            showReturnHint = false
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
