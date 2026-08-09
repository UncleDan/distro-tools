# repo-scripts

Script per copiare la configurazione dei repository APT (e relative chiavi
GPG) da MX Linux a una Debian, per: MX Linux, Google Chrome, TeamViewer,
Visual Studio Code (Microsoft), VSCodium.

## Contenuto

| File | Dove si esegue | Cosa fa |
|---|---|---|
| `esporta-mxrepo.sh` | MX Linux | Estrae repo + chiave MX in `mxrepo/` |
| `esporta-google-chrome.sh` | MX Linux | Estrae repo + chiave Chrome in `chromerepo/` |
| `esporta-teamviewer.sh` | MX Linux | Estrae repo + chiave TeamViewer in `teamviewerrepo/` |
| `esporta-vscode.sh` | MX Linux | Estrae repo + chiave VS Code in `vscoderepo/` (se presente) |
| `esporta-vscodium.sh` | MX Linux | Estrae repo + chiave VSCodium in `vscodiumrepo/` (se presente) |
| `esporta-tutti.sh` | MX Linux | Lancia tutti gli `esporta-*.sh` in sequenza |
| `registra-mxrepo.sh` | Debian (root) | Registra repo + chiave MX da `mxrepo/` |
| `registra-google-chrome.sh` | Debian (root) | Registra repo + chiave Chrome da `chromerepo/` |
| `registra-teamviewer.sh` | Debian (root) | Registra repo + chiave TeamViewer da `teamviewerrepo/` |
| `registra-vscode.sh` | Debian (root) | Registra repo + chiave VS Code da `vscoderepo/` (se presente) |
| `registra-vscodium.sh` | Debian (root) | Registra repo + chiave VSCodium da `vscodiumrepo/` (se presente) |
| `registra-tutti.sh` | Debian (root) | Lancia tutti i `registra-*.sh` in sequenza, poi `apt update` |

## Come si usa

1. **Su MX Linux**, estrai lo zip ed entra nella cartella:
   ```
   cd repo-scripts
   ./esporta-tutti.sh
   ```
   Al termine troverai nella stessa cartella le sottocartelle `mxrepo/`,
   `chromerepo/` e `teamviewerrepo/`, ciascuna con il file
   `*.sources.list` e la relativa chiave GPG (se trovata).

2. **Copia l'intera cartella `repo-scripts`** (script + sottocartelle
   popolate) sulla macchina Debian, ad esempio con una chiavetta USB,
   `scp` o una cartella condivisa.

3. **Su Debian**, entra nella cartella copiata ed esegui come root:
   ```
   cd repo-scripts
   sudo ./registra-tutti.sh
   ```
   Verranno creati i file in `/etc/apt/sources.list.d/`, le chiavi
   copiate in `/etc/apt/trusted.gpg.d/` (o `/etc/apt/keyrings/` per i
   formati `.asc`/`.key`), e infine eseguito `apt update`.

## Eseguire un singolo repository

Se serve solo un repository specifico, si possono lanciare i singoli
script invece di quelli "tutti":

```
# su MX Linux
./esporta-google-chrome.sh

# su Debian, dopo aver copiato la cartella chromerepo/ accanto allo script
sudo ./registra-google-chrome.sh
```

## Permessi e proprietario

- Gli script `esporta-*.sh` **non vanno lanciati con `sudo` davanti**:
  girano come utente normale e usano `sudo` internamente solo per
  leggere gli eventuali file protetti sotto `/etc/apt/`. Alla prima
  lettura protetta viene chiesta la password sudo una sola volta
  (`sudo -v`), poi riutilizzata per il resto dell'esecuzione.
  I file esportati (`mxrepo/`, `chromerepo/`, `teamviewerrepo/`)
  restano di proprieta' dell'utente che ha lanciato lo script, con
  permessi `755` per le cartelle e `644` per i file: si copiano quindi
  liberamente (USB, scp, cartella condivisa) senza problemi di
  permessi.
- Gli script `registra-*.sh` (e `registra-tutti.sh`) **si autoelevano
  con `sudo`** se non vengono lanciati come root: se li avvii senza
  `sudo`, lo script si rilancia da solo chiedendo la password. I file
  installati in `/etc/apt/sources.list.d/`, `/etc/apt/trusted.gpg.d/`
  e `/etc/apt/keyrings/` vengono impostati esplicitamente con
  proprietario `root:root` e permessi `644` (`755` per la cartella
  `/etc/apt/keyrings` se creata).

## Note

- Gli script di esportazione cercano automaticamente la chiave GPG
  associata al repository (tramite `signed-by=` / `Signed-By:` nei file
  apt, oppure cercando file con il nome del prodotto in
  `/etc/apt/trusted.gpg.d`, `/etc/apt/keyrings`, `/usr/share/keyrings`).
  Se non trovano nulla, avvisano a schermo: in tal caso copia la chiave
  a mano nella sottocartella corrispondente prima di spostarti su Debian.
- Gli script di registrazione vanno sempre eseguiti con `sudo` /come
  root, perché scrivono in `/etc/apt/`.
- `registra-tutti.sh` continua con gli script successivi anche se uno
  di essi fallisce (ad es. cartella mancante), segnalando l'errore a
  schermo.
- Se un repository non è installato su MX Linux (ad es. VS Code o
  VSCodium non presenti), lo script di esportazione lo segnala a
  schermo e non crea il file `*.sources.list`: la sottocartella resta
  vuota. Lo script di registrazione corrispondente rileva l'assenza,
  lo segnala e si ferma senza errori, senza toccare `/etc/apt/`.
