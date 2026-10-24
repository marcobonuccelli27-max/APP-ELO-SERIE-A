# Elo Serie A

App Android che calcola i punteggi Elo delle squadre di Serie A, stima le probabilità 1X2 di ogni partita e le confronta con le quote dei bookmaker. Include una verifica sul passato per capire se il modello avrebbe guadagnato davvero.

## Cosa c’è in questa cartella

- `lib/` contiene il codice dell’app (Flutter).
- `pubspec.yaml` elenca le librerie che servono.
- `compila-apk.yml` è l’automazione che fa compilare l’app a GitHub.
- `firma/` contiene la chiave che firma l’app, sempre la stessa a ogni versione.
- `LEGGIMI.md` è questo file.

## Come ottenere l’APK (una volta sola, circa 15 minuti)

1. Estrai lo zip sul computer.
2. Crea un account gratuito su [github.com](https://github.com).
3. In alto a destra premi **+** e poi **New repository**. Come nome scrivi `elo-serie-a`, scegli **Public** e premi **Create repository**. Con “Private” funziona lo stesso, ma per scaricare l’APK dal telefono dovrai accedere a GitHub anche lì.
4. Nella pagina del repository appena creato premi il link **uploading an existing file**. Trascina nella pagina la cartella `lib` e i file `pubspec.yaml`, `LEGGIMI.md` e `compila-apk.yml`. Premi **Commit changes**.
5. Apri la scheda **Actions** e premi **set up a workflow yourself**. Cancella il testo che compare, incolla tutto il contenuto di `compila-apk.yml` (aprilo con il Blocco note) e premi **Commit changes**, due volte se lo chiede.
6. La compilazione parte da sola. Nella scheda **Actions** vedi un pallino giallo che gira: la prima volta servono circa 8–10 minuti. Quando diventa una spunta verde, l’app è pronta.
7. Torna nella scheda **Code**. Sulla destra trovi **Releases**: apri l’ultima e scarica `app-release.apk`.

## Installazione sul telefono

Apri la pagina Releases dal telefono, scarica `app-release.apk` e aprilo. Android chiederà di autorizzare l’installazione da fonti sconosciute per il browser che stai usando: è normale per le app che non vengono dal Play Store.

**Aggiornamenti.** Se in futuro cambi qualcosa nel codice, carica i file nuovi su GitHub e la compilazione riparte da sola. La cartella `firma` contiene la chiave con cui viene firmata l’app: così ogni nuova versione si installa sopra la precedente senza disinstallarla. Serve solo per questa app personale.

## Primo avvio

1. Apri **Impostazioni** e controlla budget, puntata e soglia. I valori iniziali sono 200 €, 2% e 1,05.
2. Torna su **Giornata** e premi **Aggiorna dati**. La prima volta l’app scarica circa 20 stagioni di risultati e calibra il modello: serve circa un minuto. Poi ogni aggiornamento richiede pochi secondi.
3. Apri **Verifica sul passato** e premi **Avvia verifica**. Ti dice se il modello, usato nelle ultime stagioni, avrebbe guadagnato o perso.

## Calibrazione

Con **Calibrazione automatica** attiva (è l’impostazione iniziale) l’app prova centinaia di combinazioni sulle stagioni passate e tiene quella che prevede meglio. Non devi fare nulla. La ripete da sola a ogni nuova stagione, oppure quando premi **Ricalibra ora**.

Se vuoi impostare i valori a mano, disattiva la calibrazione automatica e parti da questi:

| Valore | Da dove partire | Cosa fa |
|---|---|---|
| Fattore K | 20 | Quanto si muovono i punteggi dopo ogni partita |
| Vantaggio casa | 65 | Punti Elo in più per chi gioca in casa |
| Riavvicinamento estivo | 25% | Quanto i punteggi tornano verso la media a inizio stagione |

Poi premi **Ricalcola con questi valori**. La verifica sul passato calibra sempre in automatico sulle stagioni precedenti a quelle provate: così il test resta onesto.

## Elo o Dixon-Coles

In **Impostazioni › Modello** scegli il modello che calcola le previsioni.

- **Elo**: un solo punteggio di forza per squadra. Veloce e semplice.
- **Dixon-Coles**: stima per ogni squadra una forza d’attacco e una di difesa dai gol segnati e subiti, dando più peso alle partite recenti. Stima meglio i pareggi e calcola anche over/under 2,5 e goal/no goal. Il suo parametro è l’**emivita**: con 180 giorni, una partita di sei mesi fa conta la metà di una di oggi. La prima calibrazione può richiedere qualche decina di secondi.

Nella **Verifica sul passato** puoi scegliere il modello e confrontare i due sulle stesse stagioni: vince quello con l’errore più basso. La classifica Elo e quella **Attacco e difesa** sono sempre disponibili in Classifiche.

Le quote over/under arrivano da football-data. Con The Odds API l’app scarica solo le quote 1X2 per non consumare richieste in più, quindi vedrai le probabilità over/under ma non il valore.

## Fonti delle quote

- **football-data (gratis)**: nessuna chiave, quote di alcuni bookmaker. Si aggiornano un paio di volte a settimana, di solito qualche giorno prima della giornata.
- **The Odds API**: quote di molti bookmaker europei, più aggiornate. Serve una chiave gratuita da [the-odds-api.com](https://the-odds-api.com), da incollare nelle Impostazioni. Il piano gratuito ha un numero limitato di richieste al mese, e ogni “Aggiorna dati” ne usa una.

In **Impostazioni › Bookmaker** tieni attivi solo i bookmaker su cui puoi giocare: in Italia, quelli con licenza ADM. Pinnacle, 1xBet e Matchbook sono già esclusi.

## Come leggere i numeri

- **Probabilità**: la stima del modello per 1, X e 2.
- **Quota**: la migliore tra i bookmaker attivi.
- **Valore** = probabilità × quota. Sopra 1 la scommessa è a tuo favore *se il modello ha ragione*. L’app segnala solo quelle sopra la soglia.
- **Quote poi scese** (nella verifica): quante volte la quota presa era più alta di quella di chiusura. Sopra il 50% è il segnale più affidabile che il modello anticipa il mercato.
- **± nel risultato**: il margine d’incertezza dovuto al caso. Se il risultato ci sta dentro, non dimostra niente.

## Limiti da tenere a mente

Il modello conosce solo i risultati: non sa nulla di infortuni, formazioni, turnover o motivazioni. A inizio stagione e sui pareggi è meno preciso. Un Elo semplice raramente batte le quote di chiusura: usalo come strumento di analisi, non come sistema sicuro. Gioca solo cifre che puoi permetterti di perdere. Se il gioco diventa un problema, il Telefono Verde Nazionale per il gioco d’azzardo risponde gratis allo 800 558 822.

Dati storici: [football-data.co.uk](https://www.football-data.co.uk).
