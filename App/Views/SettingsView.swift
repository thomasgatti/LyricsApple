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
                    if model.showLiveActivity {
                        Stepper(value: $bindableModel.liveActivityLead, in: 0...3, step: 0.25) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Anticipo extra (blocco e CarPlay)")
                                Text(String(format: "%.2f secondi", model.liveActivityLead))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if model.liveActivityLead != NowPlayingViewModel.defaultLiveActivityLead {
                            Button("Ripristina a 0,5 secondi") {
                                model.liveActivityLead = NowPlayingViewModel.defaultLiveActivityLead
                            }
                        }
                    }
                } header: {
                    Text("Live Activity")
                } footer: {
                    Text("Mostra la riga in corso sulla schermata di blocco, nella Dynamic Island e, con iOS 26, sullo schermo CarPlay. Continua anche a iPhone bloccato (Lyrics resta attiva in sottofondo con un audio silenzioso: consuma un po' più di batteria). Si ferma da sola dopo 10 minuti senza musica. L'anticipo extra compensa il tempo che iOS impiega ad aggiornarla e si somma all'anticipo del testo. Da usare solo ad auto ferma o per i passeggeri.")
                }

                Section("Sicurezza") {
                    Label("Non leggere i testi mentre guidi. L'app è pensata per i passeggeri o per l'auto ferma, anche quando il testo compare sullo schermo CarPlay.", systemImage: "car")
                        .font(.footnote)
                }

                Section {
                    LabeledContent("Widget (App Group)", value: model.appGroupName == nil ? "Non disponibile" : "Attivo")
                    LabeledContent("Ultimo aggiornamento widget", value: Self.time(model.lastWidgetReload))
                    LabeledContent("Ultimo controllo a iPhone bloccato", value: Self.time(model.lastBackgroundPoll))
                    LabeledContent("Riavvii audio in sottofondo", value: "\(model.keepAliveRestarts)")
                    LabeledContent("Live Activity", value: model.liveActivitySummary)
                    LabeledContent("Ultimo invio Live Activity", value: Self.time(model.liveActivityLastUpdate))
                    if let error = model.liveActivityError {
                        Text("Errore Live Activity: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Diagnostica")
                } footer: {
                    Text("Se il testo sulla schermata di blocco si ferma, guarda qui l'orario dell'ultimo controllo a iPhone bloccato e mandalo a chi ti aiuta con l'app.")
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

extension SettingsView {
    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
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
