# Migrazione da TNGBackup v0.8.8 a v2.x.x

Questa guida aiuta a convertire i file di configurazione dal formato v0.8.8 (sistema locale/remoto separato) al nuovo formato v2.x.x (repository unificato).

---

## Panoramica dei Cambiamenti

| Aspetto | v0.8.8 | v2.x.x | Note |
|---------|--------|--------|-------|
| **Repository** | LOCAL + REMOTE separati | REPO_URI unificato | Un solo repository per config |
| **Operazioni** | Integrate in config (CHECK, PRUNE, COMPACT) | Separate e esplicite | Comandi CLI per ogni operazione |
| **Retention** | LOCAL_KEEP_* e REMOTE_KEEP_* | KEEP_* unificato | Unico set di regole |
| **SSH** | SSH_USER, SSH_HOST, SSH_PORT, SSH_CERT | URI ssh:// + SSH_OPT | Configurazione centralizzata |
| **Esclusioni** | BACKUP_EXCL (semicolon) | BACKUP_EXCLUDE (semicolon) | Stesso formato, nome diverso |
| **Percorsi backup** | BACKUP_PATH (semicolon) | BACKUP_PATH (space) | **Cambio separatore** |
| **Hook** | PRERUN, POSTRUN | Supportati nativamente (v2.1+) | Niente script wrapper necessario |
| **Operazioni intorno al backup** | CHECK, PRUNE, COMPACT (flag 0/1/2) | CHECK_BACKUP, PRUNE_BACKUP, COMPACT_BACKUP (v2.1+) | Naming più chiaro |
| **Auto-creazione repo** | LCREATE_REPO, RCREATE_REPO | CREATE_REPO, CREATE_REPO_DIR (v2.1+) | Nomi unificati, singolo repo |
| **Password SSH** | SSH_PASS (rimosso per sicurezza) | SSH_PASSWORD (v2.1+, con sshpass) | Supporto ripristinato dove necessario |
| **Auto-init** | LCREATE_REPO, RCREATE_REPO | `tngbackup init` o CREATE_REPO=y | Operazione esplicita o automatica |
| **Encryption** | BORG_ENCRIPTION (typo) | BORG_ENCRYPTION (corretto) | Naming corretto |

---

## Conversione Passo per Passo

### Passo 1: Decidere Repository Locale o Remoto

In v0.8.8 avevi:

```bash
LOCAL=y                    # o n
LOCAL_REPO="/path/to/repo"
REMOTE=y                   # o n
REMOTE_REPO="ssh://..."
```

In v2.x.x scegli **uno solo** e usa `REPO_URI`:

```bash
# Per repository LOCALE:
REPO_URI="/path/to/repo"

# Per repository REMOTO:
REPO_URI="ssh://user@host:port/path/to/repo"
```

---

### Passo 2: Variabili Core e Operazioni

**v0.8.8:**
```bash
REPOSITORY="my-backup"
REPO_PASSPHRASE="secret"

BACKUP=y
CHECK=2          # Check dopo il backup
PRUNE=2          # Prune dopo il backup
COMPACT=0        # Nessun compact
```

**v2.x.x (operazioni integrate nel backup, opzionali):**
```bash
REPO_URI="/mnt/backup/my-backup"      # o ssh://...
REPO_PASSPHRASE="secret"

# Operazioni intorno al backup (optional, solo con operazione 'backup'):
CHECK_BACKUP=1          # 0=no, 1=before, 2=after
PRUNE_BACKUP=2          # 0=no, 1=before, 2=after
COMPACT_BACKUP=0        # 0=no, 1=before, 2=after

# Oppure esegui operazioni separatamente da riga di comando:
# tngbackup backup --config ...
# tngbackup check --config ...
# tngbackup prune --config ...
# tngbackup compact --config ...
```

---

### Passo 3: Percorsi di Backup

**v0.8.8 (separatore: semicolon `;`):**
```bash
BACKUP_PATH="/home;/etc;/var/www"
BACKUP_EXCL="*.log;*/node_modules;*/cache"
```

**v2.x.x (cambio separatore):**
```bash
# BACKUP_PATH: separatore SPACE, non semicolon
BACKUP_PATH="/home /etc /var/www"

# BACKUP_EXCLUDE: stesso formato semicolon
BACKUP_EXCLUDE="*.log;*/node_modules;*/cache"
```

**⚠️ Cambio importante:** `BACKUP_PATH` da semicolon a space.

---

### Passo 4: Politica di Conservazione (Retention)

**v0.8.8 (duplicato per locale/remoto):**
```bash
LOCAL_KEEP_LAST=10
LOCAL_KEEP_DAILY=7
LOCAL_KEEP_WEEKLY=4
LOCAL_KEEP_MONTHLY=12
LOCAL_KEEP_YEARLY=0

REMOTE_KEEP_LAST=10
REMOTE_KEEP_DAILY=7
REMOTE_KEEP_WEEKLY=4
REMOTE_KEEP_MONTHLY=12
REMOTE_KEEP_YEARLY=0
```

**v2.x.x (unificato, un solo set):**
```bash
KEEP_LAST=10
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=0
```

Se in v0.8.8 avevi politiche diverse tra locale e remoto, **dovrai usare file di config separati in v2.x.x** e modalità batch.

---

### Passo 5: Configurazione SSH

**v0.8.8:**
```bash
SSH_USER="borg"
SSH_HOST="backup.example.com"
SSH_PORT=22
SSH_CERT="/root/.ssh/id_rsa"
SSH_PASS="optional-if-key-has-passphrase"
```

**v2.x.x:**
```bash
# Tutto nell'URI:
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/repo"

# Opzioni SSH (se necessario override):
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/id_rsa"
SSH_PORT=22  # Ridondante se nell'URI, ma rispettato se diverso
```

**Note:** 
- **Metodo preferito:** Autenticazione basata su chiave SSH con certificato (più sicuro)
- **Metodo alternativo (v2.x.x):** Se certificati non disponibili, usa SSH_PASSWORD con sshpass (meno sicuro; vedi Passo 9b)

---

### Passo 6: Opzioni Borg

**v0.8.8:**
```bash
LOCAL_OPT="--compression zstd,10 --stats"
REMOTE_OPT="--compression zstd,10"
BORG_OPT="--exclude-caches"
```

**v2.x.x:**
```bash
# Un solo set di opzioni, applicate a borg create:
BORG_OPT="--compression zstd,10 --stats --exclude-caches"
```

---

### Passo 7: Pre/Post Esecuzione

**v0.8.8:**
```bash
PRERUN="echo 'Inizio backup' && /path/to/script.sh"
POSTRUN="/path/to/cleanup.sh"
```

**v2.x.x (Supporto nativo):**
```bash
# PRERUN e POSTRUN sono ora supportati nativamente
PRERUN="/path/to/prerun-script.sh"        # Eseguito prima del backup
POSTRUN="/path/to/postrun-script.sh"      # Eseguito dopo il backup

# Se PRERUN fallisce (exit != 0), il backup è abortito
# Se POSTRUN fallisce, lo status del backup rimane invariato
```

Puoi ancora usare uno script wrapper se preferisci:

```bash
#!/bin/bash
/path/to/prerun-script.sh
/usr/local/bin/tngbackup backup --config /etc/tngbackup.conf
/path/to/postrun-script.sh
```

O systemd `ExecStartPre=` e `ExecStartPost=` nei file `.service`.

---

### Passo 8: Logging

**v0.8.8:**
```bash
SHOWTEXT=y
DEBUG=n
DRYRUN=n
# Non c'era separazione tra log operativo e audit log
```

**v2.x.x:**
```bash
SHOWTEXT=y
DEBUG=n
DRYRUN=n

# Aggiungi via CLI (consigliato):
# tngbackup backup --config ... \
#     --log /var/log/tngbackup.log \
#     --audit-log /var/log/tngbackup-audit.log

# O nel file di config:
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
```

---

### Passo 8b: Operazioni intorno al Backup (v2.1+)

**v0.8.8 (integrato nella config):**
```bash
CHECK=0                 # 0=no, 1=before, 2=after
PRUNE=0                 # 0=no, 1=before, 2=after
COMPACT=0               # 0=no, 1=before, 2=after
```

**v2.x.x (naming più chiaro):**
```bash
# Durante il backup:
CHECK_BACKUP=1          # Verifica integrità prima
PRUNE_BACKUP=2          # Pulisci archivi dopo
COMPACT_BACKUP=2        # Riclama spazio dopo

# Comando unificato:
tngbackup backup --config /etc/tngbackup.conf
# → Verifica → Backup → Prune → Compact (pipeline automatica)
```

---

### Passo 9: Auto-creazione Repository (v2.1+)

**v0.8.8 (separato locale/remoto):**
```bash
LCREATE_REPO=y
LCREATE_REPO_DIR=y
RCREATE_REPO=y
RCREATE_REPO_DIR=y
```

**v2.x.x (init esplicita):**
```bash
# Usa l'operazione init esplicita:
tngbackup init --config /etc/tngbackup.conf

# La directory genitore di REPO_URI deve esistere.
```

**v2.x.x (auto-creation supportato):**
```bash
# Auto-creazione automatica (opzione):
CREATE_REPO="y"         # Crea repository se mancante
CREATE_REPO_DIR="y"     # Crea directory genitore se mancante

# Primo backup inizializza automaticamente il repository:
tngbackup backup --config /etc/tngbackup.conf

# Oppure disabilita auto-creation se preferisci init manuale:
CREATE_REPO="n"
# Poi: tngbackup init --config /etc/tngbackup.conf
```

---

### Passo 9b: Password SSH Interattiva (v2.1+)

**v0.8.8:**
```bash
SSH_PASS="your-password"    # Password SSH (non sicura)
```

**v2.x.x (supporto ripristinato):**
```bash
# Usa sshpass per password interattive (quando certificati non disponibili):
SSH_PASSWORD="your-ssh-password"    # Richiede 'sshpass' installato

# Esempio:
REPO_URI="ssh://user@backup.example.com/mnt/borg"
SSH_PASSWORD="server-password"
```

**⚠️ Nota di sicurezza:**
- Meno sicuro dei certificati SSH (sconsigliato per ambienti critici)
- Preferire sempre autenticazione basata su chiave quando possibile
- Se necessario, usare SSH agent per chiavi protette da passphrase

---

## Esempio Completo: Conversione

### Configurazione v0.8.8

```bash
REPOSITORY="webserver"
REPO_PASSPHRASE="correct-horse-battery-staple"

BACKUP=y
CHECK=2
PRUNE=2
COMPACT=0

BACKUP_PATH="/var/www;/etc/nginx"
BACKUP_EXCL="*.log;*/cache;*/tmp"

LOCAL=n
REMOTE=y
REMOTE_REPO="ssh://borg@nas.example.com:2222/mnt/borg/webserver"

REMOTE_OPT="--compression zstd,10 --stats"
REMOTE_KEEP_LAST=5
REMOTE_KEEP_DAILY=7
REMOTE_KEEP_WEEKLY=4
REMOTE_KEEP_MONTHLY=12
REMOTE_KEEP_YEARLY=0

SSH_USER="borg"
SSH_HOST="nas.example.com"
SSH_PORT=2222
SSH_CERT="/root/.ssh/borg_ed25519"

BORG_ENCRIPTION="repokey-blake2"

SHOWTEXT=y
DEBUG=n
DRYRUN=n
```

### Configurazione v2.x.x (Equivalente)

```bash
# Repository
REPO_URI="ssh://borg@nas.example.com:2222/mnt/borg/webserver"
REPO_PASSPHRASE="correct-horse-battery-staple"

# Backup
BACKUP_PATH="/var/www /etc/nginx"
BACKUP_EXCLUDE="*.log;*/cache;*/tmp"

# Backup Hooks (optional)
PRERUN="mysqldump -u root -p$PASS db > /tmp/dump.sql"
POSTRUN="rm /tmp/dump.sql"

# Companion Operations (during backup)
CHECK_BACKUP=1          # Verifica prima del backup
PRUNE_BACKUP=2          # Pulisci dopo il backup
COMPACT_BACKUP=2        # Riclama spazio dopo il backup

# Repository Auto-Creation
CREATE_REPO="y"         # Inizializza se mancante
CREATE_REPO_DIR="y"     # Crea directory genitore se mancante

# Opzioni Borg
BORG_OPT="--compression zstd,10 --stats"
BORG_ENCRYPTION="repokey-blake2"

# Opzioni SSH
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519"
SSH_PORT=2222
# SSH_PASSWORD="server-password"  # Alternativa se certificato non disponibile

# Politica di conservazione
KEEP_LAST=5
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=0

# Logging
SHOWTEXT=y
DEBUG=n
DRYRUN=n
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
```

### Comandi di Esecuzione

**v0.8.8 (config-driven):**
```bash
bash tngbackup config.conf
```

**v2.x.x (operation-driven):**
```bash
# Inizializzare
tngbackup init --config /etc/tngbackup.conf

# Backup
tngbackup backup --config /etc/tngbackup.conf \
    --log /var/log/tngbackup.log \
    --audit-log /var/log/tngbackup-audit.log

# Check (se necessario)
tngbackup check --config /etc/tngbackup.conf

# Prune
tngbackup prune --config /etc/tngbackup.conf

# Compact
tngbackup compact --config /etc/tngbackup.conf
```

Oppure con script wrapper:

```bash
#!/bin/bash
CONFIG="/etc/tngbackup.conf"
LOG="/var/log/tngbackup.log"
AUDIT="/var/log/tngbackup-audit.log"

tngbackup backup --config "$CONFIG" --log "$LOG" --audit-log "$AUDIT"
tngbackup check --config "$CONFIG" --audit-log "$AUDIT"
tngbackup prune --config "$CONFIG" --audit-log "$AUDIT"
tngbackup compact --config "$CONFIG" --audit-log "$AUDIT"
```

---

## Modalità Batch: Per Backup Multipli

Se in v0.8.8 avevi **due repository separati** (uno locale, uno remoto):

**v0.8.8:**
```bash
# Un singolo file config con LOCAL=y e REMOTE=y
```

**v2.x.x con Modalità Batch:**

Crea due file separati in `/etc/tngbackup/`:

```
/etc/tngbackup/
├── local-backup.conf       # REPO_URI="/mnt/borg/..."
└── remote-backup.conf      # REPO_URI="ssh://..."
```

Esegui entrambi:

```bash
tngbackup backup --config /etc/tngbackup/ --log /var/log/tngbackup.log
tngbackup prune --config /etc/tngbackup/ --audit-log /var/log/tngbackup-audit.log
tngbackup compact --config /etc/tngbackup/
```

---

## Checklist di Migrazione

**Configurazione Base:**
- [ ] Scegli se usare repository locale o remoto (v2.x.x supporta uno per config)
- [ ] Converti `REPOSITORY` + `LOCAL/REMOTE_REPO` → `REPO_URI`
- [ ] Converti `BACKUP_PATH` da `;` separato a space separato
- [ ] Rinomina `BACKUP_EXCL` → `BACKUP_EXCLUDE` (facoltativo, entrambi funzionano)
- [ ] Unifica `LOCAL_KEEP_*` / `REMOTE_KEEP_*` → `KEEP_*`
- [ ] Converti SSH: `SSH_USER`, `SSH_HOST`, `SSH_PORT`, `SSH_CERT` → `REPO_URI` + `SSH_OPT`
- [ ] Rinomina `BORG_ENCRIPTION` → `BORG_ENCRYPTION`
- [ ] Unisci `LOCAL_OPT` e `REMOTE_OPT` → `BORG_OPT`

**Nuove Feature (v2.x.x):**
- [ ] Opzionale: Converti `CHECK`, `PRUNE`, `COMPACT` (0/1/2) → `CHECK_BACKUP`, `PRUNE_BACKUP`, `COMPACT_BACKUP`
- [ ] Opzionale: Aggiungi `PRERUN` e `POSTRUN` (ora supportati nativamente, no script wrapper)
- [ ] Opzionale: Configura `CREATE_REPO` e `CREATE_REPO_DIR` per auto-creazione repository
- [ ] Opzionale: Configura `SSH_PASSWORD` se non puoi usare certificati SSH (con sshpass)

**Finalizzazione:**
- [ ] Se abiliti `CREATE_REPO=n`: Esegui `tngbackup init` manualmente una volta
- [ ] Se abiliti `CREATE_REPO=y`: Il primo backup creerà il repository automaticamente
- [ ] Testa con `DRYRUN=y DEBUG=y tngbackup backup --config ...`
- [ ] Se hai backup multipli (locale + remoto): usa modalità batch con directory di config separate

---

## Script di Conversione (Bash)

Se hai molti file v0.8.8 da convertire, questo script aiuta:

```bash
#!/bin/bash

OLD_CONFIG="$1"
NEW_CONFIG="$2"

# Estrai REPOSITORY
REPO=$(grep "^REPOSITORY=" "$OLD_CONFIG" | cut -d'"' -f2)

# Scegli se LOCAL o REMOTE
if grep -q "^REMOTE=y" "$OLD_CONFIG"; then
  SSH_HOST=$(grep "^SSH_HOST=" "$OLD_CONFIG" | cut -d'"' -f2)
  SSH_USER=$(grep "^SSH_USER=" "$OLD_CONFIG" | cut -d'"' -f2)
  SSH_PORT=$(grep "^SSH_PORT=" "$OLD_CONFIG" | cut -d'=' -f2)
  REMOTE_REPO=$(grep "^REMOTE_REPO=" "$OLD_CONFIG" | cut -d'"' -f2 | sed 's/${REPOSITORY}/'"$REPO"'/g')
  REPO_URI="ssh://$SSH_USER@$SSH_HOST:$SSH_PORT${REMOTE_REPO#./}"
else
  LOCAL_REPO=$(grep "^LOCAL_REPO=" "$OLD_CONFIG" | cut -d'"' -f2 | sed 's/${REPOSITORY}/'"$REPO"'/g')
  REPO_URI="$LOCAL_REPO"
fi

# Converti BACKUP_PATH: ; → space
BACKUP_PATH=$(grep "^BACKUP_PATH=" "$OLD_CONFIG" | cut -d'"' -f2 | tr ';' ' ')

# Converti BACKUP_EXCL → BACKUP_EXCLUDE
BACKUP_EXCLUDE=$(grep "^BACKUP_EXCL=" "$OLD_CONFIG" | cut -d'"' -f2)

# Genera nuovo config
cat > "$NEW_CONFIG" <<EOF
# Migrato da $OLD_CONFIG

REPO_URI="$REPO_URI"
REPO_PASSPHRASE="$(grep "^REPO_PASSPHRASE=" "$OLD_CONFIG" | cut -d'"' -f2)"

BACKUP_PATH="$BACKUP_PATH"
BACKUP_EXCLUDE="$BACKUP_EXCLUDE"

BORG_ENCRYPTION="repokey-blake2"

KEEP_LAST=$(grep "^.*_KEEP_LAST=" "$OLD_CONFIG" | head -1 | cut -d'=' -f2)
KEEP_DAILY=$(grep "^.*_KEEP_DAILY=" "$OLD_CONFIG" | head -1 | cut -d'=' -f2)
KEEP_WEEKLY=$(grep "^.*_KEEP_WEEKLY=" "$OLD_CONFIG" | head -1 | cut -d'=' -f2)
KEEP_MONTHLY=$(grep "^.*_KEEP_MONTHLY=" "$OLD_CONFIG" | head -1 | cut -d'=' -f2)

DEBUG=$(grep "^DEBUG=" "$OLD_CONFIG" | cut -d'=' -f2)
DRYRUN=$(grep "^DRYRUN=" "$OLD_CONFIG" | cut -d'=' -f2)

EOF

echo "✓ Conversione completata: $NEW_CONFIG"
```

Uso:
```bash
bash convert.sh old-config.conf new-config.conf
```

---

## Supporto e Domande

Per problemi durante la migrazione, consulta:

- `docs/USAGE.md` — Documentazione completa v2.x.x
- `docs/examples/` — Esempi di configurazione
- Log di audit per tracciare errori: `--audit-log /var/log/tngbackup-audit.log`

---

**Versione documento:** v2.x.x  
**Ultimo aggiornamento:** Settembre 2026
