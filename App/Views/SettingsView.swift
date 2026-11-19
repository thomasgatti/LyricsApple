import SwiftUI

struct SettingsView: View {
    @Environment(NowPlayingViewModel.self) private var model
    @Environment(SpotifyAuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var bindableModel = model

        NavigationStack {
            Form {
                Section {
                    Stepper(value: $bindableModel.syncOffset, in: -5...5, step: 0.25) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anticipo del testo")
                            Text(String(format: "%+.2f secondi", model.syncOffset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if model.syncOffset != 0 {
                        Button("Ripristina a 0") { model.syncOffset = 0 }
                    }
                } header: {
                    Text("Sincronizzazione")
                } footer: {
                    Text("Se il testo arriva in ritardo rispetto alla voce, aumenta l'anticipo; se arriva troppo presto, diminuiscilo.")
                }

                Section("Schermo") {
                    Toggle("Mantieni lo schermo acceso", isOn: $bindableModel.keepScreenOn)
                }

                Section {
                    Toggle("Testo su CarPlay e schermata di blocco", isOn: $bindableModel.showLiveActivity)
                } header: {
                    Text("Live Activity")
                } footer: {
                    Text("Mostra la riga in corso sulla schermata di blocco, nella Dynamic Island e, con iOS 26, sullo schermo CarPlay. Continua anche a iPhone bloccato (Lyrics resta attiva in sottofondo con un audio silenzioso: consuma un po' più di batteria). Si ferma da sola dopo 10 minuti senza musica. Da usare solo ad auto ferma o per i passeggeri.")
                }

                Section("Sicurezza") {
                    Label("Non leggere i testi mentre guidi. L'app è pensata per i passeggeri o per l'auto ferma, anche quando il testo compare sullo schermo CarPlay.", systemImage: "car")
                        .font(.footnote)
                }

                Section("Fonti") {
                    LabeledContent("Brano in riproduzione", value: "Spotify")
                    LabeledContent("Testi", value: model.lyricsSourceName)
                    Link("Informazioni su LRCLIB", destination: URL(string: "https://lrclib.net")!)
                }

                Section {
                    Button("Disconnetti Spotify", role: .destructive) {
                        model.reset()
                        auth.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

struct SafetyNoticeView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "car.side")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
                .padding(.top, 36)
            Text("Prima di iniziare")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Chi guida non deve leggere i testi.", systemImage: "hand.raised")
                Label("Usa l'app come passeggero o ad auto ferma.", systemImage: "person.2")
                Label("Se attivi la Live Activity, la riga in corso compare anche su CarPlay: leggila solo ad auto ferma.", systemImage: "iphone")
            }
            .font(.callout)
            Spacer()
            Button("Ho capito", action: onAccept)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .presentationDetents([.medium, .large])
    }
}
