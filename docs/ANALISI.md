# Analisi di fattibilità e scelte tecniche

Data verifica: 19 novembre 2026. Fonti in fondo al documento.

## 1. Verdetto in breve

| Obiettivo | Fattibile? | Note |
|---|---|---|
| Leggere il brano in riproduzione su Spotify | **Sì** | Spotify Web API, endpoint `currently-playing`, login OAuth PKCE senza server |
| Trovare i testi, anche sincronizzati | **Sì, con riserve legali** | LRCLIB: gratis, senza chiave, con timestamp. I diritti sui testi però restano agli editori |
| Evidenziare la riga corrente e cambiare testo col brano | **Sì** | Polling ogni 1–4 s + stima locale della posizione |
| **Testi sullo schermo CarPlay** | **No** | Il CarPlay Developer Guide (anche l'edizione di ottobre 2026) vieta alle app audio di mostrare testi sullo schermo CarPlay. Non esiste una categoria CarPlay "testi". Non lo aggiriamo |
| Widget/Live Activity CarPlay con i testi | **No (e comunque inutilizzabile)** | Stessa regola + limiti tecnici, vedi §3 |
| App gratuita per gli utenti | **Sì** | Nessun backend, nessun abbonamento |
| Pubblicazione su App Store per chiunque | **Oggi no, in pratica** | Spotify limita le app in Development Mode a 5 utenti; l'accesso esteso è riservato ad aziende con servizi già affermati. Più il nodo dei diritti sui testi |

**Soluzione scelta:** app iPhone nativa (SwiftUI) per **passeggeri o auto ferma**. Su CarPlay il guidatore continua a usare Spotify normalmente. L'iPhone di un passeggero, collegato allo **stesso account Spotify**, segue in tempo reale ciò che suona in auto e ne mostra il testo sincronizzato. Questo è il vero valore aggiunto: un secondo schermo che segue la riproduzione senza controllarla. Sullo stesso iPhone che riproduce, invece, anche l'app Spotify mostra già i testi.

## 2. Fase 0: skill e strumenti

| Cosa | Esito |
|---|---|
| Skill installate per Swift, Xcode, CarPlay o Spotify | Nessuna |
| **Mac + Xcode** | **Mancano.** Il tuo PC è Windows: le app iOS si compilano e si installano solo con Xcode su macOS. È il requisito più importante (vedi README) |
| Plugin disponibili nel catalogo | *SwiftUI App Design* e *Mobile App Design (iOS)* (community, gratuiti, utili per rifinire la UI); *swift-lsp* (diagnostica Swift, ma richiede il toolchain Swift, quindi è utile solo su Mac). **Non installati**: per questa versione non servono |
| Alternativa concreta al Mac per verificare il codice | Workflow GitHub Actions incluso (`.github/workflows/ios.yml`): compila ed esegue i test su un Mac remoto di GitHub. È gratis per i repository pubblici, con minuti inclusi per quelli privati |
| XcodeGen | Genera il progetto Xcode da `project.yml`. Gratuito, si installa sul Mac con Homebrew |

## 3. Verifica tecnica

### Apple CarPlay
- **Entitlement CarPlay**: solo per categorie precise (audio, comunicazione, navigazione, parcheggio, ricarica EV, carburante, guida, consegne cibo, ecc.). Un'app "solo testi" non rientra in nessuna. Come app audio non potrebbe comunque mostrare testi.
- **Regola sui testi**: il CarPlay Developer Guide stabilisce che le app audio non devono mai mostrare testi di canzoni sullo schermo CarPlay. La regola c'era già nell'edizione di giugno 2026 ed è confermata in quella di ottobre 2026.
- **Widget in CarPlay (iOS 26)**: qualunque widget `systemSmall` compare in CarPlay anche senza app CarPlay. WidgetKit però ha un budget di aggiornamenti giornaliero (ricaricamenti nell'ordine delle decine al giorno). Non può seguire una canzone riga per riga, e mettere i testi lì violerebbe lo spirito della regola sopra.
- **Live Activities in CarPlay (iOS 26)**: compaiono usando la famiglia `small` o le viste compatte. Per aggiornarle mentre l'app è in background serve un server push APNs (quindi un backend) che segua Spotify per ogni utente. Inoltre porterebbe i testi davanti al guidatore. **Scartata.**
- **Auto ferma o in movimento**: CarPlay non offre alle app di terze parti un'API "veicolo parcheggiato" per sbloccare contenuti. Le limitazioni sono decise dal sistema.
- Alcuni progetti di terze parti dichiarano di mostrare testi su CarPlay tramite widget o Live Activity. Sono in contrasto con le regole Apple scritte, e non li replichiamo.

### Spotify
- **Web API** `GET /v1/me/player/currently-playing`: restituisce titolo, artisti, album, copertina, durata, posizione e stato di play/pausa. Funziona anche con account Free.
- **OAuth 2.0 + PKCE**: non serve un client secret né un server. Il refresh token permette di collegarsi una volta sola. I token sono salvati nel Portachiavi.
- **App Remote SDK (iOS)**: per leggere la riproduzione dà eventi in tempo reale, ma richiede l'app Spotify attiva e si disconnette spesso in background: per questo usiamo il polling della Web API. Dell'SDK ufficiale usiamo solo `SPTSessionManager` per il **login tramite l'app Spotify** (PKCE, senza server). Così gli account collegati a Google, Apple o Facebook si collegano con un tocco, senza reinserire credenziali. Se l'app non è installata, si usa la pagina web di Spotify in Safari.
- **Development Mode (da febbraio 2026)**: il proprietario dell'app deve avere **Spotify Premium**, e l'app può essere usata da **massimo 5 utenti**, registrati a mano nella dashboard. Gli utenti non devono essere per forza Premium.
- **Extended Quota (per il pubblico)**: dal 15 maggio 2025 è riservata a organizzazioni con servizi già avviati e un'ampia base di utenti. Secondo fonti di terze parti la soglia è 250k utenti attivi al mese. Un'app personale non ci arriva.
- **API ufficiale per i testi**: **non esiste**. I testi nell'app Spotify (Musixmatch) non sono accessibili.
- **Developer Policy**: vieta di sincronizzare *registrazioni audio* con media visivi come video, pubblicità e slideshow (III.6), e impone di mostrare copertina e metadati con un link a Spotify. Noi non riproduciamo audio: leggiamo solo i metadati e mostriamo il link "Apri in Spotify". Non c'è una regola esplicita sui testi. Ricontrollarla prima di qualunque pubblicazione.

### Testi
| Fonte | Costo | Sincronizzati | Licenza / note |
|---|---|---|---|
| **LRCLIB** (scelta per la v1) | Gratis, nessuna chiave | Sì (LRC) | Database aperto e collaborativo. Il codice è MIT, ma **i testi restano protetti da copyright** e LRCLIB non concede licenze sui testi. Accettabile per uso personale. È un rischio per una pubblicazione |
| Musixmatch API | Piano gratuito: solo il 30% del testo, uso non commerciale; piani completi a pagamento | Sì, a pagamento | Licenza editoriale reale |
| LyricFind | Solo accordi commerciali | Sì | Licenza editoriale reale |
| Scraping (Genius, Google...) | — | — | **Escluso**: viola i termini di servizio |

Il codice usa un protocollo `LyricsProvider`: per passare a una fonte con licenza basta una nuova classe, senza toccare il resto.

## 4. Confronto delle soluzioni

| # | Approccio | Esito |
|---|---|---|
| 1 | Widget iOS compatibile con CarPlay | Vietato per i testi e tecnicamente inadatto (budget di aggiornamenti) |
| 2 | App CarPlay nativa | Nessuna categoria applicabile, testi vietati alle app audio |
| 3 | WidgetKit + Live Activities | Richiedono un backend push e porterebbero i testi al guidatore: scartato |
| 4 | Testi solo ad auto ferma, su CarPlay | Non c'è un'API "parcheggiato" per app di terze parti, e la regola sui testi vale comunque |
| 5 | **App iPhone per passeggeri, sincronizzata con Spotify** | **Scelta.** Legittima, gratuita, senza server, funziona davvero |

## 5. Architettura

```
App/
├── LyricsAppleApp.swift        punto di ingresso, iniezione delle dipendenze
├── AppConfig.swift             Client ID, Redirect URI, scope
├── Auth/                       PKCE, Portachiavi, SpotifyAuthService (login + refresh)
├── Spotify/                    modelli e client della Web API
├── Lyrics/                     modelli, parser LRC, provider LRCLIB, cache su disco
├── NowPlaying/                 NowPlayingViewModel (MVVM): polling, cambio brano, riga corrente
├── Support/                    monitor di rete, messaggi d'errore
└── Views/                      SwiftUI: connessione, lettore testi, impostazioni, avviso sicurezza
Tests/                          parser, matching, PKCE, callback OAuth, decodifica JSON
```

- **Sincronizzazione**: l'app interroga Spotify ogni 4 secondi, e ogni secondo vicino alla fine del brano. La posizione si stima con `progress + (adesso − istante della risposta)`. Una `TimelineView` aggiorna la riga 5 volte al secondo. Un controllo "anticipo testo" (±5 s) compensa le differenze.
- **Nessun backend, nessun costo di infrastruttura.**
- **Errori gestiti**: offline (banner e nuovo tentativo automatico), limite di richieste 429 (rispetta `Retry-After`), sessione scaduta (torna alla schermata di login), utente non abilitato in Development Mode (403, con un messaggio esplicativo), brano senza testo, brano strumentale, pubblicità o podcast.

## 6. Costi e pubblicazione

| Voce | Costo | Necessario per |
|---|---|---|
| Mac con Xcode | Gratis se ne hai uno; noleggio cloud da circa 20–30 €/mese; Mac mini usato | **Obbligatorio** per compilare e installare |
| Apple ID gratuito | 0 € | Installare sul **tuo** iPhone. L'app scade ogni **7 giorni** e va reinstallata da Xcode |
| Apple Developer Program | 99 $/anno | TestFlight, firma valida 1 anno, App Store |
| Spotify Premium (proprietario dell'app) | Abbonamento già esistente | Obbligatorio dal 2026 per la Development Mode |
| Account sviluppatore Spotify | 0 € | Client ID |
| LRCLIB | 0 € | — |
| Server | 0 € | Non serve |

**App Store, realisticamente**: oggi un'app pubblica per chiunque è bloccata da due cose. (1) Spotify: massimo 5 utenti senza Extended Quota. (2) I diritti sui testi: Apple può respingere app che mostrano contenuti protetti senza licenza (Linee guida 5.2), e LRCLIB non offre licenze. Un percorso approvabile richiederebbe un accordo Extended Quota con Spotify e una fonte di testi con licenza (Musixmatch o LyricFind a pagamento): non è compatibile con "costo zero".

**Sostenibile gratis**: uso personale per te e fino a 4 amici o familiari, tramite Xcode (gratis, rinnovo ogni 7 giorni) o TestFlight (99 $/anno).

## 7. Cosa è verificato e cosa no

- ✅ Le regole Apple e Spotify e le API LRCLIB sono state verificate sulle fonti ufficiali alla data indicata.
- ⚠️ **Il codice non è stato compilato**: è stato scritto su Windows, dove non c'è Xcode. La prima compilazione va fatta su Mac, oppure con il workflow GitHub Actions incluso, che esegue anche i test unitari.
- ⚠️ Login Spotify, polling e testi vanno provati su un iPhone reale con il tuo Client ID.
- ⚠️ La precisione della sincronizzazione dipende dalla latenza di rete: si regola con "Anticipo del testo".

## Fonti
- [CarPlay Developer Guide (Apple, ottobre 2026)](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf)
- [WWDC25: What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/)
- [WWDC25: Turbocharge your app for CarPlay](https://developer.apple.com/videos/play/wwdc2025/216/)
- [Spotify: February 2026 Web API Dev Mode changes](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Spotify: Updating the criteria for Web API extended access (2025)](https://developer.spotify.com/blog/2025-04-15-updating-the-criteria-for-web-api-extended-access)
- [Spotify Developer Policy](https://developer.spotify.com/policy)
- [TechCrunch: Spotify dev mode richiede Premium, limite utenti](https://techcrunch.com/2026/02/06/spotify-changes-developer-mode-api-to-require-premium-accounts-limits-test-users/)
- [LRCLIB API docs](https://lrclib.net/docs)
- [CarPlay-Lyrics (progetto open source che conferma il rifiuto dell'entitlement)](https://github.com/lucascollins-11/CarPlay-Lyrics)
