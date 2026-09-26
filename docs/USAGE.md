# TNGBackup - Guida all'Uso

TNGBackup ("The Next Generation Backup") è un wrapper Bash attorno a
[Borg Backup](https://www.borgbackup.org/). Centralizza la configurazione del
repository, la gestione delle credenziali, la politica di retention e l'audit
logging, in modo che un'intera routine di backup possa essere espressa in un
unico piccolo file di configurazione e pilotata con un solo comando.

Questo documento descrive la versione **2.0.9** dello script `tngbackup`.

---

## Indice

1. [Stato e testing](#stato-e-testing)
2. [Requisiti](#requisiti)
3. [Installazione](#installazione)
4. [Concetti](#concetti)
5. [Sintassi della riga di comando](#sintassi-della-riga-di-comando)
6. [Riferimento del file di configurazione](#riferimento-del-file-di-configurazione)
7. [Formati dell'URI del repository](#formati-delluri-del-repository)
8. [Modalità dry-run](#modalità-dry-run)
9. [Operazioni](#operazioni)
   - [init](#init)
   - [backup](#backup)
   - [list](#list)
   - [mount](#mount)
   - [check](#check)
   - [prune](#prune)
   - [compact](#compact)
   - [info](#info)
   - [delete](#delete)
   - [extract](#extract)
10. [Menu interattivo](#menu-interattivo)
11. [Politica di retention](#politica-di-retention)
12. [Modalità batch](#modalità-batch)
13. [Logging](#logging)
14. [Note di sicurezza](#note-di-sicurezza)
15. [Pianificazione](#pianificazione)
16. [Risoluzione dei problemi](#risoluzione-dei-problemi)
17. [Codici di uscita](#codici-di-uscita)
18. [Test](#test)

---

## Stato e testing

Tutte e dieci le operazioni - `init`, `backup`, `list`, `mount`, `check`, `prune`,
`compact`, `info`, `delete` e `extract` - sono implementate e instradate
attraverso un'unica funzione condivisa `dispatch_operation`, usata in modo
identico dalle esecuzioni a configurazione singola e da quelle in batch.

La suite è coperta da due script di test in `tests/`:

| Script | Serve Borg? | Cosa copre |
|---|---|---|
| `tests/dispatch-test.sh` | No | 26 controlli. Mette per primo nel `PATH` uno stub `borg` e registra la riga di comando che riceve, così l'elaborazione degli argomenti, il dispatch delle operazioni, il caricamento della configurazione, la precedenza CLI, il dry-run, la modalità batch, il formato dell'audit log e la mappatura dei codici di uscita successo/warning/fallimento sono tutti verificabili ovunque. |
| `tests/integration-test.sh` | Sì | Crea un repository Borg usa e getta in una directory temporanea, esercita davvero ogni operazione contro di esso, verifica l'audit log, poi rimuove tutto. |

```bash
./tests/dispatch-test.sh                          # runs anywhere
./tests/integration-test.sh                       # needs a real Borg
TNGB_TEST_MOUNT=y ./tests/integration-test.sh     # also exercises mount (needs FUSE)
```

Vedi [Test](#test) per i codici di uscita e i dettagli.

Borg stesso cambia comportamento tra versioni major (in particolare 1.x contro
2.x: indirizzamento degli archivi, `borg init` contro `borg repo-create`,
semantica della compattazione). TNGBackup punta alla sintassi dei comandi Borg
1.2/1.3. Esegui il test di integrazione contro la versione di Borg installata
prima di mettere lo strumento in produzione, e prova un ripristino almeno una
volta.

---

## Requisiti

| Componente | Minimo | Note |
|---|---|---|
| Bash | 4.0 | Lo script usa `mapfile`, array, `read -ra`, l'indirezione `${!var}` e `set -o pipefail`. Verificato da `install.sh`. |
| Borg Backup | 1.2 (1.3 consigliato) | Deve essere nel `PATH` come `borg`. Controllato da `install.sh` e di nuovo a runtime da `validate_config`. |
| `getopt` | util-linux | GNU `getopt` con supporto alle opzioni lunghe. Il `getopt` integrato BSD/macOS non funziona. |
| `coreutils` | qualsiasi versione recente | `date`, `touch`, `chmod`, `tee`, `mkdir`. |
| Client OpenSSH | qualsiasi versione recente | Solo per repository remoti (`ssh://`). |
| FUSE + `llfuse`/`pyfuse3` | opzionale | Necessario solo per l'operazione `mount`. Installa `borgbackup[fuse]` o l'extra fuse della tua distribuzione. |
| `shred` | opzionale | Usato dal trap di pulizia per distruggere i file di configurazione temporanei; in mancanza ricade su `rm -f`. |
| `mountpoint` | opzionale | Usato dal trap di pulizia per rilevare e smontare mount Borg residui. |

Verifica cosa hai:

```bash
bash --version | head -1
borg --version
getopt --test; echo "getopt exit: $?"   # 4 means GNU enhanced getopt
```

TNGBackup è uno strumento Linux/BSD. Non è supportato su Windows tranne che
tramite WSL o Git Bash con GNU getopt disponibile.

---

## Installazione

### Con install.sh

```bash
git clone https://github.com/RedFoxy/TNGBackup.git
cd TNGBackup
sudo ./install.sh
```

L'installatore:

1. Verifica Bash 4.0+ e Borg 1.2+, e avvisa (senza fallire) se `getopt` o
   `ssh` mancano.
2. Installa lo script in `$PREFIX/bin/tngbackup` con modalità 0755
   (`PREFIX` di default è `/usr/local`).
3. Crea `/var/log/tngbackup.log` e `/var/log/tngbackup-audit.log` con
   modalità 0600, oppure esegue `chmod 600` se già esistono.
4. Installa `docs/tngbackup.1` in `$PREFIX/share/man/man1/`.
5. Installa un modello di configurazione in `/etc/tngbackup.conf` con
   modalità 0600 - **solo se quel file non esiste già**, così un
   aggiornamento non sovrascrive mai la configurazione in uso.
6. Installa `tngbackup.service` e `tngbackup.timer` in
   `/etc/systemd/system/` quando quella directory esiste.

I passi da 3 a 6 avvisano e continuano se una destinazione non è scrivibile,
così un'installazione non-root produce comunque un binario funzionante.

Variabili d'ambiente riconosciute dall'installatore:

| Variabile | Default | Scopo |
|---|---|---|
| `PREFIX` | `/usr/local` | Prefisso di installazione. |
| `BIN_DIR` | `$PREFIX/bin` | Destinazione del binario. |
| `MAN_DIR` | `$PREFIX/share/man/man1` | Destinazione della man page. |
| `SYSTEMD_DIR` | `/etc/systemd/system` | Destinazione delle unit. |
| `CONFIG_FILE` | `/etc/tngbackup.conf` | Destinazione del modello di configurazione. |
| `LOG_FILE` | `/var/log/tngbackup.log` | File di log da creare. |
| `AUDIT_LOG_FILE` | `/var/log/tngbackup-audit.log` | Audit log da creare. |

Installazione per singolo utente, senza root:

```bash
PREFIX="$HOME/.local" \
CONFIG_FILE="$HOME/.config/tngbackup.conf" \
LOG_FILE="$HOME/.local/state/tngbackup.log" \
AUDIT_LOG_FILE="$HOME/.local/state/tngbackup-audit.log" \
./install.sh
```

Aiuto e rimozione:

```bash
./install.sh --help
sudo ./install.sh --uninstall
```

`--uninstall` rimuove il binario, la man page e le unit systemd. Lascia
deliberatamente **il file di configurazione ed entrambi i log al loro posto** -
perdere un file di passphrase a causa di una disinstallazione sarebbe
irrecuperabile. Rimuovili a mano se è davvero ciò che vuoi.

### Configurazione dopo l'installazione

```bash
sudo "${EDITOR:-vi}" /etc/tngbackup.conf
sudo chmod 600 /etc/tngbackup.conf
man tngbackup
```

Per la modalità batch, crea invece una directory:

```bash
sudo mkdir -p /etc/tngbackup
sudo chmod 700 /etc/tngbackup
sudo install -m 0600 docs/examples/batch-configs/webserver.conf /etc/tngbackup/
```

---

## Concetti

**La configurazione è sorgente (`source`), non parsata.** `load_config` esegue
`source` sul file di configurazione all'interno della shell in esecuzione.
Questo significa che un file di configurazione è uno script Bash: puoi
calcolare valori, riferirti ad altre variabili e chiamare comandi. Significa
anche che un file di configurazione può eseguire codice arbitrario, motivo per
cui proprietà e permessi contano (vedi
[Note di sicurezza](#note-di-sicurezza)).

**Precedenza, onestamente, per opzione.** L'ordine delle operazioni in
`main()` è: analizza la riga di comando, mostra il menu se non è stata data
alcuna operazione, salva repository e passphrase da CLI, esegui il `source`
del file di configurazione, poi riapplica quei due valori salvati sopra. Quindi:

| Impostazione | Precedenza effettiva |
|---|---|
| `-r` / `--repo` (`REPO_URI`) | **CLI > file di configurazione > ambiente > default.** Riapplicata dopo il sourcing, quindi la CLI vince davvero. |
| `-p` / `--passphrase` (`REPO_PASSPHRASE`) | **CLI > file di configurazione > ambiente > default.** Stesso meccanismo. |
| `--archive`, `--path`, `--mountpoint`, `--log`, `--audit-log` | Applicate **prima** che il file di configurazione venga sourced, quindi un file di configurazione che assegna incondizionatamente `ARCHIVE_NAME`, `RESTORE_PATH`, `MOUNT_PATH`, `LOG_FILE` o `AUDIT_LOG_FILE` sovrascrive il valore della CLI. Lascia quelle variabili fuori dal file di configurazione (o proteggile con `${VAR:-...}`) se vuoi impostarle da riga di comando. |
| `-c` / `--config` | Sempre il valore della CLI - seleziona quale file viene sourced. |
| Tutto il resto | Ambiente > default dello script, poi qualsiasi cosa assegni il file di configurazione. |

In **modalità batch** `--repo` e `--passphrase` non hanno alcun effetto: il
ciclo batch resetta `REPO_URI` e `REPO_PASSPHRASE` prima di eseguire il source
di ogni configurazione, e il passo di riapplicazione non viene raggiunto. Ogni
file di configurazione deve portare il proprio repository e la propria
passphrase, che è appunto il senso della modalità batch.

**Variabili d'ambiente.** Ogni variabile di configurazione ha un
inizializzatore `${VAR:-default}` in cima allo script, quindi esportare la
variabile ne imposta il valore prima che il file di configurazione venga
letto. Un'assegnazione incondizionata nel file di configurazione vince comunque
sull'ambiente.

**Le credenziali vivono nell'ambiente solo per la durata di una chiamata a
Borg.** `setup_borg_env` esporta `BORG_PASSPHRASE` e `BORG_REPO` prima di ogni
invocazione di Borg, e aggiunge automaticamente `BORG_RSH` per i repository
`ssh://`. Il trap `EXIT`/`INT`/`TERM` le annulla tutte alla fine
dell'esecuzione.

**Borg non può mai bloccarsi in attesa di un prompt.** Ogni invocazione di
Borg passa attraverso `run_borg`, che esegue `borg ... < /dev/null`, e lo
script esporta all'avvio `BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes` e
`BORG_RELOCATED_REPO_ACCESS_IS_OK=yes`. Un prompt di conferma quindi fallisce
rapidamente invece di bloccare per sempre un job cron. Entrambe le variabili
rispettano un valore già presente nell'ambiente, quindi puoi impostarne una a
`no` se preferisci che quelle due condizioni interrompano l'esecuzione.

---

## Sintassi della riga di comando

```
tngbackup [OPERATION] [OPTIONS]
```

`OPERATION` è una parola nuda (senza trattino iniziale). Se viene omessa, viene
mostrato il menu interattivo.

| Opzione | Argomento | Descrizione |
|---|---|---|
| `-c`, `--config` | FILE o DIR | File di configurazione da sourced. Se viene data una **directory**, viene usata la modalità batch e ogni file `*.conf` al suo interno viene elaborato a turno. Default: `/etc/tngbackup.conf` (o `$TNGB_CONFIG`). |
| `-r`, `--repo` | URI | URI del repository. Imposta `REPO_URI`, e viene riapplicato dopo il sourcing del file di configurazione. |
| `-p`, `--passphrase` | STRING | Passphrase del repository. Imposta `REPO_PASSPHRASE`, riapplicata dopo il file di configurazione. Da evitare su sistemi condivisi. |
| `--archive` | NAME | Nome dell'archivio. Usato da `backup`, `list`, `check`, `info`, `mount`, e **richiesto** da `delete` ed `extract`. |
| `--path` | PATH | Dipende dal contesto. Con `backup` imposta `BACKUP_PATH`; con ogni altra operazione, `extract` incluso, imposta `RESTORE_PATH`. |
| `--mountpoint` | PATH | Directory di mount per `mount`. Imposta `MOUNT_PATH`. Default `/mnt/borg`. |
| `-l`, `--log` | FILE | Log leggibile per l'uomo. Il file viene creato immediatamente e sottoposto a `chmod 600`. |
| `--audit-log` | FILE | Audit log leggibile da macchina. Creato immediatamente e sottoposto a `chmod 600`. |
| `-h`, `--help` | | Stampa l'help integrato ed esce con 0. |

Note sulla gestione degli argomenti:

- Le opzioni sono analizzate con GNU `getopt`, quindi sia
  `--config=/etc/x.conf` sia `--config /etc/x.conf` sono accettate, così come
  le opzioni brevi raggruppate.
- Un'opzione non riconosciuta fa stampare il testo di aiuto e lo script esce
  con stato 1.
- L'operazione viene presa dal **primo argomento posizionale** dopo `--`.
  `tngbackup --config /etc/tngbackup.conf backup` e
  `tngbackup backup --config /etc/tngbackup.conf` sono equivalenti.
- `--path` è sovraccarico (overloaded). Questa è una fonte comune di
  confusione: con `extract`, `--path` è la *destinazione del ripristino*, non
  un selettore di cosa estrarre.
- `--log` e `--audit-log` creano il proprio file in modo anticipato. Se il
  percorso non è scrivibile (`/var/log` per un utente non-root, ad esempio) lo
  script abortisce sotto `set -e` prima di fare qualunque lavoro. Una volta che
  un file di log *è* configurato, un fallimento successivo nello scriverci
  viene tollerato e non fa mai abortire un backup.

---

## Riferimento del file di configurazione

Un file di configurazione è un frammento Bash. Metti tra virgolette ogni
valore. Un'assegnazione per riga. I commenti iniziano con `#`.

Poiché lo script applica default reali, una configurazione minima è
genuinamente minima:

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_PASSPHRASE='correct horse battery staple'
BACKUP_PATH="/home /etc"
```

Questo eredita la cifratura `repokey-blake2`, le opzioni SSH di default, e la
politica di retention di default - il che significa che `prune` agirà su di
essa, quindi leggi [Politica di retention](#politica-di-retention) prima di
eseguirne una.

### Core

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `TNGB_CONFIG` | percorso | `/etc/tngbackup.conf` | Percorso del file o della directory di configurazione da caricare. Normalmente impostato tramite `--config` o l'ambiente, non dentro un file di configurazione. |
| `DEBUG` | `y`/`n` | `n` | Stampa diagnostiche `[DEBUG]`: caricamento della configurazione, parsing della CLI, la riga di comando Borg esatta, la politica di retention, i passi di pulizia. |
| `DRYRUN` | `y`/`n` | `n` | Registra ogni comando Borg invece di eseguirlo. Vedi [Modalità dry-run](#modalità-dry-run). Indipendente da `DEBUG`. |
| `SHOWTEXT` | `y`/`n` | `y` | Stampa sulla console righe `[INFO]`/`[WARN]`/`[ERROR]` con timestamp. Imposta a `n` per job cron silenziosi che scrivono solo su `LOG_FILE`. |
| `BACKUP` | `y`/`n` | `y` | Flag di compatibilità riservato ereditato dalla v1. Presente con un default; il dispatcher v2 seleziona il lavoro in base al nome dell'operazione. |

```bash
DEBUG="n"
DRYRUN="n"
SHOWTEXT="y"
```

### Repository

| Variabile | Tipo | Default | Richiesta | Descrizione |
|---|---|---|---|---|
| `REPO_URI` | stringa | (vuoto) | sì | Posizione del repository Borg. Percorso locale assoluto oppure URI `ssh://`. Esportata come `BORG_REPO`. |
| `REPO_PASSPHRASE` | stringa | (vuoto) | sì | Passphrase per il repository cifrato. Esportata come `BORG_PASSPHRASE`. |
| `BORG_ENCRYPTION` | stringa | `repokey-blake2` | no | Modalità di cifratura passata a `borg init --encryption=`. Usata solo da `init`. |

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_PASSPHRASE='correct horse battery staple'
BORG_ENCRYPTION="repokey-blake2"
```

Valori validi di `BORG_ENCRYPTION` per Borg 1.x: `none`, `authenticated`,
`authenticated-blake2`, `repokey`, `repokey-blake2`, `keyfile`,
`keyfile-blake2`. `repokey*` conserva la chiave dentro il repository (comodo,
protetto dalla passphrase); `keyfile*` la conserva in
`~/.config/borg/keys` (il repository è inutilizzabile senza quel file -
faccine un backup separato).

`validate_config` rifiuta di eseguire qualsiasi operazione se `REPO_URI` o
`REPO_PASSPHRASE` sono vuoti, anche per un repository non cifrato. Se usi
davvero `--encryption=none`, imposta `REPO_PASSPHRASE` a un qualunque
segnaposto non vuoto; Borg lo ignora.

### Backup

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `BACKUP_PATH` | percorsi separati da spazi | (vuoto) | Cosa sottoporre a backup. Richiesta per l'operazione `backup`. |
| `BACKUP_EXCLUDE` | pattern separati da **punto e virgola** | (vuoto) | Pattern di esclusione. Ogni elemento non vuoto diventa un argomento `--exclude`. |
| `ARCHIVE_NAME` | stringa | (vuoto) | Nome dell'archivio. Se vuoto, `backup` genera `archive-YYYYmmdd-HHMMSS`. |
| `RESTORE_PATH` | percorso | (vuoto) | Directory di destinazione per `extract`. Ricade sulla directory corrente se non impostata. |
| `MOUNT_PATH` | percorso | `/mnt/borg` | Punto di mount per `mount`. Creato automaticamente se mancante. |

```bash
BACKUP_PATH="/home /etc /var/www"
BACKUP_EXCLUDE="*.tmp;*/node_modules;/var/www/*/cache;*/.cache"
ARCHIVE_NAME=""
RESTORE_PATH="/tmp/restore"
MOUNT_PATH="/mnt/borg"
```

Sono in gioco due separatori diversi, e mescolarli è l'errore di
configurazione più frequente:

- `BACKUP_PATH` è separata da **spazi** (viene suddivisa in parole in un
  elenco di destinazioni di backup).
- `BACKUP_EXCLUDE` è separata da **punto e virgola** (viene suddivisa con
  `IFS=';' read -ra`). Uno spazio dentro `BACKUP_EXCLUDE` fa parte del
  pattern, non è un separatore, e i pattern di esclusione contenenti spazi
  funzionano correttamente: la riga di comando Borg viene costruita come un
  array Bash, non per concatenazione di stringhe. Gli elementi vuoti tra i
  punto e virgola vengono ignorati, quindi un `;` finale è innocuo.

`BACKUP_PATH` è comunque suddivisa in parole, quindi **i percorsi sorgente del
backup contenenti spazi non possono essere espressi**. Usa un symlink o un
percorso senza spazi.

`ARCHIVE_NAME` viene usata letteralmente. La sintassi dei segnaposto propria
di Borg (`{hostname}-{now:%Y%m%d}`) passa inalterata e funziona davvero per
`borg create`, ma il log e i record di audit dello script conterrebbero poi il
template non interpolato invece del nome finale dell'archivio. Per audit trail
leggibili preferisci lasciare `ARCHIVE_NAME` vuota, oppure calcolarla nel file
di configurazione:

```bash
ARCHIVE_NAME="$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
```

### Opzioni Borg e SSH

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `BORG_OPT` | stringa | (vuoto) | Opzioni aggiuntive inserite in `borg create`. Suddivisa in parole, quindi nessun singolo argomento può contenere spazi. |
| `SSH_OPT` | stringa | `-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5` | Opzioni del client SSH usate per costruire `BORG_RSH` per i repository remoti. |
| `SSH_PORT` | intero | `22` | Porta SSH per i repository remoti. |

`SSH_OPT` e `SSH_PORT` sono collegate automaticamente. `setup_borg_env`
ispeziona `REPO_URI` prima di ogni chiamata a Borg e, quando inizia con
`ssh://`, esporta:

```
BORG_RSH="ssh $SSH_OPT -p $SSH_PORT"
```

Per un repository locale annulla invece `BORG_RSH`, così un valore residuo non
può filtrare. **Non hai bisogno di esportare `BORG_RSH` da solo.** I default
già ti danno le tre opzioni che contano per i backup non presidiati:
`BatchMode=yes` così una chiave rotta fallisce rapidamente invece di chiedere
conferma, `StrictHostKeyChecking=accept-new` così una prima connessione riesce
e la chiave dell'host viene poi fissata, e `ConnectTimeout=5` così un server
irraggiungibile non consuma l'intera finestra di backup.

Sovrascrivi `SSH_OPT` quando serve una chiave specifica o dei keepalive -
ricorda che stai sostituendo il default, quindi ripeti le opzioni che vuoi
comunque mantenere:

```bash
SSH_PORT="2222"
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519 -o ServerAliveInterval=30"
```

Se Borg non è nel `PATH` non interattivo del server, aggiungi al file di
configurazione:

```bash
export BORG_REMOTE_PATH="/usr/local/bin/borg"
```

Valori utili per `BORG_OPT`:

| Opzione | Effetto |
|---|---|
| `--compression lz4` | Veloce, rapporto basso. Buono per dati grandi e già compressi. |
| `--compression zstd,10` | Bilanciato. Buona scelta generica. |
| `--compression zstd,22` | Rapporto massimo, lento, pesante per la CPU. |
| `--stats` | Stampa un riepilogo delle dimensioni deduplicate/compresse alla fine. |
| `--exclude-caches` | Salta le directory contrassegnate con `CACHEDIR.TAG`. |
| `--one-file-system` | Non attraversa confini di filesystem. |
| `--checkpoint-interval 900` | Checkpoint ogni 15 minuti in modo che un backup grande interrotto possa riprendere. |
| `--exclude-if-present .nobackup` | Salta le directory contenenti un file marcatore. |

`BORG_OPT` si applica solo a `borg create`. Non viene passata a `check`,
`prune`, `info` o alle altre operazioni.

### Retention

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `KEEP_LAST` | intero | **`10`** | Mantieni gli N archivi più recenti indipendentemente dall'età. |
| `KEEP_HOURLY` | intero | (vuoto) | Mantieni l'archivio più recente per ciascuna delle ultime N ore. |
| `KEEP_DAILY` | intero | **`7`** | Mantieni l'archivio più recente per ciascuno degli ultimi N giorni. |
| `KEEP_WEEKLY` | intero | **`4`** | Mantieni l'archivio più recente per ciascuna delle ultime N settimane. |
| `KEEP_MONTHLY` | intero | **`12`** | Mantieni l'archivio più recente per ciascuno degli ultimi N mesi. |
| `KEEP_YEARLY` | intero | (vuoto) | Mantieni l'archivio più recente per ciascuno degli ultimi N anni. |

Una regola viene applicata solo quando il suo valore è non vuoto **e** diverso
da `"0"`. Sia `KEEP_HOURLY=""` sia `KEEP_HOURLY="0"` disabilitano la regola
oraria.

Nota i default non vuoti: a meno che la tua configurazione non dica altro,
`prune` gira con
`--keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12`. Vedi
[Politica di retention](#politica-di-retention).

### Logging

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `LOG_FILE` | percorso | (vuoto) | Log leggibile per l'uomo. Viene appeso da `log()`, e l'output combinato di Borg viene rediretto (`tee`) al suo interno. Quando è vuoto, l'output di Borg va semplicemente su stdout. |
| `AUDIT_LOG_FILE` | percorso | (vuoto) | Audit trail strutturato, una riga per operazione completata. Quando è vuoto, l'audit viene silenziosamente disabilitato. |

```bash
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
```

Quando queste sono impostate con `--log` / `--audit-log` lo script crea i file
e applica la modalità 600. Quando invece sono impostate nel file di
configurazione, i file vengono appesi così come sono; creali tu con i permessi
giusti, oppure lascia che lo faccia `install.sh`:

```bash
sudo install -m 0600 /dev/null /var/log/tngbackup.log
sudo install -m 0600 /dev/null /var/log/tngbackup-audit.log
```

Le scritture su `LOG_FILE` sono best-effort: se il file diventa non scrivibile
a metà esecuzione, il messaggio viene scartato invece di far abortire il
backup.

---

## Formati dell'URI del repository

### Repository locale

Un percorso assoluto su un filesystem montato localmente:

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_URI="/srv/borg/webserver"
```

La directory padre deve esistere ed essere scrivibile. La directory del
repository stessa viene creata da `borg init`. Per un URI locale lo script
annulla esplicitamente `BORG_RSH`, quindi `SSH_OPT` e `SSH_PORT` vengono
ignorate.

Un percorso locale può puntare a un filesystem di rete (NFS, CIFS, sshfs), ma
questo è sconsigliato: il comportamento di locking e fsync di Borg su
filesystem di rete è fragile, e le prestazioni sono molto peggiori di un vero
repository `ssh://`, perché ogni ricerca di chunk diventa un round trip di
rete. Preferisci `ssh://` ogni volta che la macchina di destinazione può
eseguire Borg.

### Repository SSH

```
ssh://user@host:port/absolute/path/to/repo
ssh://user@host/absolute/path/to/repo          # default port 22
ssh://user@host/./relative/to/home             # ./ means relative to $HOME
ssh://user@host/~/backups/repo                 # ~ expansion on the remote side
```

Esempi:

```bash
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/webserver"
REPO_URI="ssh://borg@10.0.0.20:2222/mnt/raid/borg/db"
REPO_URI="ssh://backup@nas.lan/./borg/home"
```

Un URI `ssh://` attiva automaticamente `BORG_RSH="ssh $SSH_OPT -p $SSH_PORT"`.
Mantieni `SSH_PORT` coerente con qualsiasi porta scritta nell'URI stesso.

Requisiti per un repository remoto:

1. Borg deve essere installato anche sull'host **remoto**, e le versioni
   dovrebbero essere compatibili (stessa famiglia major/minor).
2. L'autenticazione basata su chiave deve funzionare in modo non
   interattivo:
   ```bash
   ssh -o BatchMode=yes -p 22 borg@backup.example.com borg --version
   ```
   Se quel comando chiede qualcosa, sistemalo prima di pianificare un backup.
3. La directory padre del percorso remoto deve esistere ed essere scrivibile
   dall'utente SSH.

Irrobustire il lato remoto: restringi la chiave in
`~/.ssh/authorized_keys` del server così che possa servire solo un
repository:

```
command="borg serve --restrict-to-repository /srv/borg/webserver --append-only",restrict ssh-ed25519 AAAA... borg@client
```

`--append-only` significa che un client compromesso può aggiungere archivi ma
non può cancellare la cronologia - una buona difesa contro il ransomware che
va a caccia di backup. Nota che con `--append-only` sul server, `prune`,
`delete` e `compact` dal client non libereranno realmente spazio; la
compattazione va fatta sul server.

---

## Modalità dry-run

`DRYRUN=y` fa sì che ogni invocazione di Borg stampi invece di eseguire.
`run_borg` registra il comando esatto come `[DRY-RUN] borg ...` e restituisce
successo, quindi l'operazione riporta `SUCCESS` e scrive un normale record di
audit senza toccare il repository. Anche la creazione di directory per
`mount` ed `extract` viene saltata.

Viene impostata dall'ambiente o dal file di configurazione - non esiste un
flag CLI, e **non** richiede `DEBUG`:

```bash
# One-off, from the environment
DRYRUN=y tngbackup backup --config /etc/tngbackup.conf

# Show the fully expanded command line as well
DEBUG=y DRYRUN=y tngbackup backup --config /etc/tngbackup.conf

# Check what a retention policy would delete
DRYRUN=y tngbackup prune --config /etc/tngbackup.conf

# Validate an entire batch directory without writing anything
DRYRUN=y tngbackup backup --config /etc/tngbackup/
```

Esempio di output:

```
[2026-09-05 12:41:03] [INFO] Starting backup from: /home /etc /var/www
[2026-09-05 12:41:03] [INFO] [DRY-RUN] borg create --compression zstd,10 --stats --exclude *.tmp --exclude */node_modules ::archive-20260905-124103 /home /etc /var/www
[2026-09-05 12:41:03] [INFO] backup completed successfully
[2026-09-05 12:41:03] [INFO] Operation 'backup' finished with status SUCCESS in 0s
```

Usala per verificare una nuova configurazione, un elenco di esclusioni
modificato, o una directory batch prima che venga eseguita senza presidio per
la prima volta.

Due limiti da tenere a mente:

- La validazione della configurazione si applica comunque, quindi `REPO_URI`,
  `REPO_PASSPHRASE` e un binario `borg` nel `PATH` sono tutti ancora
  richiesti anche per un dry run.
- Un dry run riporta sempre `SUCCESS`, perché nessun comando è stato
  effettivamente eseguito. Dimostra ciò che *verrebbe* eseguito, non che il
  repository sia raggiungibile o la passphrase corretta. Per quello, esegui un
  vero `list`.

Il `--dry-run` proprio di Borg è una cosa diversa e resta disponibile tramite
`BORG_OPT` (`BORG_OPT="--dry-run --list"`), che contatta davvero il repository
e riporta i file che verrebbero archiviati.

---

## Operazioni

Ogni operazione viene invocata allo stesso modo:

```bash
tngbackup OPERATION [OPTIONS]
```

Tutte le operazioni richiedono `REPO_URI` e `REPO_PASSPHRASE` (da
configurazione, ambiente, o `-r`/`-p`), e richiedono `borg` nel `PATH`. Ognuna
di esse chiama prima `setup_borg_env`, così `BORG_REPO`, `BORG_PASSPHRASE` e -
per `ssh://` - `BORG_RSH` sono al loro posto, e ognuna termina attraverso
`finish_operation`, che scrive il record di audit e imposta il codice di
uscita del processo in base al risultato di Borg.

`finish_operation` segue la convenzione a tre vie dei codici di uscita propria
di Borg:

| Uscita Borg | Stato | Registrato come | `tngbackup` esce con |
|---|---|---|---|
| `0` | `SUCCESS` | `INFO`: `<op> completed successfully` | `0` |
| `1` | `WARNING` | `WARN`: `<op> completed with warnings (borg exit 1)` | `0` |
| `>= 2` | `FAILED` | `ERROR`: `<op> failed (borg exit N)` | quel codice |

Un warning significa che l'operazione si è completata ed ha fatto ciò che le
era stato chiesto - un backup che non ha potuto leggere una manciata di file
ha comunque prodotto un archivio - quindi deliberatamente **non** viene
trattato come un fallimento. Viene comunque registrato distintamente
nell'audit log, così puoi monitorarlo separatamente.

I fallimenti rilevati dallo script *prima* che Borg venga invocato - un
`--archive` mancante per `delete`/`extract`, una politica di retention non
configurata per `prune`, un mountpoint o una directory di ripristino non
scrivibili - saltano questa tabella: impostano direttamente `FAILED` ed
escono con 1.

Poiché `BORG_REPO` è esportata, la maggior parte delle operazioni indirizza il
repository implicitamente e gli archivi con la scorciatoia `::name`.

### init

Crea un nuovo repository Borg vuoto in `REPO_URI` usando `BORG_ENCRYPTION`.

Esegue: `borg init --encryption="$BORG_ENCRYPTION" "$REPO_URI"`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`. **Opzionale:** `BORG_ENCRYPTION`.

```bash
# From a config file
tngbackup init --config /etc/tngbackup.conf

# Entirely from the command line
tngbackup init --repo /mnt/backup/borg-repo --passphrase 'correct horse battery staple'

# Config file for everything else, repository overridden on the CLI
tngbackup init --config /etc/tngbackup/webserver.conf \
               --repo ssh://borg@backup.example.com:22/srv/borg/web
```

Esempio di output:

```
[2026-09-05 02:15:11] [INFO] Initializing repository: /mnt/backup/borg-repo
[2026-09-05 02:15:12] [INFO] init completed successfully
[2026-09-05 02:15:12] [INFO] Operation 'init' finished with status SUCCESS in 1s
```

Subito dopo, esporta e conserva la chiave del repository da qualche parte
diverso dal repository stesso:

```bash
BORG_PASSPHRASE='...' borg key export /mnt/backup/borg-repo /root/borg-web.key
chmod 600 /root/borg-web.key
```

Senza la passphrase (e, per le modalità `keyfile`, il file chiave) il
repository diventa permanentemente illeggibile. Non esiste un percorso di
recupero.

Errori comuni:

| Messaggio | Causa | Soluzione |
|---|---|---|
| `A repository already exists at ...` | `init` è stato eseguito due volte | Niente da fare; il repository esiste già. |
| `Missing required configuration: REPO_URI` | Nessun repository configurato | Imposta `REPO_URI` o passa `--repo`. |
| `borg binary not found in PATH` | Borg non installato | Installa `borgbackup`. |
| `Permission denied` sulla directory padre | Impossibile creare la directory del repo | Esegui `mkdir -p` sulla directory padre e correggi la proprietà. |
| Connessione SSH rifiutata/scaduta | Host, porta o chiave errati | Verifica con `ssh -o BatchMode=yes -p PORT user@host borg --version`. |

### backup

Crea un archivio contenente `BACKUP_PATH`, rispettando `BACKUP_EXCLUDE` e
`BORG_OPT`.

Esegue: `borg create [BORG_OPT words] [--exclude PATTERN]... ::ARCHIVE_NAME PATHS...`

La riga di comando viene assemblata come un array Bash, quindi i pattern di
esclusione con spazi sono sicuri. `BORG_OPT` e `BACKUP_PATH` vengono
deliberatamente suddivisi in parole.

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`, `BACKUP_PATH`.
**Opzionale:** `BACKUP_EXCLUDE`, `ARCHIVE_NAME`, `BORG_OPT`.

Se `ARCHIVE_NAME` è vuota, viene generato `archive-YYYYmmdd-HHMMSS` a partire
dall'orologio locale.

```bash
# Standard: everything from the config file
tngbackup backup --config /etc/tngbackup.conf

# Explicit archive name
tngbackup backup --config /etc/tngbackup.conf --archive pre-upgrade-2026-09-05

# Override the source path (--path means BACKUP_PATH for this operation)
tngbackup backup --config /etc/tngbackup.conf --path /var/www

# With logs
tngbackup backup --config /etc/tngbackup.conf \
                 --log /var/log/tngbackup.log \
                 --audit-log /var/log/tngbackup-audit.log
```

Esempio di output con `BORG_OPT="--stats"`:

```
[2026-09-05 03:00:01] [INFO] Starting backup from: /home /etc /var/www
------------------------------------------------------------------------------
Archive name: archive-20260905-030001
Archive fingerprint: 9f3c2b1a...
Time (start): Sat, 2026-09-05 03:00:02
Time (end):   Sat, 2026-09-05 03:04:47
Duration: 4 minutes 45.02 seconds
Number of files: 184203
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:               41.02 GB             28.33 GB              1.11 GB
All archives:              612.44 GB            420.10 GB             52.87 GB
------------------------------------------------------------------------------
[2026-09-05 03:04:47] [INFO] backup completed successfully
[2026-09-05 03:04:47] [INFO] Operation 'backup' finished with status SUCCESS in 286s
```

Note:

- I backup **non** vengono potati (`pruned`) automaticamente a meno che
  `PRUNE_BACKUP` non sia impostato (vedi sotto). Altrimenti esegui `prune` (e
  `compact`) come passi separati - vedi [Pianificazione](#pianificazione).
- Backup consecutivi degli stessi dati sono economici: Borg deduplica a
  livello di chunk, quindi un albero di 40 GB immutato costa pochi megabyte.
- Il codice di uscita 1 di Borg significa "completato con warning" (file
  illeggibili o spariti, ad esempio). L'archivio *è stato* creato, quindi
  TNGBackup registra l'esecuzione come `WARNING`, logga
  `backup completed with warnings (borg exit 1)` e **esce con 0**. Un
  warning non è un fallimento; controlla il log per vedere quali file sono
  stati saltati.
- Per backup di database coerenti, esegui prima il dump e poi fai il backup
  del dump - vedi `docs/examples/batch-configs/database.conf`.

Errori comuni:

| Messaggio | Causa | Soluzione |
|---|---|---|
| `BACKUP_PATH not set; no files to backup` | Sorgente mancante | Imposta `BACKUP_PATH` o passa `--path`. |
| `Repository ... does not exist` | Mai inizializzato e `CREATE_REPO=n` | Esegui prima `tngbackup init`, oppure lascia `CREATE_REPO=y` (il default) per crearlo automaticamente. |
| `Failed to create/acquire the lock` | Esecuzione concorrente o lock residuo | Vedi [Risoluzione dei problemi](#risoluzione-dei-problemi). |
| `passphrase supplied ... is incorrect` | `REPO_PASSPHRASE` errata | Correggi la configurazione; un repository non può essere recuperato senza la passphrase giusta. |
| `Archive ... already exists` | `ARCHIVE_NAME` duplicata | Usa un nome univoco o lascia `ARCHIVE_NAME` vuota. |
| `No space left on device` | Filesystem del repository pieno | Esegui prune e compact, oppure aggiungi capacità. |

#### Hook di backup (`PRERUN` / `POSTRUN`)

Esegue un comando o uno script immediatamente prima e/o dopo il backup:

- **`PRERUN`**: viene eseguito prima di `borg create`. Se esce con codice non
  zero, il backup viene **abortito** (registrato come `FAILED`, con dettaglio
  `PRERUN hook failed` nell'audit log) e `borg create` non viene mai eseguito.
- **`POSTRUN`**: viene sempre eseguito dopo il tentativo di backup (successo,
  warning o fallimento). Il suo stesso stato di uscita viene solo loggato
  (`WARN` se diverso da zero) e non cambia mai lo stato registrato del backup.

Entrambi vengono eseguiti con `bash -c "$PRERUN"` / `bash -c "$POSTRUN"`,
quindi possono essere un singolo comando o una sequenza concatenata con
`&&`/`;`, ed entrambi rispettano `DRYRUN` (registrati come
`[DRY-RUN] PRERUN: ...` / `[DRY-RUN] POSTRUN: ...` senza essere eseguiti
davvero).

```bash
PRERUN="mysqldump -u root -p$DB_PASS mydb > /tmp/mydb.sql"
POSTRUN="rm -f /tmp/mydb.sql"
```

#### Auto-creazione del repository (`CREATE_REPO` / `CREATE_REPO_DIR`)

- **`CREATE_REPO`** (default `y`): se il repository non esiste ancora,
  `backup` lo inizializza automaticamente (`borg init --encryption=$BORG_ENCRYPTION`)
  prima di procedere, invece di fallire con `Repository ... does not exist`.
  Imposta a `n` per richiedere un esplicito `tngbackup init` preventivo.
- **`CREATE_REPO_DIR`** (default `y`, solo repository locali): crea la
  directory padre di `REPO_URI` se manca, prima di controllare se il
  repository stesso esiste.

Per un `REPO_URI` locale, l'esistenza viene verificata in modo economico
cercando un file `config` dentro la directory del repository (così appare un
repository Borg sul disco) - questo evita di affidarsi al codice di uscita di
`borg info`, che può essere diverso da zero per motivi non correlati (un lock
residuo, un errore transitorio) e altrimenti rischierebbe di reinizializzare
un repository perfettamente sano. Per un repository `ssh://` non esiste questa
scorciatoia, quindi `borg info` viene usato come sonda best-effort.

Sotto `DRYRUN=y`, non viene creato o toccato nulla; il log riporta cosa
succederebbe (`[DRY-RUN] Would initialize repository if missing: ...`).

#### Operazioni companion (`CHECK_BACKUP` / `PRUNE_BACKUP` / `COMPACT_BACKUP`)

Esegue automaticamente `check`, `prune` e/o `compact` attorno al backup,
ognuna come propria operazione con la propria voce nell'audit log (così
mantieni la stessa tracciabilità per fase che avresti eseguendole a mano).
Ogni variabile accetta:

- `0` - disabilitata (default)
- `1` - eseguita prima di `borg create`
- `2` - eseguita dopo `borg create`

Quando più variabili sono impostate sulla stessa fase, vengono eseguite in
questo ordine fisso: `check`, `prune`, `compact`. Un `check` richiesto per la
fase `1` verifica sempre l'intero repository (`--repository-only`), mai un
archivio specifico - l'archivio che `backup` sta per creare non esiste ancora.

```bash
# Full pipeline in one command: check -> backup -> prune -> compact
CHECK_BACKUP=1
PRUNE_BACKUP=2
COMPACT_BACKUP=2
```

Nessuna di queste tre operazioni fa mai abortire il backup se fallisce: a
differenza di `PRERUN`, un check/prune/compact companion fallito viene
registrato solo sotto il proprio nome di operazione nell'audit log; `backup`
procede comunque (o mantiene il proprio risultato se ha già girato).

### list

Senza `--archive`, elenca tutti gli archivi nel repository. Con `--archive`,
elenca i file dentro quell'archivio.

Esegue: `borg list` (repository, tramite `BORG_REPO`) oppure
`borg list ::ARCHIVE_NAME`.

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`. **Opzionale:** `ARCHIVE_NAME`.

```bash
# All archives
tngbackup list --config /etc/tngbackup.conf

# Contents of one archive
tngbackup list --config /etc/tngbackup.conf --archive archive-20260905-030001

# Ad-hoc against a repository with no config file
tngbackup list --repo /mnt/backup/borg-repo --passphrase 'secret'
```

Esempio di output (elenco del repository):

```
archive-20260901-030001              Mon, 2026-09-01 03:00:01 [1a2b3c...]
archive-20260902-030001              Tue, 2026-09-02 03:00:02 [4d5e6f...]
archive-20260903-030002              Wed, 2026-09-03 03:00:02 [7a8b9c...]
archive-20260904-030001              Thu, 2026-09-04 03:00:01 [0d1e2f...]
archive-20260905-030001              Fri, 2026-09-05 03:00:01 [3a4b5c...]
```

Esempio di output (elenco di un archivio, troncato):

```
drwxr-xr-x root   root          0 Fri, 2026-09-05 02:11:04 etc
-rw-r--r-- root   root       2907 Thu, 2026-08-21 09:33:10 etc/nginx/nginx.conf
-rw-r--r-- root   root       1421 Wed, 2026-07-02 17:45:51 etc/fstab
```

Elencare un archivio grande produce una quantità di output molto grande.
Incanalalo (pipe):

```bash
tngbackup list --config /etc/tngbackup.conf --archive archive-20260905-030001 \
  | grep 'etc/nginx'
```

`list` è il modo più economico per verificare che le credenziali e la
connettività siano corrette - la sonda di esistenza del repository
consigliata, molto più veloce di `check`.

Il campo dei dettagli del record di audit è il nome dell'archivio, oppure
`all-archives` per un elenco del repository.

Errori comuni:

| Messaggio | Causa | Soluzione |
|---|---|---|
| `Archive ... does not exist` | Refuso in `--archive` | Esegui `list` senza `--archive` per vedere i nomi validi. |
| `Repository ... does not exist` | `REPO_URI` errato | Verifica il percorso/URI. |
| `Connection closed by remote host` | Problema SSH/`borg serve` | Verifica con `ssh -o BatchMode=yes host borg --version`. |

### mount

Monta l'intero repository (ogni archivio come sottodirectory) oppure un
singolo archivio in `MOUNT_PATH`, in sola lettura, via FUSE. Questo è il modo
più comodo per esplorare e recuperare selettivamente file con strumenti
ordinari.

Esegue: `borg mount ::ARCHIVE_NAME "$MOUNT_PATH"`, oppure
`borg mount "$REPO_URI" "$MOUNT_PATH"` quando non viene dato alcun archivio.

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`, `MOUNT_PATH` (default `/mnt/borg`).
**Opzionale:** `ARCHIVE_NAME`.

Il punto di mount viene **creato automaticamente** se non esiste (saltato
sotto `DRYRUN=y`). In caso di successo lo script stampa il suggerimento per
smontare e annulla internamente `MOUNT_PATH`, così il trap di pulizia non
smonterà il mount che hai appena richiesto.

```bash
# Mount the whole repository: one directory per archive
tngbackup mount --config /etc/tngbackup.conf --mountpoint /mnt/borg

# Mount a single archive
tngbackup mount --config /etc/tngbackup.conf \
                --archive archive-20260905-030001 \
                --mountpoint /mnt/borg
```

Esempio di output:

```
[2026-09-05 10:22:14] [INFO] Mounting archive archive-20260905-030001 on /mnt/borg
[2026-09-05 10:22:16] [INFO] Unmount with: borg umount /mnt/borg
[2026-09-05 10:22:16] [INFO] mount completed successfully
```

Esplorazione e smontaggio:

```bash
ls /mnt/borg
cp /mnt/borg/etc/nginx/nginx.conf /tmp/
borg umount /mnt/borg
```

Nota che `borg mount` per default demonizza, quindi il mount sopravvive al
processo `tngbackup` - motivo per cui lo smontaggio è lasciato a te. Smonta
quando hai finito: un mount dimenticato mantiene un lock sul repository e
bloccherà il prossimo backup.

Requisiti ed errori comuni:

| Messaggio | Causa | Soluzione |
|---|---|---|
| `borg: Unrecognized command mount` / `fuse is not installed` | Binding FUSE mancanti | `pip install 'borgbackup[fuse]'` oppure installa il pacchetto `borgbackup-fuse` / `python3-llfuse` della tua distro. |
| `fusermount: failed to open /dev/fuse: Permission denied` | Utente non autorizzato a usare FUSE | Esegui come root o aggiungi l'utente al gruppo `fuse`. |
| `Cannot create mountpoint: ...` | Padre non scrivibile | Scegli un percorso scrivibile o esegui come root. |
| `Device or resource busy` allo smontaggio | Una shell o un processo è dentro il mount | Esci con `cd`, poi `fuser -mv /mnt/borg`. |
| Punto di mount non vuoto | File esistenti in `MOUNT_PATH` | Usa una directory vuota. |

Montare un repository **remoto** funziona ma ogni lettura è un round trip di
rete. Per ripristini di massa, `extract` è molto più veloce.

### check

Verifica la coerenza del repository, oppure l'integrità di un archivio.

Esegue:

- senza `--archive`: `borg check --repository-only`
- con `--archive`: `borg check ::ARCHIVE_NAME`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`. **Opzionale:** `ARCHIVE_NAME`.

Il default è deliberatamente il check **veloce**. `--repository-only` verifica
i file di segmento e l'indice senza leggere e decifrare i dati degli archivi,
quindi un `tngbackup check` di routine è abbastanza economico da poter essere
pianificato settimanalmente. Nominare un archivio passa invece a un check di
coerenza completo dei chunk di quell'archivio.

```bash
# Fast repository-only check
tngbackup check --config /etc/tngbackup.conf

# Full check of one archive
tngbackup check --config /etc/tngbackup.conf --archive archive-20260905-030001
```

Esempio di output di un check pulito del repository:

```
[2026-09-05 04:00:01] [INFO] Checking repository: /mnt/backup/borg-repo
Starting repository check
Starting repository index check
Completed repository check, no problems found.
[2026-09-05 04:01:38] [INFO] check completed successfully
```

Il campo dei dettagli del record di audit è `repository` per un check del
repository, oppure il nome dell'archivio per un check di archivio.

Indicazioni pratiche:

- Un check **completo** di un archivio legge ogni chunk. Verificare ogni
  archivio a turno equivale a una lettura dell'intero repository e può
  richiedere ore; fallo occasionalmente, non ogni notte.
- Per verificare i dati degli archivi periodicamente senza controllare tutto,
  controlla ogni settimana l'archivio più recente per nome e ruota tra
  archivi più vecchi.
- Non eseguire mai casualmente `borg check --repair`. Può scartare dati per
  rendere il repository auto-coerente. Fai prima una copia del repository se
  i dati contano. TNGBackup non passa mai `--repair`.
- Per repository remoti, eseguire `borg check` **sul server** evita di
  trasferire l'intero repository via rete.

| Messaggio | Causa | Soluzione |
|---|---|---|
| `Data integrity error` | Bit rot o file troncato | Controlla prima lo storage sottostante/SMART, poi valuta `--repair` su una copia. |
| Il check sembra bloccato | Lettura completa dell'archivio in corso | Atteso per un check di archivio; monitora l'I/O con `iostat`. |

### prune

Elimina gli archivi che nessuna regola di retention richiede, usando le
variabili `KEEP_*`. La potatura (pruning) contrassegna i dati come inutilizzati;
**non** libera spazio su disco finché non viene eseguito `compact`.

Esegue: `borg prune --list --keep-last=N --keep-daily=N ...`

Solo le regole il cui valore è non vuoto e diverso da `"0"` contribuiscono
un'opzione. `--list` viene sempre passato, così il log mostra esattamente
quali archivi sono stati mantenuti e quali potati.

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`, e almeno una regola `KEEP_*`
attiva.

```bash
tngbackup prune --config /etc/tngbackup.conf
tngbackup prune --config /etc/tngbackup.conf --audit-log /var/log/tngbackup-audit.log

# See what it would do without touching anything
DRYRUN=y DEBUG=y tngbackup prune --config /etc/tngbackup.conf
```

Esempio di output:

```
[2026-09-05 04:30:00] [INFO] Pruning repository: /mnt/backup/borg-repo
Keep         archive-20260905-030001   Fri, 2026-09-05 03:00:01
Keep         archive-20260904-030001   Thu, 2026-09-04 03:00:01
Pruning archive archive-20260820-030001 Wed, 2026-08-20 03:00:01
[2026-09-05 04:30:12] [INFO] prune completed successfully
```

Il campo dei dettagli del record di audit elenca le opzioni di retention che
sono state applicate, così l'audit log registra la politica in vigore al
momento di ogni prune.

**Non c'è modo di far potare tutto.** Se ogni variabile `KEEP_*` è vuota o
`0`, `build_retention_opts` non produce nulla e l'operazione rifiuta di
essere eseguita:

```
[ERROR] No retention policy configured (set at least one of KEEP_LAST, KEEP_HOURLY, KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY, KEEP_YEARLY)
```

Questo viene registrato come un prune `FAILED` nell'audit log ed esce con 1.

Il corollario conta di più: **`KEEP_LAST` ha default 10, e `KEEP_DAILY`,
`KEEP_WEEKLY` e `KEEP_MONTHLY` hanno default rispettivamente 7, 4 e 12.** Un
file di configurazione che non dice nulla sulla retention ha comunque una
politica, ed eseguire `prune` contro di esso eliminerà gli archivi che ne
restano fuori. Prima del primo prune su qualunque repository, conferma la
politica effettiva:

```bash
DEBUG=y DRYRUN=y tngbackup prune --config /etc/tngbackup.conf
# [DEBUG] Retention policy: --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12
```

e fai un dry-run contro l'elenco reale degli archivi con Borg:

```bash
export BORG_PASSPHRASE='...'
borg prune --list --dry-run --keep-last=10 --keep-daily=7 --keep-weekly=4 \
    --keep-monthly=12 /mnt/backup/borg-repo
```

Altre precauzioni:

- Se un repository contiene archivi provenienti da più job diversi,
  restringi la potatura con `--glob-archives`/`--prefix` (rispettivamente
  Borg 1.2/1.3), oppure assegna a ogni job il proprio repository. La modalità
  batch dà a ogni configurazione il proprio `REPO_URI`, che è l'approccio
  pulito.
- Prune usa i **timestamp** degli archivi, non i nomi.
- In modalità batch le variabili `KEEP_*` **non** vengono resettate tra i
  file di configurazione, quindi imposta tutte e sei esplicitamente in ogni
  configurazione batch.

### compact

Riscrive i segmenti del repository per rilasciare fisicamente lo spazio
liberato da `prune` e `delete`.

Esegue: `borg compact`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`.

```bash
tngbackup compact --config /etc/tngbackup.conf
```

Note:

- `compact` esiste da Borg 1.2+. Su Borg 1.1 l'equivalente avveniva
  automaticamente durante `prune`.
- È pesante in termini di I/O e riscrive i file di segmento. Eseguilo dopo
  la potatura, non prima, e non a ogni backup - giornaliero o settimanale
  è più che sufficiente.
- Lo spazio viene liberato solo dopo la compattazione. Se `df` non mostra
  cambiamenti dopo un prune, il motivo è questo.
- Su un remoto append-only, esegui la compattazione lato server.

| Messaggio | Causa | Soluzione |
|---|---|---|
| `Unrecognized command compact` | Borg 1.1 o precedente | Aggiorna a Borg 1.2+; la potatura già compatta sulla 1.1. |
| `Failed to create/acquire the lock` | Un'altra operazione è in esecuzione | Attendi, oppure rimuovi un lock residuo (vedi Risoluzione dei problemi). |

### info

Mostra le statistiche del repository, oppure le statistiche di un archivio
quando viene dato `--archive`.

Esegue: `borg info` oppure `borg info ::ARCHIVE_NAME`.

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`. **Opzionale:** `ARCHIVE_NAME`.

```bash
tngbackup info --config /etc/tngbackup.conf
tngbackup info --config /etc/tngbackup.conf --archive archive-20260905-030001
```

Esempio di output del repository:

```
Repository ID: 9f3c2b1a4d5e6f7a8b9c0d1e2f3a4b5c...
Location: /mnt/backup/borg-repo
Encrypted: Yes (repokey BLAKE2b)
Cache: /root/.cache/borg/9f3c2b1a...
                       Original size      Compressed size    Deduplicated size
All archives:              612.44 GB            420.10 GB             52.87 GB
Unique chunks         Total chunks
       412093             8823910
```

Leggi "Deduplicated size" come lo spazio effettivo occupato dal repository.
Il divario tra questo valore e "Original size" è il beneficio di
deduplicazione e compressione.

### delete

Elimina un archivio nominato.

Esegue: `borg delete ::ARCHIVE_NAME`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`, `ARCHIVE_NAME`.

`--archive` è obbligatorio. Senza di esso l'operazione fallisce
immediatamente e in modo pulito, prima di contattare il repository:

```
[ERROR] delete requires --archive NAME
```

Questa è una protezione deliberata: un `borg delete` nudo avrebbe come
bersaglio l'intero repository, e il wrapper non ne emette mai uno.

```bash
tngbackup delete --config /etc/tngbackup.conf --archive archive-20260820-030001

# Confirm the target first
DRYRUN=y tngbackup delete --config /etc/tngbackup.conf --archive archive-20260820-030001
```

Avvertenze:

- Distruttiva e non annullabile.
- Lo spazio viene rilasciato solo dopo `compact`.
- Per la pulizia di routine, usa `prune` con una politica di retention
  invece di `delete` manuale.

### extract

Ripristina il contenuto di un archivio in una directory.

Esegue, dall'interno della directory di destinazione: `borg extract ::ARCHIVE_NAME`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`, `ARCHIVE_NAME`.
**Opzionale:** `RESTORE_PATH` / `--path`.

`--archive` è obbligatorio:

```
[ERROR] extract requires --archive NAME
```

La destinazione è `RESTORE_PATH` (o `--path`), che ricade sulla **directory
di lavoro corrente** quando nessuna delle due è impostata - quindi passane
sempre una esplicitamente in automazione. La directory viene creata se non
esiste (saltato sotto `DRYRUN=y`), e l'estrazione viene eseguita in una
subshell che vi entra con `cd`, così la directory di lavoro del chiamante
non viene toccata.

```bash
tngbackup extract --config /etc/tngbackup.conf \
                  --archive archive-20260905-030001 \
                  --path /tmp/restore
```

Esempio di output:

```
[2026-09-05 11:03:20] [INFO] Extracting archive archive-20260905-030001 into /tmp/restore
[2026-09-05 11:06:02] [INFO] extract completed successfully
[2026-09-05 11:06:02] [INFO] Operation 'extract' finished with status SUCCESS in 162s
```

Ricorda: con `extract`, `--path` è la **destinazione**, non un selettore di
cosa ripristinare.

Borg ripristina i percorsi così come sono stati archiviati, relativi alla
directory di estrazione. Un archivio di `/etc` estratto in `/tmp/restore`
produce `/tmp/restore/etc/...`. Estrai sempre prima in una directory di
prova, ispeziona il risultato, poi sposta i file al loro posto. Estrarre
direttamente sopra un filesystem in produzione rischia di sovrascrivere dati
buoni con dati vecchi.

Per ripristinare un singolo file o un sottoalbero, usa Borg direttamente - i
selettori di percorso non sono esposti dal wrapper:

```bash
export BORG_PASSPHRASE='...'
cd /tmp/restore
borg extract /mnt/backup/borg-repo::archive-20260905-030001 etc/nginx/nginx.conf
```

Anteprima senza scrivere nulla:

```bash
borg extract --dry-run --list /mnt/backup/borg-repo::archive-20260905-030001
```

| Messaggio | Causa | Soluzione |
|---|---|---|
| `extract requires --archive NAME` | Nessun archivio dato | Passa `--archive`; trova i nomi con `tngbackup list`. |
| `Cannot create restore path: ...` | Padre non scrivibile | Scegli una destinazione scrivibile o esegui come root. |
| `Permission denied` durante la scrittura | Directory di ripristino non scrivibile | Correggi la proprietà, oppure esegui come root per preservare proprietari/modalità. |
| I file finiscono in un posto inatteso | I percorsi dell'archivio sono relativi | Guarda un livello più in profondità: `find /tmp/restore -maxdepth 2`. |
| `No space left on device` | Destinazione del ripristino troppo piccola | Ripristina selettivamente, oppure su un filesystem più grande. |

### break-lock

Rimuove un lock residuo del repository che impedisce le operazioni di backup.

Esegue: `borg break-lock $REPO_URI`

**Richiesta:** `REPO_URI`, `REPO_PASSPHRASE`.

Quando un backup va in crash o viene interrotto senza fare pulizia, Borg
lascia il repository bloccato. I tentativi di backup successivi falliscono
con "Failed to create/acquire the lock (timeout)". Usa `break-lock` per
rimuovere il lock residuo:

```bash
tngbackup break-lock --config /etc/tngbackup.conf
```

**Risoluzione dei problemi:**

| Messaggio | Causa | Soluzione |
|---|---|---|
| `Repository ... does not exist` | `REPO_URI` errato | Verifica il percorso/URI. |
| `passphrase supplied ... is incorrect` | `REPO_PASSPHRASE` errata | Correggi la configurazione. |
| Lock rimosso con successo | Operazione riuscita | Riprova la tua operazione di backup. |

**Nota:** Questa operazione serve solo per la risoluzione dei problemi. Le
normali operazioni di backup non dovrebbero richiedere una rimozione manuale
del lock. Se incontri frequentemente lock residui:
- Valuta di usare `PRERUN="borg break-lock 2>/dev/null || true"` per pulire
  automaticamente prima di ogni backup
- Indaga perché i backup vanno in crash (spazio su disco, permessi, problemi
  di rete)


---

## Menu interattivo

Eseguire `tngbackup` senza alcuna operazione (e senza `--help`) mostra un menu:

```
╔═══════════════════════════════════╗
║      TNGBackup v2.0.9             ║
╚═══════════════════════════════════╝

  1) Initialize repository
  2) Backup
  3) List archives
  4) Mount archive
  5) Check repository
  6) Prune old archives
  7) Compact repository
  8) Repository info
  9) Extract files
 10) Delete archive

  0) Exit (default)

Select [0-10]:
```

Premere Invio senza alcun input seleziona `0` ed esce. Un inserimento non
valido ripresenta il menu.

Il menu viene eseguito **prima** che la configurazione venga caricata e si
limita a impostare `OPERATION`; lo script poi continua normalmente nello
stesso processo. Ogni altra opzione che hai passato sopravvive, quindi
combinare il menu con dei flag funziona come atteso:

```bash
tngbackup --config /etc/tngbackup/webserver.conf \
          --archive archive-20260905-030001 \
          --log /var/log/tngbackup.log
# → pick 3 (List archives): lists that archive, from that config, into that log
```

Lo stesso vale per la modalità batch: scegliere un'operazione dal menu e
passare una **directory** di configurazione esegue quell'operazione su ogni
configurazione al suo interno.

Il menu legge dallo standard input, quindi non deve mai essere usato da cron,
da una unit systemd, o da qualunque altro contesto non interattivo. Nomina
sempre esplicitamente un'operazione lì.

---

## Politica di retention

Le variabili `KEEP_*` si mappano uno a uno sulle opzioni `--keep-*` di prune
di Borg. L'algoritmo di Borg è:

1. Ordina gli archivi dal più recente al più vecchio.
2. Per ogni regola a turno, percorri gli archivi e mantieni l'**archivio più
   recente in ciascun bucket temporale** (ora, giorno, settimana, mese, anno)
   finché non sono stati mantenuti N bucket.
3. Mantieni l'unione delle selezioni di tutte le regole. Elimina tutto il
   resto.

Due conseguenze che sorprendono le persone:

- Le regole **non** sono quote additive su un'unica lista. `KEEP_DAILY=7`
  più `KEEP_WEEKLY=4` non mantiene 11 archivi; la regola settimanale di
  solito riseleziona archivi già mantenuti dalla regola giornaliera, quindi
  il totale reale è più piccolo.
- Una regola "mantiene gli ultimi N periodi che contengono un archivio", non
  "gli ultimi N periodi di calendario". Se la macchina è rimasta spenta per
  un mese, la regola mensile va a cercare più indietro invece di perdere uno
  slot.

### I default

A differenza della maggior parte delle impostazioni, la retention **non** è
vuota per default:

```
KEEP_LAST=10   KEEP_HOURLY=(none)   KEEP_DAILY=7
KEEP_WEEKLY=4  KEEP_MONTHLY=12      KEEP_YEARLY=(none)
```

quindi una configurazione che non menziona mai la retention pota comunque con
`--keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12`: circa
20 archivi che coprono all'incirca un anno. È un default ragionevole, ma è
una politica reale che eliminerà archivi, quindi decidi consapevolmente
invece di ereditarla per caso. Imposta le variabili esplicitamente in ogni
file di configurazione che scrivi.

Per disabilitare una singola regola, impostala a `0` o `""`. Impostare
**tutte e sei** a `0` non pota tutto - fa sì che `prune` rifiuti di essere
eseguito e segnali un fallimento.

### Esempio pratico 1 - server giornaliero, storico di tre mesi

```bash
KEEP_LAST="3"
KEEP_HOURLY=""
KEEP_DAILY="7"
KEEP_WEEKLY="4"
KEEP_MONTHLY="3"
KEEP_YEARLY=""
```

Un backup a notte. Dopo un anno di esecuzione, il repository contiene
all'incirca:

| Regola | Mantiene | Archivi approssimativi |
|---|---|---|
| `KEEP_LAST=3` | i 3 più recenti, incondizionatamente | 3 (tutti si sovrappongono all'insieme giornaliero) |
| `KEEP_DAILY=7` | l'archivio più recente per ciascuno degli ultimi 7 giorni | 7 |
| `KEEP_WEEKLY=4` | il più recente per ciascuna delle ultime 4 settimane | ~3 nuovi (1 si sovrappone all'insieme giornaliero) |
| `KEEP_MONTHLY=3` | il più recente per ciascuno degli ultimi 3 mesi | ~2 nuovi (1 si sovrappone all'insieme settimanale) |

Totale: circa 12 archivi, che coprono all'incirca 90 giorni. La granularità
di recupero è di un giorno per l'ultima settimana, una settimana per l'ultimo
mese, un mese per l'ultimo trimestre.

### Esempio pratico 2 - backup orari di un database molto attivo

```bash
KEEP_LAST="2"
KEEP_HOURLY="24"
KEEP_DAILY="7"
KEEP_WEEKLY="4"
KEEP_MONTHLY=""
KEEP_YEARLY=""
```

Un backup all'ora. Mantenuti: 24 punti orari che coprono l'ultimo giorno,
poi punti giornalieri per una settimana, poi punti settimanali per un mese -
circa 32 archivi. È la forma giusta per dati in cui un errore viene
solitamente notato entro poche ore.

### Esempio pratico 3 - retention legale a lungo termine

```bash
KEEP_LAST="5"
KEEP_HOURLY=""
KEEP_DAILY="14"
KEEP_WEEKLY="8"
KEEP_MONTHLY="24"
KEEP_YEARLY="7"
```

Circa 45 archivi che coprono sette anni. La deduplicazione rende questo
molto più economico di quanto sembri quando i dati cambiano lentamente, ma
significa anche che il repository non smette mai di crescere; controlla
periodicamente l'output di `info`.

### `KEEP_LAST`

`KEEP_LAST=N` mantiene gli N archivi più recenti indipendentemente dal
tempo. Usalo come rete di sicurezza combinata con le regole basate sul
tempo: l'unione contiene sempre almeno gli N archivi più recenti, anche se
le regole basate sul tempo ne selezionassero di meno.

### Validare una politica

Due passi, in ordine. Prima conferma cosa passerà lo script:

```bash
DEBUG=y DRYRUN=y tngbackup prune --config /etc/tngbackup.conf
```

Poi conferma cosa farebbe Borg con essa, contro l'elenco reale degli
archivi:

```bash
export BORG_PASSPHRASE='...'
borg prune --list --dry-run \
    --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12 \
    /mnt/backup/borg-repo
```

L'output contrassegna ogni archivio come `Keep` o `Would prune`:

```
Keep         archive-20260905-030001   Fri, 2026-09-05 03:00:01
Keep         archive-20260904-030001   Thu, 2026-09-04 03:00:01
Would prune  archive-20260820-030001   Wed, 2026-08-20 03:00:01
```

Poi ricorda che la potatura non libera nulla finché non gira `compact`.

---

## Modalità batch

Passare una **directory** a `--config` (o impostare `TNGB_CONFIG` a una
directory) fa passare TNGBackup in modalità batch. Ogni file `*.conf`
direttamente dentro la directory viene elaborato a turno, nell'ordine dei
glob della shell (di fatto alfabetico).

Per ogni file lo script:

1. Logga `Processing: <file>`.
2. Resetta `REPO_URI`, `REPO_PASSPHRASE`, `BACKUP_PATH`, `BACKUP_EXCLUDE` e
   `ARCHIVE_NAME` a vuoto, così una configurazione non può ereditare
   silenziosamente il repository, le credenziali, le sorgenti, le esclusioni
   o il nome dell'archivio di un'altra.
3. Esegue il source del file di configurazione. Un file che fallisce il
   sourcing viene registrato come warning e saltato; il batch continua.
4. Valida la configurazione. Una validazione fallita viene conteggiata come
   fallimento e il file viene saltato.
5. Esegue l'operazione richiesta attraverso la stessa funzione
   `dispatch_operation` usata dalle esecuzioni a configurazione singola.

La modalità batch supporta **tutte e dieci le operazioni** - qualunque
operazione tu nomini (o scelga dal menu) viene applicata a ogni
configurazione nella directory. `backup`, `check` e `prune` sono quelle che
hanno senso senza presidio; `mount` su un'intera directory è raramente ciò
che vuoi.

I fallimenti vengono conteggiati, non ignorati: il batch viene eseguito fino
al completamento, e lo script **esce con codice diverso da zero se una
qualunque configurazione è fallita**. Una configurazione la cui operazione è
terminata con un *warning* di Borg non viene conteggiata come fallimento - ha
comunque prodotto il suo risultato - ma viene comunque registrata
distintamente come `WARNING` nell'audit log.

**Cosa continua a passare tra i file:** `BORG_OPT`, tutte e sei le
variabili `KEEP_*`, `RESTORE_PATH`, `MOUNT_PATH`, `SSH_OPT`, `SSH_PORT`,
`BORG_ENCRYPTION`, `LOG_FILE`, `AUDIT_LOG_FILE`, `DEBUG`, `DRYRUN` e
`SHOWTEXT` **non** vengono resettate. Scrivi le configurazioni batch in modo
difensivo: imposta esplicitamente in ogni file ogni variabile che ti
interessa, incluse quelle vuote. Le configurazioni batch di esempio in
`docs/examples/batch-configs/` seguono questa regola, e le variabili di
retention sono quelle che contano di più - un `prune` che eredita
`KEEP_YEARLY` dalla configurazione precedente è un bug silenzioso di
retention dei dati.

`--repo` e `--passphrase` vengono ignorati in modalità batch: il ciclo
resetta entrambi prima di eseguire il source di ogni file. Ogni
configurazione porta la propria.

### Esempio pratico

Struttura:

```
/etc/tngbackup/            (mode 0700, root:root)
├── database.conf          (mode 0600)
├── home.conf              (mode 0600)
└── webserver.conf         (mode 0600)
```

Ogni file punta al proprio repository:

```bash
# webserver.conf
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/webserver"
BACKUP_PATH="/var/www /etc/nginx"

# database.conf
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/database"
BACKUP_PATH="/var/backups/mysql"

# home.conf
REPO_URI="/mnt/backup/borg/home"
BACKUP_PATH="/home"
```

Convalida l'intera directory senza scrivere nulla:

```bash
DRYRUN=y tngbackup backup --config /etc/tngbackup/
```

Poi eseguilo per davvero:

```bash
tngbackup backup --config /etc/tngbackup/ \
                 --log /var/log/tngbackup.log \
                 --audit-log /var/log/tngbackup-audit.log
```

Output:

```
[2026-09-05 03:00:01] [INFO] Processing: /etc/tngbackup/database.conf
[2026-09-05 03:00:01] [INFO] Starting backup from: /var/backups/mysql
[2026-09-05 03:01:12] [INFO] backup completed successfully
[2026-09-05 03:01:12] [INFO] Processing: /etc/tngbackup/home.conf
[2026-09-05 03:01:12] [INFO] Starting backup from: /home
[2026-09-05 03:09:55] [INFO] backup completed successfully
[2026-09-05 03:09:55] [INFO] Processing: /etc/tngbackup/webserver.conf
[2026-09-05 03:09:55] [INFO] Starting backup from: /var/www /etc/nginx
[2026-09-05 03:14:30] [INFO] backup completed successfully
[2026-09-05 03:14:30] [INFO] Batch processing complete: 3 config(s) processed, 0 failed
[2026-09-05 03:14:30] [INFO] Batch run completed in 869s
```

Con un fallimento la parte finale recita:

```
[2026-09-05 03:09:55] [WARN] Operation 'backup' failed for: /etc/tngbackup/webserver.conf
[2026-09-05 03:14:30] [INFO] Batch processing complete: 3 config(s) processed, 1 failed
```

e il processo esce con 1.

Poi pota tutte e tre con la stessa forma di comando:

```bash
tngbackup prune --config /etc/tngbackup/ --audit-log /var/log/tngbackup-audit.log
```

Comportamento del batch degno di nota:

- I job girano **sequenzialmente**, mai in parallelo. Il tempo totale è la
  somma.
- Un job fallito non abortisce il batch, ma cambia lo stato di uscita -
  quindi `systemd` e `cron` segnaleranno il fallimento normalmente.
- L'ordinamento è alfabetico, quindi anteponi un prefisso ai nomi dei file
  se l'ordine conta: `10-database.conf`, `20-webserver.conf`,
  `50-home.conf`.
- Vengono raccolti solo i file `*.conf`. Disabilita un job rinominandolo
  `webserver.conf.disabled`.
- Le sottodirectory non vengono cercate.
- La riga finale `Batch run completed in Ns` riporta il tempo totale di
  esecuzione.

---

## Logging

TNGBackup scrive due flussi indipendenti.

### Log leggibile per l'uomo (`-l` / `--log` / `LOG_FILE`)

Ogni chiamata a `log()` viene appesa, e l'output combinato di Borg viene
rediretto (`tee`) nello stesso file. Formato:

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] message
```

I livelli sono `ERROR`, `WARN`, `INFO`, `DEBUG` (quest'ultimo solo quando
`DEBUG=y`). I timestamp usano l'ora locale.

```
[2026-09-05 03:00:01] [INFO] Starting backup from: /var/www /etc/nginx
[2026-09-05 03:04:47] [INFO] backup completed successfully
[2026-09-05 03:04:47] [INFO] Operation 'backup' finished with status SUCCESS in 286s
```

Un'esecuzione completata con warning ha questo aspetto - nota il livello
`WARN` e lo stato `WARNING`, e che l'archivio esiste:

```
[2026-09-05 03:05:12] [INFO] Starting backup from: /home
/home/alice/.gvfs: open: Permission denied
[2026-09-05 03:09:22] [WARN] backup completed with warnings (borg exit 1)
[2026-09-05 03:09:22] [INFO] Operation 'backup' finished with status WARNING in 250s
```

Quando impostato tramite `--log`, il file viene creato e sottoposto a
`chmod 600` prima che venga scritto qualunque cosa. Quando non è configurato
alcun file di log, l'output di Borg va su stdout inalterato - un `--log`
mancante non sopprime né interrompe mai l'output.

Le scritture sono best-effort: se il file di log diventa non scrivibile a
metà esecuzione, il messaggio viene scartato invece di far abortire il
backup.

### Audit log (`--audit-log` / `AUDIT_LOG_FILE`)

Un record delimitato da pipe per ogni operazione completata, progettato per
essere analizzato:

```
TIMESTAMP_UTC_ISO8601 | operation | status | details | duration_seconds
```

| Campo | Descrizione |
|---|---|
| `TIMESTAMP_UTC_ISO8601` | UTC, `%Y-%m-%dT%H:%M:%SZ`, ad es. `2026-09-05T03:04:47Z`. |
| `operation` | `init`, `backup`, `list`, `check`, `prune`, `compact`, `info`, `mount`, `delete`, `extract`. |
| `status` | Uno tra `SUCCESS`, `WARNING` o `FAILED`. `WARNING` significa che Borg è uscito con 1 - l'operazione si è completata, ma qualcosa era degno di nota (tipicamente file illeggibili o spariti). `FAILED` significa che Borg è uscito con 2 o più, oppure che lo script ha rifiutato la richiesta prima di invocare Borg. |
| `details` | Contesto: nome dell'archivio, URI del repository, `all-archives`, `repository`, le opzioni di retention applicate da `prune`, oppure `ARCHIVE -> TARGET` per `mount` ed `extract`. |
| `duration_seconds` | Secondi interi trascorsi dall'avvio dello script. |

Esempio:

```
2026-09-05T02:15:12Z | init | SUCCESS | /mnt/backup/borg-repo | 1
2026-09-05T03:04:47Z | backup | SUCCESS | archive-20260905-030001 | 286
2026-09-05T03:09:22Z | backup | WARNING | archive-20260905-030512 | 250
2026-09-05T03:14:30Z | backup | FAILED | archive-20260905-030955 | 275
2026-09-05T04:01:38Z | check | SUCCESS | repository | 97
2026-09-05T04:30:12Z | prune | SUCCESS | --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12 | 12
2026-09-05T11:06:02Z | extract | SUCCESS | archive-20260905-030001 -> /tmp/restore | 162
```

La riga `WARNING` sopra è un backup reale: esiste un archivio chiamato
`archive-20260905-030512` e può essere usato per un ripristino. Qualcosa è
stato saltato, e il log operativo dice cosa.

In modalità batch ogni configurazione contribuisce con il proprio record,
quindi un batch di tre configurazioni scrive tre righe.

Se `AUDIT_LOG_FILE` è vuoto, l'audit viene silenziosamente disabilitato.

Query utili:

```bash
# Real failures only - warnings are excluded, which is usually what you want
awk -F' \\| ' '$3=="FAILED"' /var/log/tngbackup-audit.log | tail -50

# Anything that was not a clean success, warnings included
awk -F' \\| ' '$3!="SUCCESS"' /var/log/tngbackup-audit.log | tail -50

# Warnings only - archives that exist but skipped something
awk -F' \\| ' '$3=="WARNING"{print $1, $2, $4}' /var/log/tngbackup-audit.log

# Slowest backups
awk -F' \\| ' '$2=="backup"{print $5, $4}' /var/log/tngbackup-audit.log \
  | sort -rn | head -10

# Which retention policy was in force at each prune
awk -F' \\| ' '$2=="prune"{print $1, $4}' /var/log/tngbackup-audit.log

# Alert if no backup completed today. A WARNING still produced an archive,
# so it counts as a backup having happened - match both statuses.
today=$(date -u +%Y-%m-%d)
grep -qE "^${today}.*\| backup \| (SUCCESS|WARNING) \|" /var/log/tngbackup-audit.log \
  || echo "NO BACKUP TODAY" | mail -s "Backup alert" ops@example.com
```

La distinzione conta quando scrivi il monitoraggio: un grep su `FAILED`
ora ignora correttamente i warning, quindi ti avvisa solo per i backup che
davvero non sono avvenuti. Tratta `WARNING` come qualcosa da rivedere
piuttosto che qualcosa per cui svegliarsi - ma rivedilo comunque, poiché un
numero crescente di file saltati è il modo in cui un problema di permessi o
hardware si annuncia.

### Rotazione dei log

Nessuno dei due file viene ruotato dallo script. Aggiungi
`/etc/logrotate.d/tngbackup`:

```
/var/log/tngbackup.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0600 root root
}

/var/log/tngbackup-audit.log {
    monthly
    rotate 36
    compress
    delaycompress
    missingok
    notifempty
    create 0600 root root
}
```

Mantieni l'audit log molto più a lungo del log operativo: è piccolo, ed è
il record che dimostra che i backup stavano girando.

---

## Note di sicurezza

### La passphrase

Perdere la passphrase significa perdere permanentemente i backup. Perderne
il controllo significa che qualcun altro può leggerli. Entrambe le modalità
di fallimento sono irrecuperabili, quindi trattala di conseguenza.

- Conservala in un password manager o in un secrets store, separatamente
  dalla macchina di cui viene fatto il backup. Una passphrase che esiste
  solo sul server che protegge diventa inutile dopo che quel server muore.
- Esporta e conserva anche la chiave del repository:
  ```bash
  borg key export /mnt/backup/borg-repo /root/borg-repo.key
  chmod 600 /root/borg-repo.key
  ```
  Per le modalità di cifratura `keyfile*` questo è obbligatorio - la chiave
  vive solo in `~/.config/borg/keys` e il repository non può essere aperto
  senza di essa.

### Non passare la passphrase sulla riga di comando

`-p` / `--passphrase` è comodo per lavoro locale occasionale e pericoloso
altrove. Su un sistema multi-utente, la riga di comando completa di ogni
processo è leggibile da chiunque:

```bash
ps auxww | grep tngbackup     # any user can see this
```

Finisce anche nella cronologia della shell. Lo script disabilita la
registrazione della cronologia della propria shell (`set +o history`), ma
questo non pulisce la shell interattiva in cui hai digitato il comando.
Preferisci, in ordine:

1. Un file di configurazione con `chmod 600` contenente `REPO_PASSPHRASE`.
2. `BORG_PASSPHRASE` esportata da uno script wrapper protetto o da un
   `EnvironmentFile` systemd con modalità 600.
3. `BORG_PASSCOMMAND`, che lascia a Borg il compito di recuperare il segreto
   da un portachiavi o un secret store:
   ```bash
   export BORG_PASSCOMMAND='secret-tool lookup borg repo webserver'
   ```
   Nota che `validate_config` richiede comunque una `REPO_PASSPHRASE` non
   vuota, quindi imposta un segnaposto se guidi Borg interamente tramite
   `BORG_PASSCOMMAND`.

L'audit log non registra mai la passphrase, e `tests/dispatch-test.sh`
verifica che nessuna passphrase finisca in nessuno dei due file di log.

### Permessi dei file

| File | Modalità | Proprietario |
|---|---|---|
| `/etc/tngbackup.conf` | 0600 | root:root |
| `/etc/tngbackup/` | 0700 | root:root |
| `/etc/tngbackup/*.conf` | 0600 | root:root |
| `/var/log/tngbackup.log` | 0600 | root:root |
| `/var/log/tngbackup-audit.log` | 0600 | root:root |
| file di chiave esportati | 0600 | root:root |

`install.sh` crea il modello di configurazione ed entrambi i log con
modalità 0600. Se aggiungi file a mano:

```bash
sudo chmod 600 /etc/tngbackup.conf
sudo chmod 700 /etc/tngbackup
sudo chmod 600 /etc/tngbackup/*.conf
sudo chmod 600 /var/log/tngbackup*.log
```

Verifica periodicamente:

```bash
find /etc/tngbackup* /var/log/tngbackup*.log \
     \( -perm /o+rwx -o -perm /g+w \) -ls
```

Qualunque cosa stampata da quel comando è troppo permissiva.

### I file di configurazione vengono eseguiti

`load_config` usa `source`. Un file di configurazione è codice in
esecuzione, con i privilegi dell'utente che invoca - solitamente root. Non
eseguire mai il source di un file di configurazione che non hai scritto, non
rendere mai la directory di configurazione scrivibile dal gruppo o da
tutti, e non tenere mai un file di configurazione con una passphrase reale
dentro un repository git. Aggiungi a `.gitignore`:

```
*.conf
!docs/examples/**/*.conf
```

### Igiene SSH

- Usa una chiave dedicata per client, senza passphrase (così può girare
  senza presidio), protetta dai permessi dei file.
- Restringi la chiave sul server con
  `command="borg serve --restrict-to-repository ... --append-only",restrict`.
- Il `SSH_OPT` di default include già `BatchMode=yes`, così una chiave
  mancante fallisce rapidamente invece di bloccarsi. Se sovrascrivi
  `SSH_OPT`, mantienilo.
- `StrictHostKeyChecking=accept-new` (anch'esso un default) si fida della
  chiave dell'host al primo contatto. È un compromesso ragionevole per
  l'automazione, ma su una rete ostile pre-semina `known_hosts` e usa invece
  `StrictHostKeyChecking=yes`:
  ```bash
  ssh-keyscan -p 22 backup.example.com >> /root/.ssh/known_hosts
  ```

### Default non interattivi di Borg

Lo script esporta `BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes` e
`BORG_RELOCATED_REPO_ACCESS_IS_OK=yes` così che Borg non possa mai
bloccarsi su quei due prompt di conferma. Entrambi sono prompt di sicurezza,
e sopprimerli è un compromesso deliberato: l'affidabilità delle esecuzioni
non presidiate a scapito di un warning a cui comunque non potresti
rispondere. Entrambi rispettano un valore già presente nell'ambiente, quindi
imposta uno dei due a `no` se preferisci che quelle condizioni interrompano
l'esecuzione:

```bash
BORG_RELOCATED_REPO_ACCESS_IS_OK=no tngbackup backup --config /etc/tngbackup.conf
```

### Comportamento di pulizia

Il trap `EXIT`/`INT`/`TERM` annulla `REPO_PASSPHRASE`, `BORG_PASSPHRASE`,
`BORG_RSH`, `REPO_URI` e `BACKUP_PATH`, esegue `shred` su qualunque file di
configurazione temporaneo che ha creato, e tenta di smontare un `MOUNT_PATH`
residuo. Un `mount` riuscito annulla prima `MOUNT_PATH`, così il trap non
smonta mai un mount che hai richiesto tu. Questo limita l'esposizione entro
la durata di vita del processo; non protegge il file di configurazione su
disco, motivo per cui i permessi contano.

### Output di DEBUG

`DEBUG=y` stampa diagnostiche compresa la riga di comando completa di Borg
e la politica di retention. Non stampa la passphrase, ma descrive la
struttura del tuo repository - rivedi l'output prima di incollarlo in una
segnalazione di bug o in una chat.

---

## Pianificazione

Le esecuzioni non presidiate devono sempre nominare esplicitamente
un'operazione - altrimenti il menu interattivo si blocca per sempre su
`read`.

### cron

Modifica il crontab di root con `crontab -e`:

```cron
# Environment for all jobs below
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=ops@example.com

# Nightly backup at 03:00
0 3 * * * /usr/local/bin/tngbackup backup --config /etc/tngbackup.conf \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log

# Prune at 04:00, then compact at 04:30
0 4 * * * /usr/local/bin/tngbackup prune --config /etc/tngbackup.conf \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log
30 4 * * * /usr/local/bin/tngbackup compact --config /etc/tngbackup.conf \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log

# Weekly repository check, Sunday 05:00 (fast: --repository-only)
0 5 * * 0 /usr/local/bin/tngbackup check --config /etc/tngbackup.conf \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log
```

Modalità batch, tutti i job in `/etc/tngbackup/`:

```cron
0 3 * * * /usr/local/bin/tngbackup backup --config /etc/tngbackup/ \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log
0 4 * * * /usr/local/bin/tngbackup prune --config /etc/tngbackup/ \
            --audit-log /var/log/tngbackup-audit.log
```

Backup orari di un dataset che cambia velocemente:

```cron
15 * * * * /usr/local/bin/tngbackup backup --config /etc/tngbackup/database.conf \
             --audit-log /var/log/tngbackup-audit.log
```

Suggerimenti per cron:

- Il `PATH` di cron è minimale. Imposta `PATH` in cima al crontab (come
  sopra) o usa percorsi assoluti ovunque.
- `%` è speciale nel crontab e deve essere sfuggito come `\%` - rilevante se
  costruisci un nome di archivio con `date +%F` in linea.
- Imposta `MAILTO` così i fallimenti vengono notati. Un backup completato
  con warning esce con 0 e quindi *non* genererà mail di fallimento -
  monitora invece l'audit log per i record `WARNING`. Poiché lo script esce
  con codice diverso da zero in caso di fallimento (batch incluso), cron
  segnala i fallimenti in modo affidabile. Con `SHOWTEXT=y` un'esecuzione
  riuscita stampa comunque output e genera mail ogni notte; imposta
  `SHOWTEXT="n"` nella configurazione e affidati a `LOG_FILE` così la mail
  arriva solo in caso di output su stderr.
- Distribuisci i job su host diversi così venti macchine non colpiscono lo
  stesso server di backup tutte alle 03:00.

### systemd timer

Più robusto di cron per laptop e macchine non sempre accese:
`Persistent=true` recupera un'esecuzione mancata, e `RandomizedDelaySec`
distribuisce il carico.

`install.sh` posiziona entrambe le unit in `/etc/systemd/system/` quando
quella directory esiste; altrimenti installale a mano:

```bash
sudo install -m 0644 docs/tngbackup.service /etc/systemd/system/
sudo install -m 0644 docs/tngbackup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tngbackup.timer
```

Controllala e pilotala:

```bash
systemctl list-timers tngbackup.timer
systemctl start tngbackup.service      # run now, out of schedule
journalctl -u tngbackup.service -n 100 --no-pager
systemctl status tngbackup.service
```

Poiché lo script esce con lo stato dell'operazione, un backup fallito
contrassegna la unit come `failed` e può innescare un handler `OnFailure=`.
Un backup completato con warning esce con 0, quindi la unit resta
`succeeded` e nessun handler scatta - che è il comportamento previsto,
poiché è stato prodotto un archivio.

```ini
# In tngbackup.service
OnFailure=notify-admin@%n.service
```

Per più job, usa una unit templata. `/etc/systemd/system/tngbackup@.service`:

```ini
[Unit]
Description=TNGBackup - %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tngbackup backup --config /etc/tngbackup/%i.conf \
    --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log
StandardOutput=journal
StandardError=journal
Environment="DEBUG=n"
```

Poi abilita un timer per ciascuna istanza:
`systemctl enable --now tngbackup@webserver.timer`.

Poiché le unit `Type=oneshot` girano fino al completamento, systemd non
avvierà una seconda esecuzione mentre una è ancora in corso - una guardia
utile contro backup sovrapposti che cron non ti dà.

---

## Risoluzione dei problemi

### Il repository è bloccato

```
Failed to create/acquire the lock /mnt/backup/borg-repo/lock.exclusive
```

Un processo Borg detiene il lock, oppure uno precedente è morto senza
rilasciarlo.

```bash
# 1. Is something actually running?
ps aux | grep -E 'borg|tngbackup'

# 2. If yes, wait for it, or stop it cleanly (SIGTERM, never SIGKILL -
#    the cleanup trap needs to run)
kill -TERM <pid>

# 3. Only if nothing is running, break the stale lock:
borg break-lock /mnt/backup/borg-repo
```

Un `tngbackup mount` dimenticato è una causa comune: `borg mount`
demonizza e detiene il repository. Controlla con `mount | grep borg` e
`borg umount`.

Non rimuovere mai un lock mentre un processo Borg potrebbe ancora stare
scrivendo; questo rischia la corruzione del repository. Per un repository
remoto, controlla anche il **server** per processi `borg serve` in
esecuzione.

Per prevenire sovrapposizioni, avvolgi le invocazioni in `flock`:

```bash
flock -n /var/lock/tngbackup.lock /usr/local/bin/tngbackup backup --config /etc/tngbackup.conf
```

Oppure usa un servizio systemd `Type=oneshot`, che serializza per
progettazione.

### SSH fallisce o scade

Borg viene invocato con stdin chiuso, quindi un prompt SSH ora fallisce
rapidamente invece di bloccarsi. Aspettati un errore immediato piuttosto
che un job bloccato.

Quasi sempre un problema di chiave: una host key sconosciuta, una chiave
protetta da passphrase, o un fallback all'autenticazione con password.

```bash
# Reproduce non-interactively - this must succeed silently
ssh -o BatchMode=yes -o ConnectTimeout=5 -p 22 borg@backup.example.com borg --version
```

Controlla cosa sta effettivamente usando lo script:

```bash
DEBUG=y DRYRUN=y tngbackup list --config /etc/tngbackup.conf
# [DEBUG] Remote repository detected, BORG_RSH configured
```

Soluzioni:

```bash
# Pre-seed the host key
ssh-keyscan -p 22 backup.example.com >> /root/.ssh/known_hosts

# Point SSH_OPT at an explicit key - root's environment differs from yours,
# and there is no ssh-agent under cron or systemd.
# Repeat the defaults you still want; SSH_OPT replaces them wholesale.
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519"
```

Se backup lunghi vengono interrotti da un firewall, aggiungi dei
keepalive:

```bash
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
```

Se sembra che `SSH_OPT` venga ignorato, conferma che `REPO_URI` inizi
davvero con `ssh://` - `BORG_RSH` viene impostato solo per quello schema di
URI, e un URI dall'aspetto locale come `user@host:/path` non lo attiverà.

### borg binary not found in PATH

```
[ERROR] borg binary not found in PATH
```

O Borg non è installato, oppure il `PATH` del job non lo include.

```bash
command -v borg || echo "not installed"

# Debian/Ubuntu
sudo apt install borgbackup
# RHEL/Fedora
sudo dnf install borgbackup
# Alpine
sudo apk add borgbackup
# pipx (with FUSE support for mount)
pipx install 'borgbackup[fuse]'
```

Se Borg si trova in `/usr/local/bin/borg` o in un venv pipx, imposta
esplicitamente `PATH` nel crontab o aggiungi `Environment="PATH=..."` alla
unit systemd.

Per repository remoti, Borg deve essere installato anche sul server, e il
`PATH` non interattivo del server deve trovarlo. Se non lo trova:

```bash
export BORG_REMOTE_PATH=/usr/local/bin/borg
```

### Permission denied

Distingui quattro casi:

1. **Lettura dei file sorgente.** Borg salta i file illeggibili, li
   riporta alla fine, crea comunque l'archivio, ed esce con 1. TNGBackup lo
   registra come `WARNING` ed esce con 0 - il backup è utilizzabile. Leggi
   il log per vedere cosa è stato saltato; se la sorgente richiede root,
   esegui il backup come root.
2. **Scrittura sul repository.** La directory del repository (o il
   percorso di destinazione dell'utente SSH remoto) deve essere scrivibile
   dall'utente che invoca:
   ```bash
   ls -ld /mnt/backup/borg-repo
   sudo chown -R borg:borg /mnt/backup/borg-repo
   ```
3. **Creazione del file di log.** `--log` esegue `touch` + `chmod 600` in
   modo anticipato e abortisce l'esecuzione se la directory padre non è
   scrivibile. Lascia che `install.sh` crei `/var/log/tngbackup.log`,
   oppure scegli un percorso scrivibile.
4. **Creazione di un mountpoint o di una directory di ripristino.**
   `mount` ed `extract` eseguono `mkdir -p` sulla loro destinazione e
   falliscono in modo pulito (`Cannot create mountpoint:` /
   `Cannot create restore path:`) se il padre non è scrivibile.

Attenzione a SELinux/AppArmor sui percorsi del log e del repository -
controlla `ausearch -m avc -ts recent` se i permessi sembrano corretti ma
l'accesso viene comunque rifiutato.

### Passphrase errata

```
passphrase supplied in BORG_PASSPHRASE, by BORG_PASSCOMMAND or via keyfile is incorrect.
```

La passphrase non corrisponde a questo repository. Controlla:

- Spazi bianchi finali o un ritorno a capo estraneo nel valore della
  configurazione.
- Espansione della shell dentro virgolette doppie. Una passphrase
  contenente `$`, `` ` `` o `\` viene alterata da `REPO_PASSPHRASE="p$$w0rd"`.
  Usa virgolette singole: `REPO_PASSPHRASE='p$$w0rd'`.
- Una `BORG_PASSPHRASE` residua esportata nell'ambiente: `env | grep BORG`.
- Il repository sbagliato - `REPO_URI` che punta a un repository diverso
  da quello che pensi.
- Un `--passphrase` sulla riga di comando che avevi dimenticato: ora
  sovrascrive genuinamente il file di configurazione.

Verifica a mano:

```bash
BORG_PASSPHRASE='...' borg list /mnt/backup/borg-repo
```

Non c'è modo di recuperare un repository la cui passphrase è genuinamente
persa.

### La mia opzione CLI sembra essere ignorata

Solo `--repo` e `--passphrase` vengono riapplicati dopo che il file di
configurazione è stato sourced. `--archive`, `--path`, `--mountpoint`,
`--log` e `--audit-log` vengono impostati *prima* del sourcing, quindi un
file di configurazione che assegna incondizionatamente la variabile
corrispondente vince. Rimuovi quella riga dalla configurazione, oppure
proteggila:

```bash
ARCHIVE_NAME="${ARCHIVE_NAME:-}"
LOG_FILE="${LOG_FILE:-/var/log/tngbackup.log}"
```

In modalità batch `--repo` e `--passphrase` sono ignorati interamente per
progettazione.

### L'archivio esiste già

```
Archive archive-20260905-030001 already exists
```

`ARCHIVE_NAME` è fissa piuttosto che univoca. Lasciala vuota così viene
generato un nome con timestamp. Nota che questo non è più un pericolo in
modalità batch: `ARCHIVE_NAME` viene resettata tra le configurazioni.

Se due backup girano nello stesso secondo, anche i nomi generati collidono
- un altro motivo per serializzare le esecuzioni con `flock` o una unit
`oneshot`.

### prune si rifiuta di girare

```
[ERROR] No retention policy configured (set at least one of KEEP_LAST, ...)
```

Ogni variabile `KEEP_*` è vuota o `0`. Questa è una protezione, non un
bug: un prune senza regole eliminerebbe ogni archivio. Imposta almeno una
regola, oppure non eseguire `prune` su quel repository.

### prune ha eliminato più del previsto

I default di `KEEP_*` sono non vuoti (`KEEP_LAST=10`, `KEEP_DAILY=7`,
`KEEP_WEEKLY=4`, `KEEP_MONTHLY=12`), quindi una configurazione che omette
la retention ha comunque una politica. Controlla cosa è stato realmente
applicato - l'audit log registra le opzioni esatte usate da ogni prune:

```bash
awk -F' \\| ' '$2=="prune"{print $1, $4}' /var/log/tngbackup-audit.log
```

In modalità batch, ricorda che `KEEP_*` non viene resettata tra le
configurazioni.

### Lo script si blocca senza output su un server

L'hai invocato senza alcuna operazione, e sta aspettando sul `read` del
menu interattivo. Passa sempre un'operazione in automazione. Borg stesso
non può più bloccarsi su un prompt - stdin è chiuso per ogni invocazione.

### Ricetta generale di debug

```bash
# What would it do?
DEBUG=y DRYRUN=y tngbackup backup --config /etc/tngbackup.conf

# Trace every shell command
bash -x /usr/local/bin/tngbackup backup --config /etc/tngbackup.conf 2>&1 | tee /tmp/trace.log

# Confirm the config parses at all
bash -n /etc/tngbackup.conf && echo "syntax OK"

# See what the config actually sets
( set -a; source /etc/tngbackup.conf; echo "REPO_URI=$REPO_URI"; echo "BACKUP_PATH=$BACKUP_PATH" )

# Confirm the tool itself is healthy
./tests/dispatch-test.sh
```

Oscura URI dei repository e passphrase prima di condividere qualunque
parte di quell'output.

---

## Codici di uscita

| Codice | Significato |
|---|---|
| `0` | Successo, **oppure completato con warning**. Restituito anche da `--help` e scegliendo `0` nel menu. |
| `1` | Fallimento rilevato dallo script stesso: opzione non valida, configurazione non trovata o illeggibile, validazione fallita (`REPO_URI`/`REPO_PASSPHRASE`/`BACKUP_PATH` mancanti, `borg` non nel `PATH`), operazione sconosciuta, un `--archive` mancante per `delete`/`extract`, una politica di retention non configurata per `prune`, oppure un mountpoint/directory di ripristino non scrivibili. In modalità batch, almeno una configurazione è fallita. |
| `2` e superiori | Propagato da Borg stesso (`2` è l'"errore" proprio di Borg), oppure dalla shell sotto `set -euo pipefail` - ad es. `126`/`127` per un comando che non ha potuto essere eseguito, `130` per interruzione con Ctrl-C, `143` per `SIGTERM`. |

Lo script esce con il **codice di uscita proprio dell'operazione**: `main`
cattura il risultato di `dispatch_operation` ed esce con esso, così lo
stato di Borg raggiunge il chiamante invece di essere inghiottito.

La convenzione di Borg è `0` successo, `1` warning, `2` errore, e
`finish_operation` la mappa deliberatamente:

- **`0` → `SUCCESS`, uscita 0.**
- **`1` → `WARNING`, uscita 0.** L'operazione si è completata e ha
  prodotto il suo risultato; qualcosa era semplicemente degno di nota, il
  più delle volte un file che non poteva essere letto o che è sparito
  durante il backup. Un backup così **è** un backup utilizzabile, quindi
  non fa fallire l'esecuzione, non contrassegna una unit systemd come
  `failed`, né genera mail cron. Viene registrato come `WARNING` nell'audit
  log così puoi comunque trovarlo.
- **`2` o superiore → `FAILED`, uscita N.** Un errore reale; il codice di
  uscita passa inalterato.

Nota l'asimmetria: il codice di uscita `1` di `tngbackup` non significa mai
"Borg ha dato un warning" - significa che lo script ha rifiutato la
richiesta prima che Borg girasse. I warning propri di Borg non raggiungono
mai il chiamante come stato diverso da zero.

La **modalità batch** conta i fallimenti e restituisce 1 se una
qualunque configurazione è fallita, quindi un'uscita zero significa che
ogni job si è almeno completato. I warning non contano come fallimenti del
batch, per lo stesso motivo. I singoli risultati vale comunque la pena di
sottoporli ad audit:

```bash
#!/bin/bash
# Page on real failures; report warnings separately without paging.
today=$(date -u +%Y-%m-%d)
log=/var/log/tngbackup-audit.log

if grep "^${today}" "$log" | grep -q '| FAILED |'; then
    grep "^${today}" "$log" | grep '| FAILED |' \
      | mail -s "TNGBackup FAILURES on $(hostname)" ops@example.com
fi

if grep "^${today}" "$log" | grep -q '| WARNING |'; then
    grep "^${today}" "$log" | grep '| WARNING |' \
      | mail -s "TNGBackup warnings on $(hostname)" ops@example.com
fi
```

---

## Test

Due script di test vivono in `tests/`. Entrambi sono Bash autonomi e non
prendono argomenti; entrambi puliscono dopo di sé.

### tests/dispatch-test.sh

Gira ovunque - **non richiede un'installazione di Borg**. Mette per primo
nel `PATH` uno stub `borg` che registra la riga di comando con cui è stato
invocato, poi porta `tngbackup` attraverso 26 controlli che coprono:

- il dispatch di tutte e dieci le operazioni verso il sottocomando Borg
  giusto
- la costruzione degli argomenti di `borg create`: suddivisione in parole
  di `BORG_OPT`, un `--exclude` per ogni elemento di `BACKUP_EXCLUDE`,
  generazione del nome dell'archivio
- la costruzione delle opzioni di retention a partire dalle variabili
  `KEEP_*`
- la precedenza CLI-contro-configurazione
- la modalità dry-run che non esegue nulla
- la mappatura dei codici di uscita: Borg `0` → `SUCCESS`/uscita 0, `1` →
  `WARNING`/uscita 0, `>= 2` → `FAILED`/uscita N
- la propagazione dei fallimenti: un comando Borg fallito fa uscire
  `tngbackup` con codice diverso da zero
- la creazione dell'audit log e il formato dei record
- che nessuna passphrase finisca in nessuno dei due file di log
- la modalità batch che elabora ogni configurazione in una directory
- l'output di `--help` e il rifiuto di un'operazione sconosciuta

```bash
./tests/dispatch-test.sh
```

```
=== Result ===
Passed: 26/26
PASS: all dispatch checks passed
```

Codici di uscita: `0` tutto superato, `1` uno o più controlli falliti.
Sovrascrivi lo script sotto test con
`TNGBACKUP=/usr/local/bin/tngbackup ./tests/dispatch-test.sh`.

### tests/integration-test.sh

Richiede un vero Borg (1.2+) e Bash 4+. Crea un repository usa e getta in
una directory temporanea, esercita davvero ogni operazione contro di esso -
init, backup, list, info, check, prune, compact, extract con verifica del
contenuto, delete - verifica l'audit log, poi rimuove tutto.

```bash
./tests/integration-test.sh

# Also exercise mount (needs FUSE support in Borg)
TNGB_TEST_MOUNT=y ./tests/integration-test.sh
```

Senza `TNGB_TEST_MOUNT=y` il controllo di mount viene saltato e riportato
come `[SKIP]`, poiché FUSE non è disponibile ovunque.

Codici di uscita: `0` tutto superato, `1` uno o più controlli falliti,
**`2` prerequisiti mancanti** (nessun Borg nel `PATH`, oppure una Bash non
supportata). Un job CI può trattare `2` come "saltato" piuttosto che
"rotto".

Esegui entrambi prima di distribuire una modifica, ed esegui il test di
integrazione una volta contro la versione di Borg di produzione prima di
affidare allo strumento dati reali.

---

## Vedi anche

- `install.sh` - installatore e disinstallatore
- `docs/examples/tngbackup.conf` - configurazione di riferimento annotata
- `docs/examples/local-backup.conf` - esempio di repository locale
- `docs/examples/remote-backup.conf` - esempio di repository SSH
- `docs/examples/batch-configs/` - esempi di modalità batch
- `docs/tngbackup.1` - man page
- `docs/tngbackup.service`, `docs/tngbackup.timer` - unit systemd
- `tests/dispatch-test.sh`, `tests/integration-test.sh` - suite di test
- [Documentazione di Borg Backup](https://borgbackup.readthedocs.io/)
- `borg(1)`

---

TNGBackup 2.0.9 - Autore: Massimo "RedFoxy Darrest" Cicciò - Licenza: CC BY-NC 4.0 (Non-Commercial) + Commercial
