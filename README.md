# Lyrics: testi sincronizzati per ciò che ascolti su Spotify

App iPhone gratuita che riconosce il brano in riproduzione sul tuo account Spotify (anche quando suona in auto tramite CarPlay) e ne mostra il testo, evidenziando la riga corrente.

> **Sicurezza e regole Apple**: i testi **non** compaiono sullo schermo CarPlay. Apple lo vieta e chi guida non deve leggerli. L'app è pensata per i passeggeri o per l'auto ferma. Dettagli in [docs/ANALISI.md](docs/ANALISI.md).

## Cosa ti serve
1. **Un Mac** con **Xcode** (gratis dal Mac App Store, versione 16 o successiva). Senza Mac non si può installare un'app su iPhone. Alternative: farsi prestare un Mac, o noleggiarne uno nel cloud.
2. Un **iPhone** con iOS 17 o successivo e un cavo USB.
3. Un **Apple ID** (va bene quello gratuito).
4. Un account **Spotify Premium** per creare l'app sviluppatore. È una regola Spotify dal 2026. Chi poi usa l'app può avere anche Spotify Free.

## Passo 1: crea l'app su Spotify (5 minuti, dal browser, anche da Windows)
1. Vai su https://developer.spotify.com/dashboard e accedi.
2. **Create app**:
   - App name: `Lyrics` (o quello che vuoi)
   - App description: `Testi per uso personale`
   - Redirect URI: `lyricsapple://spotify-callback` (copialo esattamente), poi premi **Add**
   - API utilizzate: spunta **Web API**
   - Accetta i termini e salva.
3. Nella pagina dell'app apri **Settings** e copia il **Client ID**.
4. Apri **User Management** e aggiungi nome ed email dell'account Spotify che userà l'app (anche il tuo). Puoi aggiungere **massimo 5 persone**.

## Passo 2: inserisci il Client ID
Apri `Config/Secrets.xcconfig` con un editor di testo e compila:
```
SPOTIFY_CLIENT_ID = il_tuo_client_id
APP_BUNDLE_ID = com.tuonome.lyricsapple
```
Al posto di `tuonome` metti qualcosa di unico, ad esempio il tuo nome senza spazi.

## Passo 3: genera il progetto sul Mac
Copia l'intera cartella `LyricsApple` sul Mac e apri **Terminale**:
```bash
# una volta sola: installa Homebrew (https://brew.sh), poi XcodeGen
brew install xcodegen

cd percorso/della/cartella/LyricsApple
xcodegen generate
open LyricsApple.xcodeproj
```

## Passo 4: installa sul tuo iPhone
1. In Xcode: **Settings → Accounts → +** e aggiungi il tuo Apple ID.
2. Clicca il progetto **LyricsApple** nella colonna di sinistra, poi il target **LyricsApple**, poi la scheda **Signing & Capabilities**. Spunta *Automatically manage signing* e scegli il tuo **Team** (es. "Mario Rossi (Personal Team)").
3. Collega l'iPhone con il cavo e sbloccalo. Se compare "Autorizzare questo computer?", tocca **Autorizza**.
4. Sull'iPhone: **Impostazioni → Privacy e sicurezza → Modalità sviluppatore → Attiva**, poi riavvia.
5. In Xcode seleziona il tuo iPhone in alto e premi **▶︎ (Run)**.
6. Alla prima apertura iOS potrebbe bloccare l'app. Vai in **Impostazioni → Generali → VPN e gestione dispositivi**, tocca il tuo Apple ID e scegli **Autorizza**.

> Con l'Apple ID gratuito l'app funziona per **7 giorni**. Poi basta ricollegare l'iPhone e premere di nuovo ▶︎. Con l'Apple Developer Program (99 $/anno) la firma dura un anno e puoi usare TestFlight.

## Passo 5: prova
1. Apri **Lyrics**, leggi l'avviso di sicurezza e tocca **Collega Spotify**, poi accedi. Lo fai una volta sola.
2. Avvia un brano su Spotify, da qualunque dispositivo collegato allo stesso account: iPhone, CarPlay, computer.
3. In pochi secondi compaiono copertina, titolo e testo. La riga cantata è evidenziata.
4. Se il testo è in ritardo o in anticipo: **⚙︎ → Anticipo del testo**.

### In auto con CarPlay
- Il guidatore usa Spotify su CarPlay come sempre.
- Il passeggero apre **Lyrics** sul proprio iPhone, collegato allo **stesso account Spotify** (va aggiunto tra i 5 utenti), oppure sull'iPhone del guidatore tenuto in mano dal passeggero.
- Lo schermo resta acceso finché l'app è aperta (si disattiva dalle impostazioni).

## Verifica automatica senza Mac (opzionale)
Se carichi il progetto su GitHub, il workflow `.github/workflows/ios.yml` lo compila ed esegue i test su un Mac di GitHub. Così scopri subito eventuali errori di compilazione.

## Risoluzione problemi
| Messaggio | Soluzione |
|---|---|
| "Manca il Client ID Spotify" | Passo 2, poi ricompila |
| "INVALID_CLIENT: Invalid redirect URI" su Spotify | Il Redirect URI nella dashboard deve essere esattamente `lyricsapple://spotify-callback` |
| "Spotify ha negato l'accesso…" (403) | Aggiungi l'email in User Management (Passo 1.4) |
| "Niente in riproduzione" | Avvia un brano; le sessioni private e i podcast non sono supportati |
| "Testo non disponibile" | LRCLIB non ha quel brano; tocca "Riprova" più tardi |
| "Failed to register bundle identifier" in Xcode | Cambia `APP_BUNDLE_ID` con un valore più unico |

## Struttura e scelte tecniche
Vedi [docs/ANALISI.md](docs/ANALISI.md).

## Crediti
- Dati del brano: Spotify Web API. Spotify è un marchio di Spotify AB; questa app non è affiliata a Spotify.
- Testi: [LRCLIB](https://lrclib.net), database aperto e collaborativo. I testi appartengono ai rispettivi autori ed editori.
