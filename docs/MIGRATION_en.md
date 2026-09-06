# Migration from TNGBackup v0.8.8 to v2.x.x

This guide helps you convert configuration files from the v0.8.8 format (separate local/remote system) to the new v2.x.x format (unified repository).

---

## Overview of Changes

| Aspect | v0.8.8 | v2.x.x | Notes |
|--------|--------|--------|-------|
| **Repository** | LOCAL + REMOTE separate | REPO_URI unified | One repository per config |
| **Operations** | Integrated in config (CHECK, PRUNE, COMPACT) | Separate and explicit | CLI commands per operation |
| **Retention** | LOCAL_KEEP_* and REMOTE_KEEP_* | KEEP_* unified | Single set of rules |
| **SSH** | SSH_USER, SSH_HOST, SSH_PORT, SSH_CERT | ssh:// URI + SSH_OPT | Centralized configuration |
| **Exclusions** | BACKUP_EXCL (semicolon) | BACKUP_EXCLUDE (semicolon) | Same format, different name |
| **Backup paths** | BACKUP_PATH (semicolon) | BACKUP_PATH (space) | **Separator changed** |
| **Hooks** | PRERUN, POSTRUN | Natively supported (v2.1+) | No wrapper script needed |
| **Operations around backup** | CHECK, PRUNE, COMPACT (0/1/2 flags) | CHECK_BACKUP, PRUNE_BACKUP, COMPACT_BACKUP (v2.1+) | Clearer naming |
| **Auto-create repo** | LCREATE_REPO, RCREATE_REPO | CREATE_REPO, CREATE_REPO_DIR (v2.1+) | Unified names, single repo |
| **SSH password** | SSH_PASS (removed for security) | SSH_PASSWORD (v2.1+, with sshpass) | Support restored when needed |
| **Auto-init** | LCREATE_REPO, RCREATE_REPO | `tngbackup init` or CREATE_REPO=y | Explicit or automatic |
| **Encryption** | BORG_ENCRIPTION (typo) | BORG_ENCRYPTION (corrected) | Proper naming |

---

## Step-by-Step Conversion

### Step 1: Choose Local or Remote Repository

In v0.8.8 you had:

```bash
LOCAL=y                    # or n
LOCAL_REPO="/path/to/repo"
REMOTE=y                   # or n
REMOTE_REPO="ssh://..."
```

In v2.x.x choose **one only** and use `REPO_URI`:

```bash
# For local repository:
REPO_URI="/path/to/repo"

# For remote repository:
REPO_URI="ssh://user@host:port/path/to/repo"
```

---

### Step 2: Core Variables and Operations

**v0.8.8:**
```bash
REPOSITORY="my-backup"
REPO_PASSPHRASE="secret"

BACKUP=y
CHECK=2          # Check after backup
PRUNE=2          # Prune after backup
COMPACT=0        # No compact
```

**v2.x.x (operations integrated in backup, optional):**
```bash
REPO_URI="/mnt/backup/my-backup"      # or ssh://...
REPO_PASSPHRASE="secret"

# Operations around backup (optional, only with 'backup' operation):
CHECK_BACKUP=1          # 0=no, 1=before, 2=after
PRUNE_BACKUP=2          # 0=no, 1=before, 2=after
COMPACT_BACKUP=0        # 0=no, 1=before, 2=after

# Or run operations separately from CLI:
# tngbackup backup --config ...
# tngbackup check --config ...
# tngbackup prune --config ...
# tngbackup compact --config ...
```

---

### Step 3: Backup Paths

**v0.8.8 (separator: semicolon `;`):**
```bash
BACKUP_PATH="/home;/etc;/var/www"
BACKUP_EXCL="*.log;*/node_modules;*/cache"
```

**v2.x.x (separator changed):**
```bash
# BACKUP_PATH: space separator, not semicolon
BACKUP_PATH="/home /etc /var/www"

# BACKUP_EXCLUDE: same semicolon format
BACKUP_EXCLUDE="*.log;*/node_modules;*/cache"
```

**⚠️ Important change:** `BACKUP_PATH` separator changed from semicolon to space.

---

### Step 4: Retention Policy

**v0.8.8 (duplicated for local/remote):**
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

**v2.x.x (unified, single set):**
```bash
KEEP_LAST=10
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=12
KEEP_YEARLY=0
```

If you had different policies for local and remote in v0.8.8, **you must use separate config files in v2.x.x** and batch mode.

---

### Step 5: SSH Configuration

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
# Everything in the URI:
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/repo"

# SSH options (if needed to override):
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/id_rsa"
SSH_PORT=22  # Redundant if in URI, but respected if different
```

**Notes:**
- **Preferred method:** SSH key-based authentication with certificate (more secure)
- **Alternative method (v2.x.x):** If certificates unavailable, use SSH_PASSWORD with sshpass (less secure; see Step 9b)

---

### Step 6: Borg Options

**v0.8.8:**
```bash
LOCAL_OPT="--compression zstd,10 --stats"
REMOTE_OPT="--compression zstd,10"
BORG_OPT="--exclude-caches"
```

**v2.x.x:**
```bash
# Single set of options, applied to borg create:
BORG_OPT="--compression zstd,10 --stats --exclude-caches"
```

---

### Step 7: Pre/Post Execution

**v0.8.8:**
```bash
PRERUN="echo 'Starting backup' && /path/to/script.sh"
POSTRUN="/path/to/cleanup.sh"
```

**v2.x.x (Native support):**
```bash
# PRERUN and POSTRUN are now natively supported
PRERUN="/path/to/prerun-script.sh"        # Executed before backup
POSTRUN="/path/to/postrun-script.sh"      # Executed after backup

# If PRERUN fails (exit != 0), backup is aborted
# If POSTRUN fails, backup operation status is preserved
```

You can still use an external wrapper script if preferred:

```bash
#!/bin/bash
/path/to/prerun-script.sh
/usr/local/bin/tngbackup backup --config /etc/tngbackup.conf
/path/to/postrun-script.sh
```

Or systemd `ExecStartPre=` and `ExecStartPost=` in `.service` files.

---

### Step 8: Logging

**v0.8.8:**
```bash
SHOWTEXT=y
DEBUG=n
DRYRUN=n
# No separation between operational log and audit log
```

**v2.x.x:**
```bash
SHOWTEXT=y
DEBUG=n
DRYRUN=n

# Add via CLI (recommended):
# tngbackup backup --config ... \
#     --log /var/log/tngbackup.log \
#     --audit-log /var/log/tngbackup-audit.log

# Or in config file:
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
```

---

### Step 8b: Operations Around Backup (v2.1+)

**v0.8.8 (integrated in config):**
```bash
CHECK=0                 # 0=no, 1=before, 2=after
PRUNE=0                 # 0=no, 1=before, 2=after
COMPACT=0               # 0=no, 1=before, 2=after
```

**v2.x.x (clearer naming):**
```bash
# During backup:
CHECK_BACKUP=1          # Verify integrity before
PRUNE_BACKUP=2          # Clean old archives after
COMPACT_BACKUP=2        # Reclaim space after

# Single unified command:
tngbackup backup --config /etc/tngbackup.conf
# → Check → Backup → Prune → Compact (automatic pipeline)
```

---

### Step 9: Auto-Repository Creation (v2.1+)

**v0.8.8 (separate local/remote):**
```bash
LCREATE_REPO=y
LCREATE_REPO_DIR=y
RCREATE_REPO=y
RCREATE_REPO_DIR=y
```

**v2.x.x (explicit init):**
```bash
# Use the explicit init operation:
tngbackup init --config /etc/tngbackup.conf

# The parent directory of REPO_URI must exist.
```

**v2.x.x (auto-creation supported):**
```bash
# Automatic repository creation (optional):
CREATE_REPO="y"         # Create repository if missing
CREATE_REPO_DIR="y"     # Create parent directory if missing

# First backup automatically initializes repository:
tngbackup backup --config /etc/tngbackup.conf

# Or disable auto-creation if you prefer manual init:
CREATE_REPO="n"
# Then: tngbackup init --config /etc/tngbackup.conf
```

---

### Step 9b: SSH Password Authentication (v2.1+)

**v0.8.8:**
```bash
SSH_PASS="your-password"    # SSH password (insecure)
```

**v2.x.x (support restored):**
```bash
# Use sshpass for interactive password auth (when certificates unavailable):
SSH_PASSWORD="your-ssh-password"    # Requires 'sshpass' installed

# Example:
REPO_URI="ssh://user@backup.example.com/mnt/borg"
SSH_PASSWORD="server-password"
```

**⚠️ Security Note:**
- Less secure than SSH certificates (not recommended for critical environments)
- Always prefer key-based authentication when possible
- If needed, use SSH agent for passphrases on keys

---

## Complete Example: Conversion

### v0.8.8 Configuration

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

### v2.x.x Configuration (Equivalent)

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
CHECK_BACKUP=1          # Verify before backup
PRUNE_BACKUP=2          # Clean old archives after
COMPACT_BACKUP=2        # Reclaim space after

# Repository Auto-Creation
CREATE_REPO="y"         # Initialize if missing
CREATE_REPO_DIR="y"     # Create parent directory if missing

# Borg options
BORG_OPT="--compression zstd,10 --stats"
BORG_ENCRYPTION="repokey-blake2"

# SSH options
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519"
SSH_PORT=2222
# SSH_PASSWORD="server-password"  # Alternative if certificate unavailable

# Retention policy
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

### Execution Commands

**v0.8.8 (config-driven):**
```bash
bash tngbackup config.conf
```

**v2.x.x (operation-driven):**
```bash
# Initialize
tngbackup init --config /etc/tngbackup.conf

# Backup
tngbackup backup --config /etc/tngbackup.conf \
    --log /var/log/tngbackup.log \
    --audit-log /var/log/tngbackup-audit.log

# Check (if needed)
tngbackup check --config /etc/tngbackup.conf

# Prune
tngbackup prune --config /etc/tngbackup.conf

# Compact
tngbackup compact --config /etc/tngbackup.conf
```

Or with wrapper script:

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

## Batch Mode: Multiple Backups

If in v0.8.8 you had **two separate repositories** (local and remote):

**v0.8.8:**
```bash
# Single config file with LOCAL=y and REMOTE=y
```

**v2.x.x with Batch Mode:**

Create two separate files in `/etc/tngbackup/`:

```
/etc/tngbackup/
├── local-backup.conf       # REPO_URI="/mnt/borg/..."
└── remote-backup.conf      # REPO_URI="ssh://..."
```

Run both:

```bash
tngbackup backup --config /etc/tngbackup/ --log /var/log/tngbackup.log
tngbackup prune --config /etc/tngbackup/ --audit-log /var/log/tngbackup-audit.log
tngbackup compact --config /etc/tngbackup/
```

---

## Migration Checklist

**Base Configuration:**
- [ ] Choose local or remote repository (v2.x.x supports one per config)
- [ ] Convert `REPOSITORY` + `LOCAL/REMOTE_REPO` → `REPO_URI`
- [ ] Convert `BACKUP_PATH` from `;` separated to space separated
- [ ] Rename `BACKUP_EXCL` → `BACKUP_EXCLUDE` (optional, both work)
- [ ] Unify `LOCAL_KEEP_*` / `REMOTE_KEEP_*` → `KEEP_*`
- [ ] Convert SSH: `SSH_USER`, `SSH_HOST`, `SSH_PORT`, `SSH_CERT` → `REPO_URI` + `SSH_OPT`
- [ ] Rename `BORG_ENCRIPTION` → `BORG_ENCRYPTION`
- [ ] Merge `LOCAL_OPT` and `REMOTE_OPT` → `BORG_OPT`

**New Features (v2.x.x):**
- [ ] Optional: Convert `CHECK`, `PRUNE`, `COMPACT` (0/1/2) → `CHECK_BACKUP`, `PRUNE_BACKUP`, `COMPACT_BACKUP`
- [ ] Optional: Add `PRERUN` and `POSTRUN` (now natively supported, no wrapper script needed)
- [ ] Optional: Configure `CREATE_REPO` and `CREATE_REPO_DIR` for automatic repository creation
- [ ] Optional: Configure `SSH_PASSWORD` if you cannot use SSH certificates (requires sshpass)

**Finalization:**
- [ ] If you set `CREATE_REPO=n`: Run `tngbackup init` manually once
- [ ] If you set `CREATE_REPO=y`: First backup will automatically create the repository
- [ ] Test with `DRYRUN=y DEBUG=y tngbackup backup --config ...`
- [ ] If multiple backups (local + remote): use batch mode with separate config directories

---

## Conversion Script (Bash)

If you have many v0.8.8 files to convert, this script helps:

```bash
#!/bin/bash

OLD_CONFIG="$1"
NEW_CONFIG="$2"

# Extract REPOSITORY
REPO=$(grep "^REPOSITORY=" "$OLD_CONFIG" | cut -d'"' -f2)

# Choose local or remote
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

# Convert BACKUP_PATH: ; → space
BACKUP_PATH=$(grep "^BACKUP_PATH=" "$OLD_CONFIG" | cut -d'"' -f2 | tr ';' ' ')

# Convert BACKUP_EXCL → BACKUP_EXCLUDE
BACKUP_EXCLUDE=$(grep "^BACKUP_EXCL=" "$OLD_CONFIG" | cut -d'"' -f2)

# Generate new config
cat > "$NEW_CONFIG" <<EOF
# Converted from $OLD_CONFIG

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

echo "✓ Conversion completed: $NEW_CONFIG"
```

Usage:
```bash
bash convert.sh old-config.conf new-config.conf
```

---

## Support and Questions

For migration issues, consult:

- `docs/USAGE.md` — Complete v2.x.x documentation
- `docs/examples/` — Configuration examples
- Audit log for error tracking: `--audit-log /var/log/tngbackup-audit.log`

---

**Document version:** v2.x.x  
**Last updated:** September 2026
