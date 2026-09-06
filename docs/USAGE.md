# TNGBackup - Usage Guide

TNGBackup ("The Next Generation Backup") is a Bash wrapper around
[Borg Backup](https://www.borgbackup.org/). It centralises repository
configuration, credential handling, retention policy and audit logging so that
a full backup routine can be expressed in a single small configuration file and
driven by one command.

This document describes version **2.0.2** of the `tngbackup` script.

---

## Table of contents

1. [Status and testing](#status-and-testing)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Concepts](#concepts)
5. [Command line synopsis](#command-line-synopsis)
6. [Configuration file reference](#configuration-file-reference)
7. [Repository URI formats](#repository-uri-formats)
8. [Dry-run mode](#dry-run-mode)
9. [Operations](#operations)
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
10. [Interactive menu](#interactive-menu)
11. [Retention policy](#retention-policy)
12. [Batch mode](#batch-mode)
13. [Logging](#logging)
14. [Security notes](#security-notes)
15. [Scheduling](#scheduling)
16. [Troubleshooting](#troubleshooting)
17. [Exit codes](#exit-codes)
18. [Tests](#tests)

---

## Status and testing

All ten operations - `init`, `backup`, `list`, `mount`, `check`, `prune`,
`compact`, `info`, `delete` and `extract` - are implemented and dispatched
through a single shared `dispatch_operation` function, used identically by
single-config and batch runs.

The suite is covered by two test scripts in `tests/`:

| Script | Needs Borg? | What it covers |
|---|---|---|
| `tests/dispatch-test.sh` | No | 26 checks. Puts a stub `borg` first on `PATH` and records the command line it receives, so argument handling, operation dispatch, config loading, CLI precedence, dry-run, batch mode, audit-log format and the success/warning/failure exit-code mapping are all verified anywhere. |
| `tests/integration-test.sh` | Yes | Creates a throwaway Borg repository in a temporary directory, exercises every operation against it for real, verifies the audit log, then removes everything. |

```bash
./tests/dispatch-test.sh                          # runs anywhere
./tests/integration-test.sh                       # needs a real Borg
TNGB_TEST_MOUNT=y ./tests/integration-test.sh     # also exercises mount (needs FUSE)
```

See [Tests](#tests) for exit codes and details.

Borg itself changes behaviour between major versions (notably 1.x versus 2.x:
archive addressing, `borg init` versus `borg repo-create`, compaction
semantics). TNGBackup targets Borg 1.2/1.3 command syntax. Run the integration
test against your installed Borg version before putting the tool into
production, and rehearse a restore at least once.

---

## Requirements

| Component | Minimum | Notes |
|---|---|---|
| Bash | 4.0 | The script uses `mapfile`, arrays, `read -ra`, `${!var}` indirection and `set -o pipefail`. Enforced by `install.sh`. |
| Borg Backup | 1.2 (1.3 recommended) | Must be on `PATH` as `borg`. Checked by `install.sh` and again at runtime by `validate_config`. |
| `getopt` | util-linux | GNU `getopt` with long-option support. The BSD/macOS built-in `getopt` will not work. |
| `coreutils` | any recent | `date`, `touch`, `chmod`, `tee`, `mkdir`. |
| OpenSSH client | any recent | Only for remote (`ssh://`) repositories. |
| FUSE + `llfuse`/`pyfuse3` | optional | Only needed for the `mount` operation. Install `borgbackup[fuse]` or your distribution's fuse extra. |
| `shred` | optional | Used by the cleanup trap to destroy temporary config files; falls back to `rm -f`. |
| `mountpoint` | optional | Used by the cleanup trap to detect and unmount stale Borg mounts. |

Check what you have:

```bash
bash --version | head -1
borg --version
getopt --test; echo "getopt exit: $?"   # 4 means GNU enhanced getopt
```

TNGBackup is a Linux/BSD tool. It is not supported on Windows except through
WSL or Git Bash with GNU getopt available.

---

## Installation

### Using install.sh

```bash
git clone https://github.com/RedFoxy/TNGBackup.git
cd TNGBackup
sudo ./install.sh
```

The installer:

1. Verifies Bash 4.0+ and Borg 1.2+, and warns (without failing) if `getopt` or
   `ssh` are missing.
2. Installs the script to `$PREFIX/bin/tngbackup` with mode 0755
   (`PREFIX` defaults to `/usr/local`).
3. Creates `/var/log/tngbackup.log` and `/var/log/tngbackup-audit.log` with
   mode 0600, or `chmod 600`s them if they already exist.
4. Installs `docs/tngbackup.1` to `$PREFIX/share/man/man1/`.
5. Installs a configuration template to `/etc/tngbackup.conf` with mode 0600 -
   **only if that file does not already exist**, so an upgrade never clobbers
   your live configuration.
6. Installs `tngbackup.service` and `tngbackup.timer` into
   `/etc/systemd/system/` when that directory exists.

Steps 3 to 6 warn and continue if a destination is not writable, so a
non-root install still produces a working binary.

Environment variables recognised by the installer:

| Variable | Default | Purpose |
|---|---|---|
| `PREFIX` | `/usr/local` | Installation prefix. |
| `BIN_DIR` | `$PREFIX/bin` | Binary destination. |
| `MAN_DIR` | `$PREFIX/share/man/man1` | Man page destination. |
| `SYSTEMD_DIR` | `/etc/systemd/system` | Unit destination. |
| `CONFIG_FILE` | `/etc/tngbackup.conf` | Config template destination. |
| `LOG_FILE` | `/var/log/tngbackup.log` | Log file to create. |
| `AUDIT_LOG_FILE` | `/var/log/tngbackup-audit.log` | Audit log to create. |

Per-user installation, no root required:

```bash
PREFIX="$HOME/.local" \
CONFIG_FILE="$HOME/.config/tngbackup.conf" \
LOG_FILE="$HOME/.local/state/tngbackup.log" \
AUDIT_LOG_FILE="$HOME/.local/state/tngbackup-audit.log" \
./install.sh
```

Help and removal:

```bash
./install.sh --help
sudo ./install.sh --uninstall
```

`--uninstall` removes the binary, the man page and the systemd units. It
deliberately **leaves the configuration file and both log files in place** -
losing a passphrase file to an uninstall would be unrecoverable. Remove them by
hand if you really mean to.

### Configuring after install

```bash
sudo "${EDITOR:-vi}" /etc/tngbackup.conf
sudo chmod 600 /etc/tngbackup.conf
man tngbackup
```

For batch mode, create a directory instead:

```bash
sudo mkdir -p /etc/tngbackup
sudo chmod 700 /etc/tngbackup
sudo install -m 0600 docs/examples/batch-configs/webserver.conf /etc/tngbackup/
```

---

## Concepts

**Configuration is sourced, not parsed.** `load_config` runs `source` on the
configuration file inside the running shell. That means a config file is a
Bash script: you can compute values, reference other variables, and call
commands. It also means a config file can execute arbitrary code, which is why
ownership and permissions matter (see [Security notes](#security-notes)).

**Precedence, honestly, per option.** The order of operations in `main()` is:
parse the command line, show the menu if no operation was given, save the CLI
repository and passphrase, source the configuration file, then re-apply those
two saved values on top. So:

| Setting | Effective precedence |
|---|---|
| `-r` / `--repo` (`REPO_URI`) | **CLI > config file > environment > default.** Re-applied after sourcing, so the CLI genuinely wins. |
| `-p` / `--passphrase` (`REPO_PASSPHRASE`) | **CLI > config file > environment > default.** Same mechanism. |
| `--archive`, `--path`, `--mountpoint`, `--log`, `--audit-log` | Applied **before** the config file is sourced, so a config file that assigns `ARCHIVE_NAME`, `RESTORE_PATH`, `MOUNT_PATH`, `LOG_FILE` or `AUDIT_LOG_FILE` unconditionally overrides the CLI value. Leave those variables out of the config file (or guard them with `${VAR:-...}`) if you want to set them from the command line. |
| `-c` / `--config` | Always the CLI value - it selects which file is sourced. |
| Everything else | Environment > script default, then whatever the config file assigns. |

In **batch mode** `--repo` and `--passphrase` have no effect: the batch loop
resets `REPO_URI` and `REPO_PASSPHRASE` before sourcing each config, and the
re-apply step is not reached. Each config file must carry its own repository
and passphrase, which is the point of batch mode.

**Environment variables.** Every configuration variable has a
`${VAR:-default}` initialiser at the top of the script, so exporting the
variable sets its value before the config file is read. An unconditional
assignment in the config file still wins over the environment.

**Credentials live in the environment for the duration of a Borg call.**
`setup_borg_env` exports `BORG_PASSPHRASE` and `BORG_REPO` before each Borg
invocation, and adds `BORG_RSH` automatically for `ssh://` repositories. The
`EXIT`/`INT`/`TERM` trap unsets all of them at the end of the run.

**Borg is never allowed to block on a prompt.** Every Borg invocation goes
through `run_borg`, which runs `borg ... < /dev/null`, and the script exports
`BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes` and
`BORG_RELOCATED_REPO_ACCESS_IS_OK=yes` at startup. A confirmation prompt
therefore fails fast instead of hanging a cron job forever. Both variables
respect an existing value from the environment, so you can set either to `no`
if you would rather have those two conditions abort the run.

---

## Command line synopsis

```
tngbackup [OPERATION] [OPTIONS]
```

`OPERATION` is a bare word (no leading dash). If it is omitted, the interactive
menu is shown.

| Option | Argument | Description |
|---|---|---|
| `-c`, `--config` | FILE or DIR | Configuration file to source. If a **directory** is given, batch mode is used and every `*.conf` file inside it is processed in turn. Default: `/etc/tngbackup.conf` (or `$TNGB_CONFIG`). |
| `-r`, `--repo` | URI | Repository URI. Sets `REPO_URI`, and is re-applied after the config file is sourced. |
| `-p`, `--passphrase` | STRING | Repository passphrase. Sets `REPO_PASSPHRASE`, re-applied after the config file. Avoid on shared systems. |
| `--archive` | NAME | Archive name. Used by `backup`, `list`, `check`, `info`, `mount`, and **required** by `delete` and `extract`. |
| `--path` | PATH | Context-dependent. With `backup` it sets `BACKUP_PATH`; with every other operation, `extract` included, it sets `RESTORE_PATH`. |
| `--mountpoint` | PATH | Mount directory for `mount`. Sets `MOUNT_PATH`. Default `/mnt/borg`. |
| `-l`, `--log` | FILE | Human-readable log file. The file is created immediately and `chmod 600`. |
| `--audit-log` | FILE | Machine-readable audit log. Created immediately and `chmod 600`. |
| `-h`, `--help` | | Print the built-in help and exit 0. |

Notes on argument handling:

- Options are parsed with GNU `getopt`, so `--config=/etc/x.conf` and
  `--config /etc/x.conf` are both accepted, as are clustered short options.
- An unrecognised option causes the help text to be printed and the script to
  exit with status 1.
- The operation is taken from the **first positional argument** after `--`.
  `tngbackup --config /etc/tngbackup.conf backup` and
  `tngbackup backup --config /etc/tngbackup.conf` are equivalent.
- `--path` is overloaded. This is a common source of confusion: with
  `extract`, `--path` is the *restore destination*, not a selector for what to
  extract.
- `--log` and `--audit-log` create their file eagerly. If the path is not
  writable (`/var/log` as a non-root user, say) the script aborts under
  `set -e` before doing any work. Once a log file *is* configured, a later
  failure to write to it is tolerated and never aborts a backup.

---

## Configuration file reference

A configuration file is a Bash fragment. Quote every value. One assignment per
line. Comments start with `#`.

Because the script applies real defaults, a minimal config is genuinely
minimal:

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_PASSPHRASE='correct horse battery staple'
BACKUP_PATH="/home /etc"
```

That inherits `repokey-blake2` encryption, the default SSH options, and the
default retention policy - which does mean `prune` will act on it, so read
[Retention policy](#retention-policy) before running one.

### Core

| Variable | Type | Default | Description |
|---|---|---|---|
| `TNGB_CONFIG` | path | `/etc/tngbackup.conf` | Path of the configuration file or directory to load. Normally set via `--config` or the environment, not inside a config file. |
| `DEBUG` | `y`/`n` | `n` | Print `[DEBUG]` diagnostics: config loading, CLI parsing, the exact Borg command line, retention policy, cleanup steps. |
| `DRYRUN` | `y`/`n` | `n` | Log each Borg command instead of running it. See [Dry-run mode](#dry-run-mode). Independent of `DEBUG`. |
| `SHOWTEXT` | `y`/`n` | `y` | Print timestamped `[INFO]`/`[WARN]`/`[ERROR]` lines to the console. Set to `n` for quiet cron jobs that only write to `LOG_FILE`. |
| `BACKUP` | `y`/`n` | `y` | Reserved compatibility flag carried over from v1. Present with a default; the v2 dispatcher selects work by operation name. |

```bash
DEBUG="n"
DRYRUN="n"
SHOWTEXT="y"
```

### Repository

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `REPO_URI` | string | (empty) | yes | Borg repository location. Local absolute path or `ssh://` URI. Exported as `BORG_REPO`. |
| `REPO_PASSPHRASE` | string | (empty) | yes | Passphrase for the encrypted repository. Exported as `BORG_PASSPHRASE`. |
| `BORG_ENCRYPTION` | string | `repokey-blake2` | no | Encryption mode passed to `borg init --encryption=`. Only used by `init`. |

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_PASSPHRASE='correct horse battery staple'
BORG_ENCRYPTION="repokey-blake2"
```

Valid `BORG_ENCRYPTION` values for Borg 1.x: `none`, `authenticated`,
`authenticated-blake2`, `repokey`, `repokey-blake2`, `keyfile`,
`keyfile-blake2`. `repokey*` stores the key inside the repository (convenient,
protected by the passphrase); `keyfile*` stores it in `~/.config/borg/keys`
(the repository is useless without that file - back it up separately).

`validate_config` refuses to run any operation if `REPO_URI` or
`REPO_PASSPHRASE` is empty, even for an unencrypted repository. If you really
use `--encryption=none`, set `REPO_PASSPHRASE` to any non-empty placeholder;
Borg ignores it.

### Backup

| Variable | Type | Default | Description |
|---|---|---|---|
| `BACKUP_PATH` | space-separated paths | (empty) | What to back up. Required for the `backup` operation. |
| `BACKUP_EXCLUDE` | **semicolon**-separated patterns | (empty) | Exclusion patterns. Each non-empty item becomes one `--exclude` argument. |
| `ARCHIVE_NAME` | string | (empty) | Archive name. If empty, `backup` generates `archive-YYYYmmdd-HHMMSS`. |
| `RESTORE_PATH` | path | (empty) | Destination directory for `extract`. Falls back to the current directory if unset. |
| `MOUNT_PATH` | path | `/mnt/borg` | Mount point for `mount`. Created automatically if missing. |

```bash
BACKUP_PATH="/home /etc /var/www"
BACKUP_EXCLUDE="*.tmp;*/node_modules;/var/www/*/cache;*/.cache"
ARCHIVE_NAME=""
RESTORE_PATH="/tmp/restore"
MOUNT_PATH="/mnt/borg"
```

Two separators are in play and mixing them is the most frequent configuration
mistake:

- `BACKUP_PATH` is **space**-separated (it is word-split into a list of backup
  targets).
- `BACKUP_EXCLUDE` is **semicolon**-separated (it is split with
  `IFS=';' read -ra`). A space inside `BACKUP_EXCLUDE` is part of the pattern,
  not a separator, and exclusion patterns containing spaces work correctly:
  the Borg command line is built as a Bash array, not by string concatenation.
  Empty items between semicolons are skipped, so a trailing `;` is harmless.

`BACKUP_PATH` is still word-split, so **backup source paths containing spaces
cannot be expressed**. Use a symlink or a path without spaces.

`ARCHIVE_NAME` is used literally. Borg's own placeholder syntax
(`{hostname}-{now:%Y%m%d}`) is passed through unmodified and does work for
`borg create`, but the script's log and audit records would then contain the
uninterpolated template rather than the final archive name. For readable audit
trails prefer leaving `ARCHIVE_NAME` empty, or computing it in the config file:

```bash
ARCHIVE_NAME="$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
```

### Borg and SSH options

| Variable | Type | Default | Description |
|---|---|---|---|
| `BORG_OPT` | string | (empty) | Extra options inserted into `borg create`. Word-split, so no single argument may contain spaces. |
| `SSH_OPT` | string | `-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5` | SSH client options used to build `BORG_RSH` for remote repositories. |
| `SSH_PORT` | integer | `22` | SSH port for remote repositories. |

`SSH_OPT` and `SSH_PORT` are wired up automatically. `setup_borg_env` inspects
`REPO_URI` before every Borg call and, when it begins with `ssh://`, exports:

```
BORG_RSH="ssh $SSH_OPT -p $SSH_PORT"
```

For a local repository it unsets `BORG_RSH` instead, so a stale value cannot
leak in. **You do not need to export `BORG_RSH` yourself.** The defaults
already give you the three options that matter for unattended backups:
`BatchMode=yes` so a broken key fails fast instead of prompting,
`StrictHostKeyChecking=accept-new` so a first connection succeeds and the host
key is then pinned, and `ConnectTimeout=5` so an unreachable server does not
consume the whole backup window.

Override `SSH_OPT` when you need a specific key or keepalives - remember that
you are replacing the default, so repeat the options you still want:

```bash
SSH_PORT="2222"
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519 -o ServerAliveInterval=30"
```

If Borg is not on the server's non-interactive `PATH`, add to the config file:

```bash
export BORG_REMOTE_PATH="/usr/local/bin/borg"
```

Useful `BORG_OPT` values:

| Option | Effect |
|---|---|
| `--compression lz4` | Fast, low ratio. Good for large, already-compressed data. |
| `--compression zstd,10` | Balanced. Good general-purpose choice. |
| `--compression zstd,22` | Maximum ratio, slow, CPU heavy. |
| `--stats` | Print deduplicated/compressed size summary at the end. |
| `--exclude-caches` | Skip directories tagged with `CACHEDIR.TAG`. |
| `--one-file-system` | Do not cross filesystem boundaries. |
| `--checkpoint-interval 900` | Checkpoint every 15 minutes so an interrupted large backup can resume. |
| `--exclude-if-present .nobackup` | Skip directories containing a marker file. |

`BORG_OPT` applies to `borg create` only. It is not passed to `check`,
`prune`, `info` or the other operations.

### Retention

| Variable | Type | Default | Description |
|---|---|---|---|
| `KEEP_LAST` | integer | **`10`** | Keep the N most recent archives regardless of age. |
| `KEEP_HOURLY` | integer | (empty) | Keep the newest archive of each of the last N hours. |
| `KEEP_DAILY` | integer | **`7`** | Keep the newest archive of each of the last N days. |
| `KEEP_WEEKLY` | integer | **`4`** | Keep the newest archive of each of the last N weeks. |
| `KEEP_MONTHLY` | integer | **`12`** | Keep the newest archive of each of the last N months. |
| `KEEP_YEARLY` | integer | (empty) | Keep the newest archive of each of the last N years. |

A rule is applied only when its value is non-empty **and** not `"0"`. Both
`KEEP_HOURLY=""` and `KEEP_HOURLY="0"` disable the hourly rule.

Note the non-empty defaults: unless your config says otherwise, `prune` runs
with `--keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12`. See
[Retention policy](#retention-policy).

### Logging

| Variable | Type | Default | Description |
|---|---|---|---|
| `LOG_FILE` | path | (empty) | Human-readable log. Appended to by `log()`, and Borg's combined output is `tee`d into it. When empty, Borg output simply goes to stdout. |
| `AUDIT_LOG_FILE` | path | (empty) | Structured audit trail, one line per completed operation. When empty, auditing is silently disabled. |

```bash
LOG_FILE="/var/log/tngbackup.log"
AUDIT_LOG_FILE="/var/log/tngbackup-audit.log"
```

When these are set with `--log` / `--audit-log` the script creates the files and
applies mode 600. When they are set in the configuration file instead, the
files are appended to as-is; create them with the right permissions yourself,
or let `install.sh` do it:

```bash
sudo install -m 0600 /dev/null /var/log/tngbackup.log
sudo install -m 0600 /dev/null /var/log/tngbackup-audit.log
```

Writes to `LOG_FILE` are best-effort: if the file becomes unwritable mid-run,
the message is dropped rather than aborting the backup.

---

## Repository URI formats

### Local repository

An absolute path on a locally mounted filesystem:

```bash
REPO_URI="/mnt/backup/borg-repo"
REPO_URI="/srv/borg/webserver"
```

The parent directory must exist and be writable. The repository directory
itself is created by `borg init`. For a local URI the script explicitly unsets
`BORG_RSH`, so `SSH_OPT` and `SSH_PORT` are ignored.

A local path may point at a network filesystem (NFS, CIFS, sshfs), but this is
discouraged: Borg's locking and fsync behaviour over network filesystems is
fragile, and performance is much worse than a real `ssh://` repository, because
every chunk lookup becomes a network round trip. Prefer `ssh://` whenever the
target machine can run Borg.

### SSH repository

```
ssh://user@host:port/absolute/path/to/repo
ssh://user@host/absolute/path/to/repo          # default port 22
ssh://user@host/./relative/to/home             # ./ means relative to $HOME
ssh://user@host/~/backups/repo                 # ~ expansion on the remote side
```

Examples:

```bash
REPO_URI="ssh://borg@backup.example.com:22/srv/borg/webserver"
REPO_URI="ssh://borg@10.0.0.20:2222/mnt/raid/borg/db"
REPO_URI="ssh://backup@nas.lan/./borg/home"
```

An `ssh://` URI triggers `BORG_RSH="ssh $SSH_OPT -p $SSH_PORT"` automatically.
Keep `SSH_PORT` consistent with any port written into the URI itself.

Requirements for a remote repository:

1. Borg must be installed on the **remote** host too, and the versions should
   be compatible (same major/minor family).
2. Key-based authentication must work non-interactively:
   ```bash
   ssh -o BatchMode=yes -p 22 borg@backup.example.com borg --version
   ```
   If that command prompts for anything, fix it before scheduling a backup.
3. The remote path's parent must exist and be writable by the SSH user.

Hardening the remote side: restrict the key in the server's
`~/.ssh/authorized_keys` so it can only serve one repository:

```
command="borg serve --restrict-to-repository /srv/borg/webserver --append-only",restrict ssh-ed25519 AAAA... borg@client
```

`--append-only` means a compromised client can add archives but cannot delete
history - a good defence against ransomware that hunts for backups. Note that
with `--append-only` on the server, `prune`, `delete` and `compact` from the
client will not actually free space; you compact on the server instead.

---

## Dry-run mode

`DRYRUN=y` makes every Borg invocation print instead of execute. `run_borg`
logs the exact command as `[DRY-RUN] borg ...` and returns success, so the
operation reports `SUCCESS` and writes a normal audit record without touching
the repository. Directory creation for `mount` and `extract` is skipped too.

It is set from the environment or the config file - there is no CLI flag, and
it does **not** require `DEBUG`:

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

Sample output:

```
[2026-09-05 12:41:03] [INFO] Starting backup from: /home /etc /var/www
[2026-09-05 12:41:03] [INFO] [DRY-RUN] borg create --compression zstd,10 --stats --exclude *.tmp --exclude */node_modules ::archive-20260905-124103 /home /etc /var/www
[2026-09-05 12:41:03] [INFO] backup completed successfully
[2026-09-05 12:41:03] [INFO] Operation 'backup' finished with status SUCCESS in 0s
```

Use it to verify a new config, a changed exclusion list, or a batch directory
before it runs unattended for the first time.

Two limits to keep in mind:

- Configuration validation still applies, so `REPO_URI`, `REPO_PASSPHRASE` and
  a `borg` binary on `PATH` are all still required for a dry run.
- A dry run always reports `SUCCESS`, because no command actually ran. It
  proves what *would* be executed, not that the repository is reachable or the
  passphrase correct. For that, run a real `list`.

Borg's own `--dry-run` is a different thing and remains available through
`BORG_OPT` (`BORG_OPT="--dry-run --list"`), which does contact the repository
and reports the files that would be archived.

---

## Operations

Every operation is invoked the same way:

```bash
tngbackup OPERATION [OPTIONS]
```

All operations require `REPO_URI` and `REPO_PASSPHRASE` (from config,
environment, or `-r`/`-p`), and require `borg` on `PATH`. Every one of them
calls `setup_borg_env` first, so `BORG_REPO`, `BORG_PASSPHRASE` and - for
`ssh://` - `BORG_RSH` are in place, and every one finishes through
`finish_operation`, which writes the audit record and sets the process exit
code from the Borg result.

`finish_operation` follows Borg's own three-way exit-code convention:

| Borg exit | Status | Logged as | `tngbackup` exits |
|---|---|---|---|
| `0` | `SUCCESS` | `INFO`: `<op> completed successfully` | `0` |
| `1` | `WARNING` | `WARN`: `<op> completed with warnings (borg exit 1)` | `0` |
| `>= 2` | `FAILED` | `ERROR`: `<op> failed (borg exit N)` | that code |

A warning means the operation completed and did what it was asked - a backup
that could not read a handful of files still produced an archive - so it is
deliberately **not** treated as a failure. It is still recorded distinctly in
the audit log, so you can monitor for it separately.

Failures detected by the script *before* Borg is invoked - a missing
`--archive` for `delete`/`extract`, an unconfigured retention policy for
`prune`, an unwritable mountpoint or restore directory - bypass this table:
they set `FAILED` directly and exit 1.

Because `BORG_REPO` is exported, most operations address the repository
implicitly and archives with the `::name` shorthand.

### init

Creates a new, empty Borg repository at `REPO_URI` using `BORG_ENCRYPTION`.

Runs: `borg init --encryption="$BORG_ENCRYPTION" "$REPO_URI"`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`. **Optional:** `BORG_ENCRYPTION`.

```bash
# From a config file
tngbackup init --config /etc/tngbackup.conf

# Entirely from the command line
tngbackup init --repo /mnt/backup/borg-repo --passphrase 'correct horse battery staple'

# Config file for everything else, repository overridden on the CLI
tngbackup init --config /etc/tngbackup/webserver.conf \
               --repo ssh://borg@backup.example.com:22/srv/borg/web
```

Sample output:

```
[2026-09-05 02:15:11] [INFO] Initializing repository: /mnt/backup/borg-repo
[2026-09-05 02:15:12] [INFO] init completed successfully
[2026-09-05 02:15:12] [INFO] Operation 'init' finished with status SUCCESS in 1s
```

Immediately afterwards, export and store the repository key somewhere other
than the repository:

```bash
BORG_PASSPHRASE='...' borg key export /mnt/backup/borg-repo /root/borg-web.key
chmod 600 /root/borg-web.key
```

Without the passphrase (and, for `keyfile` modes, the key file) the repository
is permanently unreadable. There is no recovery path.

Common errors:

| Message | Cause | Fix |
|---|---|---|
| `A repository already exists at ...` | `init` was run twice | Nothing to do; the repository is already there. |
| `Missing required configuration: REPO_URI` | No repo configured | Set `REPO_URI` or pass `--repo`. |
| `borg binary not found in PATH` | Borg not installed | Install `borgbackup`. |
| `Permission denied` on the parent directory | Cannot create the repo dir | `mkdir -p` the parent and fix ownership. |
| SSH connection refused/timed out | Wrong host, port or key | Test with `ssh -o BatchMode=yes -p PORT user@host borg --version`. |

### backup

Creates one archive containing `BACKUP_PATH`, honouring `BACKUP_EXCLUDE` and
`BORG_OPT`.

Runs: `borg create [BORG_OPT words] [--exclude PATTERN]... ::ARCHIVE_NAME PATHS...`

The command line is assembled as a Bash array, so exclusion patterns with
spaces are safe. `BORG_OPT` and `BACKUP_PATH` are deliberately word-split.

**Required:** `REPO_URI`, `REPO_PASSPHRASE`, `BACKUP_PATH`.
**Optional:** `BACKUP_EXCLUDE`, `ARCHIVE_NAME`, `BORG_OPT`.

If `ARCHIVE_NAME` is empty, `archive-YYYYmmdd-HHMMSS` is generated from the
local clock.

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

Sample output with `BORG_OPT="--stats"`:

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

Notes:

- Backups are **not** pruned automatically. Run `prune` (and `compact`) as
  separate steps - see [Scheduling](#scheduling).
- Consecutive backups of the same data are cheap: Borg deduplicates at the
  chunk level, so an unchanged 40 GB tree costs a few megabytes.
- Borg exit code 1 means "completed with warnings" (unreadable or vanished
  files, say). The archive *was* created, so TNGBackup records the run
  `WARNING`, logs `backup completed with warnings (borg exit 1)` and **exits
  0**. A warning is not a failure; check the log to see which files were
  skipped.
- For consistent database backups, dump first and back up the dump - see
  `docs/examples/batch-configs/database.conf`.

Common errors:

| Message | Cause | Fix |
|---|---|---|
| `BACKUP_PATH not set; no files to backup` | Missing source | Set `BACKUP_PATH` or pass `--path`. |
| `Repository ... does not exist` | Never initialised | Run `tngbackup init` first. |
| `Failed to create/acquire the lock` | Concurrent run or stale lock | See [Troubleshooting](#troubleshooting). |
| `passphrase supplied ... is incorrect` | Wrong `REPO_PASSPHRASE` | Fix the config; a repository cannot be recovered without the right passphrase. |
| `Archive ... already exists` | Duplicate `ARCHIVE_NAME` | Use a unique name or leave `ARCHIVE_NAME` empty. |
| `No space left on device` | Repository filesystem full | Prune and compact, or add capacity. |

### list

With no `--archive`, lists all archives in the repository. With `--archive`,
lists the files inside that archive.

Runs: `borg list` (repository, via `BORG_REPO`) or `borg list ::ARCHIVE_NAME`.

**Required:** `REPO_URI`, `REPO_PASSPHRASE`. **Optional:** `ARCHIVE_NAME`.

```bash
# All archives
tngbackup list --config /etc/tngbackup.conf

# Contents of one archive
tngbackup list --config /etc/tngbackup.conf --archive archive-20260905-030001

# Ad-hoc against a repository with no config file
tngbackup list --repo /mnt/backup/borg-repo --passphrase 'secret'
```

Sample output (repository listing):

```
archive-20260901-030001              Mon, 2026-09-01 03:00:01 [1a2b3c...]
archive-20260902-030001              Tue, 2026-09-02 03:00:02 [4d5e6f...]
archive-20260903-030002              Wed, 2026-09-03 03:00:02 [7a8b9c...]
archive-20260904-030001              Thu, 2026-09-04 03:00:01 [0d1e2f...]
archive-20260905-030001              Fri, 2026-09-05 03:00:01 [3a4b5c...]
```

Sample output (archive listing, truncated):

```
drwxr-xr-x root   root          0 Fri, 2026-09-05 02:11:04 etc
-rw-r--r-- root   root       2907 Thu, 2026-08-21 09:33:10 etc/nginx/nginx.conf
-rw-r--r-- root   root       1421 Wed, 2026-07-02 17:45:51 etc/fstab
```

Listing a large archive produces a very large amount of output. Pipe it:

```bash
tngbackup list --config /etc/tngbackup.conf --archive archive-20260905-030001 \
  | grep 'etc/nginx'
```

`list` is the cheapest way to verify that credentials and connectivity are
correct - the recommended repository-existence probe, much faster than `check`.

The audit record's details field is the archive name, or `all-archives` for a
repository listing.

Common errors:

| Message | Cause | Fix |
|---|---|---|
| `Archive ... does not exist` | Typo in `--archive` | Run `list` without `--archive` to see valid names. |
| `Repository ... does not exist` | Wrong `REPO_URI` | Verify path/URI. |
| `Connection closed by remote host` | SSH/`borg serve` problem | Test `ssh -o BatchMode=yes host borg --version`. |

### mount

Mounts the whole repository (every archive as a subdirectory) or a single
archive at `MOUNT_PATH`, read-only, via FUSE. This is the most convenient way
to browse and cherry-pick files with ordinary tools.

Runs: `borg mount ::ARCHIVE_NAME "$MOUNT_PATH"`, or
`borg mount "$REPO_URI" "$MOUNT_PATH"` when no archive is given.

**Required:** `REPO_URI`, `REPO_PASSPHRASE`, `MOUNT_PATH` (default `/mnt/borg`).
**Optional:** `ARCHIVE_NAME`.

The mount point is **created automatically** if it does not exist (skipped
under `DRYRUN=y`). On success the script prints the unmount hint and clears
`MOUNT_PATH` internally, so the cleanup trap will not tear down the mount you
just asked for.

```bash
# Mount the whole repository: one directory per archive
tngbackup mount --config /etc/tngbackup.conf --mountpoint /mnt/borg

# Mount a single archive
tngbackup mount --config /etc/tngbackup.conf \
                --archive archive-20260905-030001 \
                --mountpoint /mnt/borg
```

Sample output:

```
[2026-09-05 10:22:14] [INFO] Mounting archive archive-20260905-030001 on /mnt/borg
[2026-09-05 10:22:16] [INFO] Unmount with: borg umount /mnt/borg
[2026-09-05 10:22:16] [INFO] mount completed successfully
```

Browsing and unmounting:

```bash
ls /mnt/borg
cp /mnt/borg/etc/nginx/nginx.conf /tmp/
borg umount /mnt/borg
```

Note that `borg mount` daemonises by default, so the mount outlives the
`tngbackup` process - which is why the unmount is left to you. Unmount when
you are done: a forgotten mount holds a repository lock and will block the
next backup.

Requirements and common errors:

| Message | Cause | Fix |
|---|---|---|
| `borg: Unrecognized command mount` / `fuse is not installed` | FUSE bindings missing | `pip install 'borgbackup[fuse]'` or install your distro's `borgbackup-fuse` / `python3-llfuse` package. |
| `fusermount: failed to open /dev/fuse: Permission denied` | User not allowed to use FUSE | Run as root or add the user to the `fuse` group. |
| `Cannot create mountpoint: ...` | Parent not writable | Choose a writable path or run as root. |
| `Device or resource busy` on unmount | A shell or process is inside the mount | `cd` out, then `fuser -mv /mnt/borg`. |
| Mount point not empty | Existing files at `MOUNT_PATH` | Use an empty directory. |

Mounting a **remote** repository works but every read is a network round trip.
For bulk restores, `extract` is far faster.

### check

Verifies repository consistency, or the integrity of one archive.

Runs:

- without `--archive`: `borg check --repository-only`
- with `--archive`: `borg check ::ARCHIVE_NAME`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`. **Optional:** `ARCHIVE_NAME`.

The default is deliberately the **fast** check. `--repository-only` verifies
segment files and the index without reading and decrypting archive data, so a
routine `tngbackup check` is cheap enough to schedule weekly. Naming an archive
switches to a full consistency check of that archive's chunks.

```bash
# Fast repository-only check
tngbackup check --config /etc/tngbackup.conf

# Full check of one archive
tngbackup check --config /etc/tngbackup.conf --archive archive-20260905-030001
```

Sample output of a clean repository check:

```
[2026-09-05 04:00:01] [INFO] Checking repository: /mnt/backup/borg-repo
Starting repository check
Starting repository index check
Completed repository check, no problems found.
[2026-09-05 04:01:38] [INFO] check completed successfully
```

The audit record's details field is `repository` for a repository check, or the
archive name for an archive check.

Practical guidance:

- A **full** archive check reads every chunk. Checking each archive in turn is
  a whole-repository read and can take hours; do it occasionally, not nightly.
- To verify archive data periodically without checking everything, check the
  newest archive by name each week and rotate through older ones.
- Never run `borg check --repair` casually. It can discard data to make the
  repository self-consistent. Take a copy of the repository first if the data
  matters. TNGBackup never passes `--repair`.
- For remote repositories, running `borg check` **on the server** avoids
  transferring the whole repository over the network.

| Message | Cause | Fix |
|---|---|---|
| `Data integrity error` | Bit rot or truncated file | Check the underlying storage/SMART first, then consider `--repair` on a copy. |
| Check appears to hang | Full archive read in progress | Expected for an archive check; watch I/O with `iostat`. |

### prune

Deletes archives that no retention rule requires, using the `KEEP_*`
variables. Pruning marks data as unused; it does **not** free disk space until
`compact` runs.

Runs: `borg prune --list --keep-last=N --keep-daily=N ...`

Only rules whose value is non-empty and not `"0"` contribute an option.
`--list` is always passed, so the log shows exactly which archives were kept
and which were pruned.

**Required:** `REPO_URI`, `REPO_PASSPHRASE`, and at least one active `KEEP_*`
rule.

```bash
tngbackup prune --config /etc/tngbackup.conf
tngbackup prune --config /etc/tngbackup.conf --audit-log /var/log/tngbackup-audit.log

# See what it would do without touching anything
DRYRUN=y DEBUG=y tngbackup prune --config /etc/tngbackup.conf
```

Sample output:

```
[2026-09-05 04:30:00] [INFO] Pruning repository: /mnt/backup/borg-repo
Keep         archive-20260905-030001   Fri, 2026-09-05 03:00:01
Keep         archive-20260904-030001   Thu, 2026-09-04 03:00:01
Pruning archive archive-20260820-030001 Wed, 2026-08-20 03:00:01
[2026-09-05 04:30:12] [INFO] prune completed successfully
```

The audit record's details field lists the retention options that were applied,
so the audit log records the policy in force at the time of each prune.

**There is no way to make this prune everything.** If every `KEEP_*` variable
is empty or `0`, `build_retention_opts` yields nothing and the operation
refuses to run:

```
[ERROR] No retention policy configured (set at least one of KEEP_LAST, KEEP_HOURLY, KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY, KEEP_YEARLY)
```

That is recorded as a `FAILED` prune in the audit log and exits 1.

The corollary matters more: **`KEEP_LAST` defaults to 10, and `KEEP_DAILY`,
`KEEP_WEEKLY` and `KEEP_MONTHLY` default to 7, 4 and 12.** A config file that
says nothing about retention still has a policy, and running `prune` against it
will delete archives that fall outside it. Before the first prune on any
repository, confirm the effective policy:

```bash
DEBUG=y DRYRUN=y tngbackup prune --config /etc/tngbackup.conf
# [DEBUG] Retention policy: --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12
```

and dry-run it against the real archive list with Borg:

```bash
export BORG_PASSPHRASE='...'
borg prune --list --dry-run --keep-last=10 --keep-daily=7 --keep-weekly=4 \
    --keep-monthly=12 /mnt/backup/borg-repo
```

Other cautions:

- If a repository holds archives from several different jobs, restrict pruning
  with `--glob-archives`/`--prefix` (Borg 1.2/1.3 respectively), or give each
  job its own repository. Batch mode gives each config its own `REPO_URI`,
  which is the clean approach.
- Prune uses archive **timestamps**, not names.
- In batch mode the `KEEP_*` variables are **not** reset between config files,
  so set all six explicitly in every batch config.

### compact

Rewrites repository segments to physically release the space freed by `prune`
and `delete`.

Runs: `borg compact`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`.

```bash
tngbackup compact --config /etc/tngbackup.conf
```

Notes:

- `compact` exists in Borg 1.2+. On Borg 1.1 the equivalent happened
  automatically during `prune`.
- It is I/O heavy and rewrites segment files. Run it after pruning, not before,
  and not on every backup - daily or weekly is plenty.
- Free space is only reclaimed after compaction. If `df` shows no change after
  a prune, this is why.
- On an append-only remote, run compaction on the server side.

| Message | Cause | Fix |
|---|---|---|
| `Unrecognized command compact` | Borg 1.1 or older | Upgrade to Borg 1.2+; pruning already compacts on 1.1. |
| `Failed to create/acquire the lock` | Another operation running | Wait, or clear a stale lock (see Troubleshooting). |

### info

Shows repository statistics, or statistics for one archive when `--archive` is
given.

Runs: `borg info` or `borg info ::ARCHIVE_NAME`.

**Required:** `REPO_URI`, `REPO_PASSPHRASE`. **Optional:** `ARCHIVE_NAME`.

```bash
tngbackup info --config /etc/tngbackup.conf
tngbackup info --config /etc/tngbackup.conf --archive archive-20260905-030001
```

Sample repository output:

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

Read "Deduplicated size" as the actual space the repository occupies. The gap
between it and "Original size" is the deduplication and compression benefit.

### delete

Deletes one named archive.

Runs: `borg delete ::ARCHIVE_NAME`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`, `ARCHIVE_NAME`.

`--archive` is mandatory. Without it the operation fails immediately and
cleanly, before contacting the repository:

```
[ERROR] delete requires --archive NAME
```

This is a deliberate guard: a bare `borg delete` would target the whole
repository, and the wrapper never issues one.

```bash
tngbackup delete --config /etc/tngbackup.conf --archive archive-20260820-030001

# Confirm the target first
DRYRUN=y tngbackup delete --config /etc/tngbackup.conf --archive archive-20260820-030001
```

Warnings:

- Destructive and not undoable.
- Space is released only after `compact`.
- For routine cleanup, use `prune` with a retention policy rather than manual
  `delete`.

### extract

Restores the contents of an archive into a directory.

Runs, from inside the target directory: `borg extract ::ARCHIVE_NAME`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`, `ARCHIVE_NAME`.
**Optional:** `RESTORE_PATH` / `--path`.

`--archive` is mandatory:

```
[ERROR] extract requires --archive NAME
```

The destination is `RESTORE_PATH` (or `--path`), falling back to the **current
working directory** when neither is set - so always pass one explicitly in
automation. The directory is created if it does not exist (skipped under
`DRYRUN=y`), and the extraction runs in a subshell that `cd`s into it, so the
caller's working directory is unaffected.

```bash
tngbackup extract --config /etc/tngbackup.conf \
                  --archive archive-20260905-030001 \
                  --path /tmp/restore
```

Sample output:

```
[2026-09-05 11:03:20] [INFO] Extracting archive archive-20260905-030001 into /tmp/restore
[2026-09-05 11:06:02] [INFO] extract completed successfully
[2026-09-05 11:06:02] [INFO] Operation 'extract' finished with status SUCCESS in 162s
```

Remember: with `extract`, `--path` is the **destination**, not a selector for
what to restore.

Borg restores paths as they were stored, relative to the extraction directory.
An archive of `/etc` extracted into `/tmp/restore` produces `/tmp/restore/etc/...`.
Always extract into a scratch directory first, inspect the result, then move
files into place. Extracting directly over a live filesystem risks overwriting
good data with old data.

To restore a single file or subtree, use Borg directly - path selectors are not
exposed by the wrapper:

```bash
export BORG_PASSPHRASE='...'
cd /tmp/restore
borg extract /mnt/backup/borg-repo::archive-20260905-030001 etc/nginx/nginx.conf
```

Preview without writing anything:

```bash
borg extract --dry-run --list /mnt/backup/borg-repo::archive-20260905-030001
```

| Message | Cause | Fix |
|---|---|---|
| `extract requires --archive NAME` | No archive given | Pass `--archive`; find names with `tngbackup list`. |
| `Cannot create restore path: ...` | Parent not writable | Choose a writable destination or run as root. |
| `Permission denied` while writing | Restore dir not writable | Fix ownership, or run as root to preserve owners/modes. |
| Files land in an unexpected place | Archive paths are relative | Look one level deeper: `find /tmp/restore -maxdepth 2`. |
| `No space left on device` | Restore target too small | Restore selectively, or to a bigger filesystem. |

### break-lock

Removes a stale repository lock that prevents backup operations.

Runs: `borg break-lock $REPO_URI`

**Required:** `REPO_URI`, `REPO_PASSPHRASE`.

When a backup crashes or is interrupted without cleaning up, Borg leaves the repository locked. Subsequent backup attempts fail with "Failed to create/acquire the lock (timeout)". Use `break-lock` to remove the stale lock:

```bash
tngbackup break-lock --config /etc/tngbackup.conf
```

**Troubleshooting:**

| Message | Cause | Fix |
|---|---|---|
| `Repository ... does not exist` | Wrong `REPO_URI` | Verify path/URI. |
| `passphrase supplied ... is incorrect` | Wrong `REPO_PASSPHRASE` | Fix the config. |
| Lock successfully removed | Operation succeeded | Retry your backup operation. |

**Note:** This operation is for troubleshooting only. Normal backup operations should not require manual lock removal. If you frequently encounter stale locks:
- Consider using `PRERUN="borg break-lock 2>/dev/null || true"` to auto-clean before each backup
- Investigate why backups are crashing (disk space, permissions, network issues)

---

## Interactive menu

Running `tngbackup` with no operation (and no `--help`) shows a menu:

```
╔═══════════════════════════════════╗
║      TNGBackup v2.0.2             ║
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

Pressing Enter with no input selects `0` and exits. An invalid entry redisplays
the menu.

The menu runs **before** the configuration is loaded and simply sets
`OPERATION`; the script then continues normally in the same process. Every
other option you passed survives, so combining the menu with flags works as
expected:

```bash
tngbackup --config /etc/tngbackup/webserver.conf \
          --archive archive-20260905-030001 \
          --log /var/log/tngbackup.log
# → pick 3 (List archives): lists that archive, from that config, into that log
```

The same applies to batch mode: choosing an operation from the menu and passing
a config **directory** runs that operation across every config in it.

The menu reads from standard input, so it must never be used from cron, a
systemd unit, or any other non-interactive context. Always name an operation
explicitly there.

---

## Retention policy

The `KEEP_*` variables map one-to-one onto Borg's `--keep-*` prune options.
Borg's algorithm is:

1. Sort archives newest to oldest.
2. For each rule in turn, walk the archives and keep the **newest archive in
   each time bucket** (hour, day, week, month, year) until N buckets have been
   kept.
3. Keep the union of all rules' selections. Delete everything else.

Two consequences that surprise people:

- Rules are **not** additive quotas on a single list. `KEEP_DAILY=7` plus
  `KEEP_WEEKLY=4` does not keep 11 archives; the weekly rule usually re-selects
  archives the daily rule already kept, so the real total is smaller.
- A rule "keeps the last N periods that contain an archive", not "the last N
  calendar periods". If the machine was off for a month, the monthly rule
  reaches further back rather than losing a slot.

### The defaults

Unlike most settings, retention is **not** empty by default:

```
KEEP_LAST=10   KEEP_HOURLY=(none)   KEEP_DAILY=7
KEEP_WEEKLY=4  KEEP_MONTHLY=12      KEEP_YEARLY=(none)
```

so a config that never mentions retention still prunes with
`--keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12`: roughly
20 archives spanning about a year. That is a sane default, but it is a real
policy that will delete archives, so decide consciously rather than inheriting
it by accident. Set the variables explicitly in every config file you write.

To disable a single rule, set it to `0` or `""`. Setting **all six** to `0`
does not prune everything - it makes `prune` refuse to run and report a
failure.

### Worked example 1 - daily server, three-month history

```bash
KEEP_LAST="3"
KEEP_HOURLY=""
KEEP_DAILY="7"
KEEP_WEEKLY="4"
KEEP_MONTHLY="3"
KEEP_YEARLY=""
```

One backup per night. After a year of running, the repository holds roughly:

| Rule | Keeps | Approximate archives |
|---|---|---|
| `KEEP_LAST=3` | 3 newest, unconditionally | 3 (all overlap the daily set) |
| `KEEP_DAILY=7` | newest archive of each of the last 7 days | 7 |
| `KEEP_WEEKLY=4` | newest of each of the last 4 weeks | ~3 new (1 overlaps the daily set) |
| `KEEP_MONTHLY=3` | newest of each of the last 3 months | ~2 new (1 overlaps the weekly set) |

Total: about 12 archives, spanning roughly 90 days. Recovery granularity is one
day for the last week, one week for the last month, one month for the last
quarter.

### Worked example 2 - hourly backups of a busy database

```bash
KEEP_LAST="2"
KEEP_HOURLY="24"
KEEP_DAILY="7"
KEEP_WEEKLY="4"
KEEP_MONTHLY=""
KEEP_YEARLY=""
```

One backup per hour. Kept: 24 hourly points covering the last day, then daily
points for a week, then weekly points for a month - about 32 archives. This is
the right shape for data where a mistake is usually noticed within hours.

### Worked example 3 - long legal retention

```bash
KEEP_LAST="5"
KEEP_HOURLY=""
KEEP_DAILY="14"
KEEP_WEEKLY="8"
KEEP_MONTHLY="24"
KEEP_YEARLY="7"
```

About 45 archives spanning seven years. Deduplication makes this far cheaper
than it sounds when the data changes slowly, but it also means the repository
never stops growing; check `info` output periodically.

### `KEEP_LAST`

`KEEP_LAST=N` keeps the N newest archives irrespective of time. Use it as a
safety floor combined with time-based rules: the union always contains at least
the N most recent archives, even if the time-based rules would select fewer.

### Validating a policy

Two steps, in order. First confirm what the script will pass:

```bash
DEBUG=y DRYRUN=y tngbackup prune --config /etc/tngbackup.conf
```

Then confirm what Borg would do with it, against the real archive list:

```bash
export BORG_PASSPHRASE='...'
borg prune --list --dry-run \
    --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12 \
    /mnt/backup/borg-repo
```

Output marks each archive `Keep` or `Would prune`:

```
Keep         archive-20260905-030001   Fri, 2026-09-05 03:00:01
Keep         archive-20260904-030001   Thu, 2026-09-04 03:00:01
Would prune  archive-20260820-030001   Wed, 2026-08-20 03:00:01
```

Then remember that pruning frees nothing until `compact` runs.

---

## Batch mode

Passing a **directory** to `--config` (or setting `TNGB_CONFIG` to a directory)
switches TNGBackup into batch mode. Every `*.conf` file directly inside the
directory is processed in turn, in shell glob order (effectively alphabetical).

For each file the script:

1. Logs `Processing: <file>`.
2. Resets `REPO_URI`, `REPO_PASSPHRASE`, `BACKUP_PATH`, `BACKUP_EXCLUDE` and
   `ARCHIVE_NAME` to empty, so one config cannot silently inherit another's
   repository, credentials, sources, exclusions or archive name.
3. Sources the config file. A file that fails to source is logged as a warning
   and skipped; the batch continues.
4. Validates the configuration. A failed validation is counted as a failure and
   the file is skipped.
5. Runs the requested operation through the same `dispatch_operation` function
   used by single-config runs.

Batch mode supports **all ten operations** - whatever operation you name (or
choose from the menu) is applied to every config in the directory. `backup`,
`check` and `prune` are the ones that make sense unattended; `mount` across a
whole directory is rarely what you want.

Failures are counted, not ignored: the batch runs to completion, and the script
**exits non-zero if any config failed**. A config whose operation finished with
a Borg *warning* is not counted as a failure - it produced its result - but it
is still recorded distinctly as `WARNING` in the audit log.

**What still carries over between files:** `BORG_OPT`, all six `KEEP_*`
variables, `RESTORE_PATH`, `MOUNT_PATH`, `SSH_OPT`, `SSH_PORT`,
`BORG_ENCRYPTION`, `LOG_FILE`, `AUDIT_LOG_FILE`, `DEBUG`, `DRYRUN` and
`SHOWTEXT` are **not** reset. Write batch configs defensively: set every
variable you care about explicitly in every file, including empty ones. The
example batch configs in `docs/examples/batch-configs/` follow this rule, and
the retention variables are the ones that matter most - a `prune` run inheriting
the previous config's `KEEP_YEARLY` is a silent data-retention bug.

`--repo` and `--passphrase` are ignored in batch mode: the loop resets both
before sourcing each file. Each config carries its own.

### Worked example

Layout:

```
/etc/tngbackup/            (mode 0700, root:root)
├── database.conf          (mode 0600)
├── home.conf              (mode 0600)
└── webserver.conf         (mode 0600)
```

Each file targets its own repository:

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

Validate the whole directory without writing anything:

```bash
DRYRUN=y tngbackup backup --config /etc/tngbackup/
```

Then run it for real:

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

With one failure the tail reads:

```
[2026-09-05 03:09:55] [WARN] Operation 'backup' failed for: /etc/tngbackup/webserver.conf
[2026-09-05 03:14:30] [INFO] Batch processing complete: 3 config(s) processed, 1 failed
```

and the process exits 1.

Then prune all three with the same command shape:

```bash
tngbackup prune --config /etc/tngbackup/ --audit-log /var/log/tngbackup-audit.log
```

Batch behaviour worth knowing:

- Jobs run **sequentially**, never in parallel. Total wall time is the sum.
- One failing job does not abort the batch, but it does change the exit
  status - so `systemd` and `cron` will report the failure normally.
- Ordering is alphabetical, so prefix filenames if order matters:
  `10-database.conf`, `20-webserver.conf`, `50-home.conf`.
- Only `*.conf` files are picked up. Disable a job by renaming it
  `webserver.conf.disabled`.
- Subdirectories are not searched.
- The final `Batch run completed in Ns` line reports total wall time.

---

## Logging

TNGBackup writes two independent streams.

### Human-readable log (`-l` / `--log` / `LOG_FILE`)

Every `log()` call is appended, and Borg's combined output is `tee`d into the
same file. Format:

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] message
```

Levels are `ERROR`, `WARN`, `INFO`, `DEBUG` (the last only when `DEBUG=y`).
Timestamps use local time.

```
[2026-09-05 03:00:01] [INFO] Starting backup from: /var/www /etc/nginx
[2026-09-05 03:04:47] [INFO] backup completed successfully
[2026-09-05 03:04:47] [INFO] Operation 'backup' finished with status SUCCESS in 286s
```

A run that completed with warnings looks like this - note the `WARN` level and
the `WARNING` status, and that the archive exists:

```
[2026-09-05 03:05:12] [INFO] Starting backup from: /home
/home/alice/.gvfs: open: Permission denied
[2026-09-05 03:09:22] [WARN] backup completed with warnings (borg exit 1)
[2026-09-05 03:09:22] [INFO] Operation 'backup' finished with status WARNING in 250s
```

When set via `--log`, the file is created and `chmod 600` before anything is
written. When no log file is configured at all, Borg output goes to stdout
unchanged - a missing `--log` never suppresses or breaks output.

Writes are best-effort: if the log file becomes unwritable mid-run the message
is dropped rather than aborting the backup.

### Audit log (`--audit-log` / `AUDIT_LOG_FILE`)

One pipe-delimited record per completed operation, designed for parsing:

```
TIMESTAMP_UTC_ISO8601 | operation | status | details | duration_seconds
```

| Field | Description |
|---|---|
| `TIMESTAMP_UTC_ISO8601` | UTC, `%Y-%m-%dT%H:%M:%SZ`, e.g. `2026-09-05T03:04:47Z`. |
| `operation` | `init`, `backup`, `list`, `check`, `prune`, `compact`, `info`, `mount`, `delete`, `extract`. |
| `status` | One of `SUCCESS`, `WARNING` or `FAILED`. `WARNING` means Borg exited 1 - the operation completed, but something was noteworthy (unreadable or vanished files, typically). `FAILED` means Borg exited 2 or higher, or the script rejected the request before invoking Borg. |
| `details` | Context: archive name, repository URI, `all-archives`, `repository`, the retention options applied by `prune`, or `ARCHIVE -> TARGET` for `mount` and `extract`. |
| `duration_seconds` | Whole seconds since the script started. |

Example:

```
2026-09-05T02:15:12Z | init | SUCCESS | /mnt/backup/borg-repo | 1
2026-09-05T03:04:47Z | backup | SUCCESS | archive-20260905-030001 | 286
2026-09-05T03:09:22Z | backup | WARNING | archive-20260905-030512 | 250
2026-09-05T03:14:30Z | backup | FAILED | archive-20260905-030955 | 275
2026-09-05T04:01:38Z | check | SUCCESS | repository | 97
2026-09-05T04:30:12Z | prune | SUCCESS | --keep-last=10 --keep-daily=7 --keep-weekly=4 --keep-monthly=12 | 12
2026-09-05T11:06:02Z | extract | SUCCESS | archive-20260905-030001 -> /tmp/restore | 162
```

The `WARNING` line above is a real backup: an archive named
`archive-20260905-030512` exists and can be restored from. Something was
skipped, and the operational log says what.

In batch mode every config contributes its own record, so a three-config batch
writes three lines.

If `AUDIT_LOG_FILE` is empty, auditing is silently disabled.

Useful queries:

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

The distinction matters when you write monitoring: a grep for `FAILED` now
correctly ignores warnings, so it pages you only for backups that genuinely did
not happen. Treat `WARNING` as something to review rather than something to
wake up for - but do review it, since a growing count of skipped files is how a
permissions or hardware problem announces itself.

### Log rotation

Neither file is rotated by the script. Add `/etc/logrotate.d/tngbackup`:

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

Keep the audit log much longer than the operational log: it is small, and it is
the record that proves backups were running.

---

## Security notes

### The passphrase

Losing the passphrase means permanently losing the backups. Losing control of
it means someone else can read them. Both failure modes are unrecoverable, so
treat it accordingly.

- Store it in a password manager or secrets store, separately from the machine
  being backed up. A passphrase that only exists on the server it protects is
  useless after that server dies.
- Export and store the repository key too:
  ```bash
  borg key export /mnt/backup/borg-repo /root/borg-repo.key
  chmod 600 /root/borg-repo.key
  ```
  For `keyfile*` encryption modes this is mandatory - the key lives only in
  `~/.config/borg/keys` and the repository cannot be opened without it.

### Do not pass the passphrase on the command line

`-p` / `--passphrase` is convenient for one-off local work and dangerous
elsewhere. On a multi-user system, the full command line of every process is
world-readable:

```bash
ps auxww | grep tngbackup     # any user can see this
```

It also lands in shell history. The script disables the shell's own history
recording (`set +o history`), but that does not clean the interactive shell you
typed the command into. Prefer, in order:

1. A `chmod 600` config file containing `REPO_PASSPHRASE`.
2. `BORG_PASSPHRASE` exported from a protected wrapper script or a systemd
   `EnvironmentFile` with mode 600.
3. `BORG_PASSCOMMAND`, letting Borg fetch the secret from a keyring or secret
   store:
   ```bash
   export BORG_PASSCOMMAND='secret-tool lookup borg repo webserver'
   ```
   Note that `validate_config` still requires a non-empty `REPO_PASSPHRASE`, so
   set it to a placeholder if you drive Borg entirely through
   `BORG_PASSCOMMAND`.

The audit log never records the passphrase, and `tests/dispatch-test.sh`
asserts that no passphrase leaks into either log file.

### File permissions

| File | Mode | Owner |
|---|---|---|
| `/etc/tngbackup.conf` | 0600 | root:root |
| `/etc/tngbackup/` | 0700 | root:root |
| `/etc/tngbackup/*.conf` | 0600 | root:root |
| `/var/log/tngbackup.log` | 0600 | root:root |
| `/var/log/tngbackup-audit.log` | 0600 | root:root |
| exported key files | 0600 | root:root |

`install.sh` creates the config template and both log files with mode 0600. If
you add files by hand:

```bash
sudo chmod 600 /etc/tngbackup.conf
sudo chmod 700 /etc/tngbackup
sudo chmod 600 /etc/tngbackup/*.conf
sudo chmod 600 /var/log/tngbackup*.log
```

Audit periodically:

```bash
find /etc/tngbackup* /var/log/tngbackup*.log \
     \( -perm /o+rwx -o -perm /g+w \) -ls
```

Anything printed by that command is too permissive.

### Config files are executed

`load_config` uses `source`. A configuration file is running code, with the
privileges of the invoking user - usually root. Never source a config file you
did not write, never make the config directory group- or world-writable, and
never keep a config file with a real passphrase inside a git repository. Add to
`.gitignore`:

```
*.conf
!docs/examples/**/*.conf
```

### SSH hygiene

- Use a dedicated key per client, with no passphrase (so it can run
  unattended), protected by file permissions.
- Restrict the key on the server with
  `command="borg serve --restrict-to-repository ... --append-only",restrict`.
- The default `SSH_OPT` already includes `BatchMode=yes`, so a missing key
  fails fast instead of hanging. If you override `SSH_OPT`, keep it.
- `StrictHostKeyChecking=accept-new` (also a default) trusts the host key on
  first contact. That is a reasonable compromise for automation, but on a
  hostile network pre-seed `known_hosts` and use `StrictHostKeyChecking=yes`
  instead:
  ```bash
  ssh-keyscan -p 22 backup.example.com >> /root/.ssh/known_hosts
  ```

### Non-interactive Borg defaults

The script exports `BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes` and
`BORG_RELOCATED_REPO_ACCESS_IS_OK=yes` so Borg can never block on those two
confirmation prompts. Both are safety prompts, and suppressing them is a
deliberate trade: reliability of unattended runs over a warning you could not
answer anyway. Both honour an existing environment value, so set either to `no`
if you would rather those conditions abort the run:

```bash
BORG_RELOCATED_REPO_ACCESS_IS_OK=no tngbackup backup --config /etc/tngbackup.conf
```

### Cleanup behaviour

The `EXIT`/`INT`/`TERM` trap unsets `REPO_PASSPHRASE`, `BORG_PASSPHRASE`,
`BORG_RSH`, `REPO_URI` and `BACKUP_PATH`, `shred`s any temporary config file it
created, and attempts to unmount a leftover `MOUNT_PATH`. A successful `mount`
clears `MOUNT_PATH` first, so the trap never tears down a mount you asked for.
This limits exposure within the process lifetime; it does not protect the
config file on disk, which is why permissions matter.

### DEBUG output

`DEBUG=y` prints diagnostics including the full Borg command line and the
retention policy. It does not print the passphrase, but it does describe your
repository layout - review the output before pasting it into a bug report or
chat.

---

## Scheduling

Unattended runs must always name an operation explicitly - otherwise the
interactive menu blocks forever on `read`.

### cron

Edit root's crontab with `crontab -e`:

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

Batch mode, all jobs in `/etc/tngbackup/`:

```cron
0 3 * * * /usr/local/bin/tngbackup backup --config /etc/tngbackup/ \
            --log /var/log/tngbackup.log --audit-log /var/log/tngbackup-audit.log
0 4 * * * /usr/local/bin/tngbackup prune --config /etc/tngbackup/ \
            --audit-log /var/log/tngbackup-audit.log
```

Hourly backups of a fast-changing dataset:

```cron
15 * * * * /usr/local/bin/tngbackup backup --config /etc/tngbackup/database.conf \
             --audit-log /var/log/tngbackup-audit.log
```

cron tips:

- cron's `PATH` is minimal. Either set `PATH` at the top of the crontab (as
  above) or use absolute paths everywhere.
- `%` is special in crontab and must be escaped as `\%` - relevant if you build
  an archive name with `date +%F` inline.
- Set `MAILTO` so failures are noticed. A backup that completed with warnings
  exits 0 and so will *not* generate failure mail - watch the audit log for
  `WARNING` records instead. Because the script exits non-zero on
  failure (batch included), cron reports failures reliably. With `SHOWTEXT=y` a
  successful run still prints output and generates mail every night; set
  `SHOWTEXT="n"` in the config and rely on `LOG_FILE` so mail arrives only on
  stderr output.
- Stagger jobs across hosts so twenty machines do not hit the same backup
  server at 03:00.

### systemd timer

More robust than cron for laptops and machines that are not always on:
`Persistent=true` catches up a missed run, and `RandomizedDelaySec` spreads the
load.

`install.sh` places both units in `/etc/systemd/system/` when that directory
exists; otherwise install them by hand:

```bash
sudo install -m 0644 docs/tngbackup.service /etc/systemd/system/
sudo install -m 0644 docs/tngbackup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tngbackup.timer
```

Check and drive it:

```bash
systemctl list-timers tngbackup.timer
systemctl start tngbackup.service      # run now, out of schedule
journalctl -u tngbackup.service -n 100 --no-pager
systemctl status tngbackup.service
```

Because the script exits with the operation's status, a failed backup marks the
unit `failed` and can trigger an `OnFailure=` handler. A backup that completed
with warnings exits 0, so the unit stays `succeeded` and no handler fires -
which is the intended behaviour, since an archive was produced.

```ini
# In tngbackup.service
OnFailure=notify-admin@%n.service
```

For several jobs, use a templated unit. `/etc/systemd/system/tngbackup@.service`:

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

Then enable one timer per instance: `systemctl enable --now tngbackup@webserver.timer`.

Because `Type=oneshot` units run to completion, systemd will not start a second
run while one is still going - a useful guard against overlapping backups that
cron does not give you.

---

## Troubleshooting

### Repository is locked

```
Failed to create/acquire the lock /mnt/backup/borg-repo/lock.exclusive
```

A Borg process holds the lock, or a previous one died without releasing it.

```bash
# 1. Is something actually running?
ps aux | grep -E 'borg|tngbackup'

# 2. If yes, wait for it, or stop it cleanly (SIGTERM, never SIGKILL -
#    the cleanup trap needs to run)
kill -TERM <pid>

# 3. Only if nothing is running, break the stale lock:
borg break-lock /mnt/backup/borg-repo
```

A forgotten `tngbackup mount` is a common cause: `borg mount` daemonises and
holds the repository. Check with `mount | grep borg` and `borg umount`.

Never break a lock while a Borg process might still be writing; that risks
repository corruption. For a remote repository, check the **server** for
running `borg serve` processes too.

To prevent overlap, wrap invocations in `flock`:

```bash
flock -n /var/lock/tngbackup.lock /usr/local/bin/tngbackup backup --config /etc/tngbackup.conf
```

Or use a `Type=oneshot` systemd service, which serialises by design.

### SSH fails or times out

Borg is invoked with stdin closed, so an SSH prompt now fails fast instead of
hanging. Expect an immediate error rather than a stuck job.

Almost always a key problem: an unknown host key, a passphrase-protected key,
or a fallback to password auth.

```bash
# Reproduce non-interactively - this must succeed silently
ssh -o BatchMode=yes -o ConnectTimeout=5 -p 22 borg@backup.example.com borg --version
```

Check what the script is actually using:

```bash
DEBUG=y DRYRUN=y tngbackup list --config /etc/tngbackup.conf
# [DEBUG] Remote repository detected, BORG_RSH configured
```

Fixes:

```bash
# Pre-seed the host key
ssh-keyscan -p 22 backup.example.com >> /root/.ssh/known_hosts

# Point SSH_OPT at an explicit key - root's environment differs from yours,
# and there is no ssh-agent under cron or systemd.
# Repeat the defaults you still want; SSH_OPT replaces them wholesale.
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i /root/.ssh/borg_ed25519"
```

If long backups are dropped by a firewall, add keepalives:

```bash
SSH_OPT="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
```

If `SSH_OPT` seems to be ignored, confirm `REPO_URI` really starts with
`ssh://` - `BORG_RSH` is only set for that URI scheme, and a local-looking
`user@host:/path` URI will not trigger it.

### borg binary not found in PATH

```
[ERROR] borg binary not found in PATH
```

Either Borg is not installed, or the job's `PATH` does not include it.

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

If Borg is at `/usr/local/bin/borg` or in a pipx venv, set `PATH` explicitly in
the crontab or add `Environment="PATH=..."` to the systemd unit.

For remote repositories, Borg must also be installed on the server, and the
server's non-interactive `PATH` must find it. If it does not:

```bash
export BORG_REMOTE_PATH=/usr/local/bin/borg
```

### Permission denied

Distinguish four cases:

1. **Reading source files.** Borg skips unreadable files, reports them at the
   end, still creates the archive, and exits 1. TNGBackup records that as
   `WARNING` and exits 0 - the backup is usable. Read the log to see what was
   skipped; if the source needs root, run the backup as root.
2. **Writing to the repository.** The repository directory (or the remote SSH
   user's target path) must be writable by the invoking user:
   ```bash
   ls -ld /mnt/backup/borg-repo
   sudo chown -R borg:borg /mnt/backup/borg-repo
   ```
3. **Creating the log file.** `--log` does `touch` + `chmod 600` eagerly and
   aborts the run if the parent directory is not writable. Let `install.sh`
   create `/var/log/tngbackup.log`, or pick a writable path.
4. **Creating a mountpoint or restore directory.** `mount` and `extract`
   `mkdir -p` their target and fail cleanly (`Cannot create mountpoint:` /
   `Cannot create restore path:`) if the parent is not writable.

Beware SELinux/AppArmor on the log and repository paths - check
`ausearch -m avc -ts recent` if permissions look correct but access is refused.

### Wrong passphrase

```
passphrase supplied in BORG_PASSPHRASE, by BORG_PASSCOMMAND or via keyfile is incorrect.
```

The passphrase does not match this repository. Check for:

- Trailing whitespace or a stray newline in the config value.
- Shell expansion inside double quotes. A passphrase containing `$`, `` ` `` or
  `\` is mangled by `REPO_PASSPHRASE="p$$w0rd"`. Use single quotes:
  `REPO_PASSPHRASE='p$$w0rd'`.
- A leftover `BORG_PASSPHRASE` exported in the environment: `env | grep BORG`.
- The wrong repository - `REPO_URI` pointing at a different repo than you think.
- A `--passphrase` on the command line that you forgot about: it now genuinely
  overrides the config file.

Verify by hand:

```bash
BORG_PASSPHRASE='...' borg list /mnt/backup/borg-repo
```

There is no way to recover a repository whose passphrase is genuinely lost.

### My CLI option seems to be ignored

Only `--repo` and `--passphrase` are re-applied after the config file is
sourced. `--archive`, `--path`, `--mountpoint`, `--log` and `--audit-log` are
set *before* sourcing, so a config file that assigns the corresponding variable
unconditionally wins. Either remove that line from the config, or guard it:

```bash
ARCHIVE_NAME="${ARCHIVE_NAME:-}"
LOG_FILE="${LOG_FILE:-/var/log/tngbackup.log}"
```

In batch mode `--repo` and `--passphrase` are ignored entirely by design.

### Archive already exists

```
Archive archive-20260905-030001 already exists
```

`ARCHIVE_NAME` is fixed rather than unique. Leave it empty so a timestamped
name is generated. Note this is no longer a batch-mode hazard: `ARCHIVE_NAME`
is reset between configs.

If two backups run within the same second, the generated names collide too -
another reason to serialise runs with `flock` or a `oneshot` unit.

### prune refuses to run

```
[ERROR] No retention policy configured (set at least one of KEEP_LAST, ...)
```

Every `KEEP_*` variable is empty or `0`. This is a guard, not a bug: a prune
with no rules would delete every archive. Set at least one rule, or do not run
`prune` on that repository.

### prune deleted more than expected

The `KEEP_*` defaults are non-empty (`KEEP_LAST=10`, `KEEP_DAILY=7`,
`KEEP_WEEKLY=4`, `KEEP_MONTHLY=12`), so a config that omits retention still has
a policy. Check what was actually applied - the audit log records the exact
options used by each prune:

```bash
awk -F' \\| ' '$2=="prune"{print $1, $4}' /var/log/tngbackup-audit.log
```

In batch mode, remember `KEEP_*` is not reset between configs.

### The script hangs with no output on a server

You invoked it with no operation, and it is sitting on the interactive menu's
`read`. Always pass an operation in automation. Borg itself can no longer hang
on a prompt - stdin is closed for every invocation.

### General debugging recipe

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

Redact repository URIs and passphrases before sharing any of that output.

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success, **or completed with warnings**. Also returned by `--help` and by choosing `0` in the menu. |
| `1` | Failure detected by the script itself: invalid option, config not found or unreadable, failed validation (missing `REPO_URI`/`REPO_PASSPHRASE`/`BACKUP_PATH`, `borg` not on `PATH`), unknown operation, a missing `--archive` for `delete`/`extract`, an unconfigured retention policy for `prune`, or an unwritable mountpoint/restore directory. In batch mode, at least one config failed. |
| `2` and above | Propagated from Borg itself (`2` is Borg's own "error"), or from the shell under `set -euo pipefail` - e.g. `126`/`127` for a command that could not be executed, `130` for interruption by Ctrl-C, `143` for `SIGTERM`. |

The script exits with the **operation's own exit code**: `main` captures the
result of `dispatch_operation` and exits with it, so Borg's status reaches the
caller rather than being swallowed.

Borg's convention is `0` success, `1` warning, `2` error, and `finish_operation`
maps it deliberately:

- **`0` → `SUCCESS`, exit 0.**
- **`1` → `WARNING`, exit 0.** The operation completed and produced its result;
  something was merely noteworthy, most often a file that could not be read or
  that vanished mid-backup. A backup like this **is** a usable backup, so it
  does not fail the run, mark a systemd unit `failed`, or generate cron mail.
  It is recorded as `WARNING` in the audit log so you can still find it.
- **`2` or higher → `FAILED`, exit N.** A real error; the exit code passes
  through unchanged.

Note the asymmetry: exit code `1` from `tngbackup` never means "Borg warned" -
it means the script rejected the request before Borg ran. Borg's own warnings
never reach the caller as a non-zero status.

**Batch mode** counts failures and returns 1 if any config failed, so a zero
exit means every job at least completed. Warnings do not count as batch
failures, for the same reason. The individual results are still worth auditing:

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

## Tests

Two test scripts live in `tests/`. Both are standalone Bash and take no
arguments; both clean up after themselves.

### tests/dispatch-test.sh

Runs anywhere - **no Borg installation required**. It puts a stub `borg` first
on `PATH` that records the command line it was invoked with, then drives
`tngbackup` through 26 checks covering:

- dispatch of all ten operations to the right Borg subcommand
- `borg create` argument construction: `BORG_OPT` word-splitting, one
  `--exclude` per `BACKUP_EXCLUDE` item, archive name generation
- retention option construction from the `KEEP_*` variables
- CLI-versus-config precedence
- dry-run mode executing nothing
- the exit-code mapping: Borg `0` → `SUCCESS`/exit 0, `1` → `WARNING`/exit 0,
  `>= 2` → `FAILED`/exit N
- failure propagation: a failing Borg command makes `tngbackup` exit non-zero
- audit log creation and record format
- that no passphrase leaks into either log file
- batch mode processing every config in a directory
- `--help` output and rejection of an unknown operation

```bash
./tests/dispatch-test.sh
```

```
=== Result ===
Passed: 26/26
PASS: all dispatch checks passed
```

Exit codes: `0` all passed, `1` one or more failed. Override the script under
test with `TNGBACKUP=/usr/local/bin/tngbackup ./tests/dispatch-test.sh`.

### tests/integration-test.sh

Requires a real Borg (1.2+) and Bash 4+. It creates a throwaway repository in a
temporary directory, exercises every operation against it for real - init,
backup, list, info, check, prune, compact, extract with content verification,
delete - verifies the audit log, then removes everything.

```bash
./tests/integration-test.sh

# Also exercise mount (needs FUSE support in Borg)
TNGB_TEST_MOUNT=y ./tests/integration-test.sh
```

Without `TNGB_TEST_MOUNT=y` the mount check is skipped and reported as
`[SKIP]`, since FUSE is not available everywhere.

Exit codes: `0` all passed, `1` one or more failed, **`2` prerequisites
missing** (no Borg on `PATH`, or an unsupported Bash). A CI job can treat `2`
as "skipped" rather than "broken".

Run both before deploying a change, and run the integration test once against
your production Borg version before trusting the tool with real data.

---

## See also

- `install.sh` - installer and uninstaller
- `docs/examples/tngbackup.conf` - annotated reference configuration
- `docs/examples/local-backup.conf` - local repository example
- `docs/examples/remote-backup.conf` - SSH repository example
- `docs/examples/batch-configs/` - batch-mode examples
- `docs/tngbackup.1` - man page
- `docs/tngbackup.service`, `docs/tngbackup.timer` - systemd units
- `tests/dispatch-test.sh`, `tests/integration-test.sh` - test suite
- [Borg Backup documentation](https://borgbackup.readthedocs.io/)
- `borg(1)`

---

TNGBackup 2.0.2 - Author: Massimo "RedFoxy Darrest" Cicciò - License: CC BY-NC 4.0 (Non-Commercial) + Commercial
