# TNGBackup v2.0.0 — The Next Generation Borg Backup

**Multi-language documentation:** [Italiano](#-italiano) | [English](#-english)

---

## 🇮🇹 Italiano

### TNGBackup — Cos'è?

TNGBackup è uno strumento unificato per la gestione di backup via **Borg Backup**. Semplifica operazioni complesse come backup locali e remoti, verifiche di integrità, gestione della conservazione, montaggio archivi e ripristino selettivo di file — il tutto da un'unica interfaccia.

**Versione:** 2.0.0  
**Licenza:** MIT  
**Requisiti:** Bash 4.0+, Borg Backup 1.2+

### Caratteristiche Principali

- **10 Operazioni Borg:** init, backup, list, mount, check, compact, prune, info, delete, extract
- **Menu Interattivo:** Scegli l'operazione senza ricordare i comandi
- **Modalità Batch:** Elabora molteplici config da una cartella sequenzialmente
- **Configurazione Flessibile:** File di config, variabili di ambiente, o parametri CLI
- **Precedenza Config:** CLI > File di Config > Variabili d'Ambiente > Default
- **Sicurezza:** Credenziali solo in memoria, no tracce su disco per esecuzioni remote
- **Audit Log:** Tracciamento completo di ogni operazione (timestamp, stato, durata)
- **Logging Controllato:** Output su file con permessi sicuri (600)

### Avvio Rapido

#### 1. Menu Interattivo
```bash
bash tngbackup
# → Seleziona operazione dal menu
```

#### 2. Backup Singolo
```bash
bash tngbackup backup --config /etc/tngbackup.conf
```

#### 3. Batch Backups (molteplici config)
```bash
bash tngbackup --config /etc/tngbackup/
# → Elabora automaticamente tutti i file *.conf nella cartella
```

### Operazioni Disponibili

| Operazione | Descrizione |
|-----------|-------------|
| `init` | Inizializzare un nuovo repository Borg |
| `backup` | Creare un archivio backup dai path configurati |
| `list` | Elencare archivi nel repository o file in un archivio |
| `check` | Verificare l'integrità del repository |
| `mount` | Montare archivi come cartelle (accesso lettura) |
| `extract` | Ripristinare file specifici da un archivio |
| `prune` | Eliminare archivi obsoleti secondo retention policy |
| `compact` | Recuperare spazio nel repository |
| `info` | Mostrare statistiche repository/archivi |
| `delete` | Eliminare archivi specifici |

### Configurazione

Crea un file `tngbackup.conf` (esempio in `docs/examples/`):

```bash
# Repository
REPO_URI="/mnt/backup-disk/my-repo"     # o ssh://user@host:/path/repo
REPO_PASSPHRASE="your-secret-passphrase"

# Backup
BACKUP_PATH="/home /etc /var/www"       # Spazi separati per multi-path
BACKUP_EXCLUDE="*.tmp;*.cache;node_modules"   # Semicolon-separated patterns

# Encryption
BORG_ENCRYPTION="repokey-blake2"        # Default: repokey-blake2

# Retention (quanti archivi mantenere)
KEEP_LAST=10
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12

# Logging
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
DEBUG=n                                 # Imposta su 'y' per output dettagliato
```

### Precedenza Configurazione

La configurazione è caricata con questa priorità (dal più alto al più basso):

1. **Parametri CLI** — `--repo` e `--passphrase` sono riapplicati dopo il
   caricamento del file di config, quindi vincono sempre (esecuzione a config
   singolo; in modalità batch ogni file definisce il proprio repository)
2. **File di Configurazione** (es. `--config tngbackup.conf`)
3. **Variabili d'Ambiente** (es. `REPO_URI=... tngbackup backup`) — usate solo
   se la variabile non è impostata dal file di config
4. **Valori Default** (definiti in testa allo script)

Vedi `docs/USAGE.md` per la precedenza dettagliata opzione per opzione.

### Sicurezza

- **Credenziali Sicure:** Passphrase Borg e password SSH rimangono in memoria, mai su disco
- **Esecuzione Remota:** Su SSH, nessuna traccia di segreti nel filesystem remoto
- **Permessi Log:** I file log sono creati con permessi 600 (solo proprietario)
- **SSH Batch Mode:** Evita prompt interattivi che potrebbero bloccare lo script
- **Cleanup Automatico:** Trap handler (EXIT, INT, TERM) pulisce credenziali e monta

### Troubleshooting

**Debug:** Abilita output dettagliato:
```bash
DEBUG=y bash tngbackup backup --config tngbackup.conf
```

**Dry-Run:** Vedi cosa farebbe senza eseguire:
```bash
DEBUG=y DRYRUN=y bash tngbackup backup --config tngbackup.conf
```

**Repository Bloccato:** Se un'altra istanza tngbackup sta usando il repo, aspetta o fermala:
```bash
ps aux | grep tngbackup
```

---

## 🇬🇧 English

### TNGBackup — What is it?

TNGBackup is a unified management tool for **Borg Backup** operations. It simplifies complex tasks like local and remote backups, integrity verification, retention management, archive mounting, and selective file recovery — all from a single interface.

**Version:** 2.0.0  
**License:** MIT  
**Requirements:** Bash 4.0+, Borg Backup 1.2+

### Key Features

- **10 Borg Operations:** init, backup, list, mount, check, compact, prune, info, delete, extract
- **Interactive Menu:** Choose operations without memorizing commands
- **Batch Mode:** Process multiple configs from a directory sequentially
- **Flexible Configuration:** Config file, environment variables, or CLI arguments
- **Config Precedence:** CLI > Config File > Environment Variables > Defaults
- **Security:** Credentials in memory only, no disk traces for remote execution
- **Audit Logging:** Full tracking of every operation (timestamp, status, duration)
- **Controlled Logging:** Output to file with secure permissions (600)

### Quick Start

#### 1. Interactive Menu
```bash
bash tngbackup
# → Select operation from menu
```

#### 2. Single Backup
```bash
bash tngbackup backup --config /etc/tngbackup.conf
```

#### 3. Batch Backups (multiple configs)
```bash
bash tngbackup --config /etc/tngbackup/
# → Automatically process all *.conf files in directory
```

### Available Operations

| Operation | Description |
|-----------|------------|
| `init` | Initialize a new Borg repository |
| `backup` | Create a backup archive from configured paths |
| `list` | List archives in repository or files in an archive |
| `check` | Verify repository integrity |
| `mount` | Mount archives as folders (read-only access) |
| `extract` | Restore specific files from an archive |
| `prune` | Delete obsolete archives per retention policy |
| `compact` | Reclaim space in repository |
| `info` | Show repository/archive statistics |
| `delete` | Delete specific archives |

### Configuration

Create a `tngbackup.conf` file (example in `docs/examples/`):

```bash
# Repository
REPO_URI="/mnt/backup-disk/my-repo"     # or ssh://user@host:/path/repo
REPO_PASSPHRASE="your-secret-passphrase"

# Backup
BACKUP_PATH="/home /etc /var/www"       # Space-separated for multi-path
BACKUP_EXCLUDE="*.tmp;*.cache;node_modules"   # Semicolon-separated patterns

# Encryption
BORG_ENCRYPTION="repokey-blake2"        # Default: repokey-blake2

# Retention (how many archives to keep)
KEEP_LAST=10
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12

# Logging
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
DEBUG=n                                 # Set to 'y' for detailed output
```

### Configuration Precedence

Configuration is loaded with this priority (highest to lowest):

1. **CLI Arguments** — `--repo` and `--passphrase` are re-applied after the
   config file is sourced, so they always win (single-config runs; in batch
   mode every config file defines its own repository)
2. **Configuration File** (e.g. `--config tngbackup.conf`)
3. **Environment Variables** (e.g. `REPO_URI=... tngbackup backup`) — used only
   when the config file does not set the variable
4. **Default Values** (defined at the top of the script)

See `docs/USAGE.md` for the detailed per-option precedence.

### Security

- **Secure Credentials:** Borg passphrase and SSH passwords stay in memory only, never on disk
- **Remote Execution:** On SSH, no trace of secrets in remote filesystem
- **Log Permissions:** Log files created with 600 permissions (owner-only)
- **SSH Batch Mode:** Avoids interactive prompts that could block execution
- **Automatic Cleanup:** Trap handler (EXIT, INT, TERM) cleans credentials and unmounts

### Troubleshooting

**Debug:** Enable detailed output:
```bash
DEBUG=y bash tngbackup backup --config tngbackup.conf
```

**Dry-Run:** See what would happen without executing:
```bash
DEBUG=y DRYRUN=y bash tngbackup backup --config tngbackup.conf
```

**Repository Locked:** If another tngbackup instance is using the repo, wait or stop it:
```bash
ps aux | grep tngbackup
```

---

## 📚 Documentation

- **Configuration Examples:** `docs/examples/` (local, remote, batch configs)
- **Detailed Usage Guide:** `docs/USAGE.md`
- **Man Page:** `docs/tngbackup.1` (installed by `install.sh`)
- **Systemd Units:** `docs/tngbackup.service`, `docs/tngbackup.timer`
- **Tests:** `tests/dispatch-test.sh` (no Borg needed), `tests/integration-test.sh`

## 📝 License

MIT — See LICENSE file for details.

## 🤝 Contributing

Suggestions and improvements are welcome. Fork the repository and submit pull requests.

---

**Last Updated:** September 2026  
**Maintained by:** RedFoxy Darrest
