# CHANGELOG

All notable changes to the TNGBackup project are documented in this file.

---

## [2.0.1] — 2026-09-06

### Added

- **Backup Hooks (PRERUN/POSTRUN):** Native support for scripts/commands to execute before and after backup operations
  - `PRERUN`: Executed before backup; if it fails (exit ≠ 0), backup is aborted. Useful for database dumps, snapshots, pre-backup validation
  - `POSTRUN`: Executed after backup (regardless of result); its failure does not change backup status. Useful for cleanup, notifications, archiving

- **Companion Operations (CHECK/PRUNE/COMPACT around backup):** New variables to automate maintenance operations during backup
  - `CHECK_BACKUP`: 0=disabled, 1=before backup, 2=after backup
  - `PRUNE_BACKUP`: 0=disabled, 1=before backup, 2=after backup
  - `COMPACT_BACKUP`: 0=disabled, 1=before backup, 2=after backup
  - Useful for automating complete backup pipelines (e.g., check → backup → prune → compact)

- **Repository Auto-Creation:** Automatic creation of repository and parent directory during backup
  - `CREATE_REPO`: Automatically initialize repository if missing (default: y)
  - `CREATE_REPO_DIR`: Automatically create parent directory if missing (default: y)
  - Eliminates need to manually run `tngbackup init` before first backup

- **SSH Password Authentication:** Support for SSH password-based authentication (less secure but sometimes necessary)
  - `SSH_PASSWORD`: Allows using SSH password instead of certificates
  - Requires `sshpass` utility installed on the system
  - **Security note:** Always prefer key-based authentication (IdentityFile)

- **Version Check and Update Notification:** Built-in version management with GitHub integration
  - `-V` or `--version` flags display current version and check for updates
  - Automatically queries GitHub API for latest release
  - Provides direct download link if newer version is available
  - Graceful fallback if GitHub is unreachable or curl is unavailable
  - Displays author, license, and GitHub repository link

- **Interactive Passphrase Input:** Secure passphrase entry without echoing to terminal
  - Use `-p` without value to prompt for passphrase (like `mysql -u root -p`)
  - Input is hidden from display for security
  - Example: `tngbackup backup -p` then enter passphrase when prompted

- **Improved Help System:** Context-aware help display
  - Shows help when no config file exists and no operation specified
  - Shows interactive menu when config file exists
  - Full help includes GitHub link for users to find documentation online

- **Break-Lock Operation:** Troubleshooting tool for stale locks
  - New `break-lock` operation to remove stale repository locks
  - Useful when a backup crashes and leaves the repository locked
  - Usage: `tngbackup break-lock --config <config>`
  - Resolves "Failed to create/acquire the lock (timeout)" errors

### Changed

- Updated migration guides to reflect native hook support (no longer need external wrapper script)
- Added hook support to README main features
- Version bumped to 2.0.1 across all project files
- New section in example configuration for companion operations

### Documentation

- Updated `docs/MIGRATION_it.md` and `docs/MIGRATION_en.md` with hook usage examples
- Updated example configuration file `docs/examples/tngbackup.conf`:
  - Dedicated section for backup hooks
  - Dedicated section for companion operations
  - Dedicated section for repository auto-creation
  - SSH_PASSWORD documentation (with security warnings)
- Updated CLAUDE.md with documentation of new features

---

## [2.0.0] — 2026-09-05

### Added

- **Stable version with new architecture:** Complete redesign from v0.8.8
- **Unified repository:** Single `REPO_URI` instead of separate LOCAL/REMOTE
- **Explicit operations:** CLI commands for each operation (init, backup, list, mount, check, prune, compact, info, delete, extract)
- **Flexible configuration:** Precedence CLI > File > Environment > Default
- **Batch Mode:** Support for processing multiple configs from a directory
- **Structured logging:** Separation between operational log and audit log (machine-readable)
- **Enhanced security:** Credentials in memory only, no disk traces for SSH
- **Complete documentation:** Bilingual README (IT/EN), USAGE.md (2200+ lines), configuration examples

### Changed from v0.8.8

- Repository configuration: `LOCAL/REMOTE_REPO` → `REPO_URI`
- BACKUP_PATH separator: `;` → space
- Retention: `LOCAL_KEEP_*` / `REMOTE_KEEP_*` → unified `KEEP_*`
- SSH: `SSH_USER`, `SSH_HOST`, `SSH_PORT`, `SSH_CERT` → `ssh://` URI + `SSH_OPT`
- Encryption: `BORG_ENCRIPTION` (typo) → `BORG_ENCRYPTION`
- Auto-init: `LCREATE_REPO`, `RCREATE_REPO` → `tngbackup init` (explicit operation)
- Hook variables: `PRERUN`, `POSTRUN` removed (not supported in v2.0; natively supported in v2.1+)

### Testing

- `tests/dispatch-test.sh`: 26 checks without Borg (mock)
- `tests/integration-test.sh`: Full test with real Borg (optional mount)

### Documentation

- Migration guide from v0.8.8: `docs/MIGRATION.md`
- Advanced usage: `docs/USAGE.md`
- Config examples: `docs/examples/`
- Man page: `docs/tngbackup.1`
- Systemd units: `docs/tngbackup.service`, `docs/tngbackup.timer`

---

## [0.8.8] — Pre-September 2026

### Status

Previous version with separate LOCAL/REMOTE architecture.

---

## Versioning Format

TNGBackup follows [Semantic Versioning](https://semver.org/):

- **MAJOR** — Incompatible changes with previous versions
- **MINOR** — New features with backward compatibility
- **PATCH** — Bug fixes with backward compatibility

---

## How to Upgrade

### From v2.0.0 to v2.0.1

Full compatibility. If you use `PRERUN` or `POSTRUN` in config:

**Before (v0.8.8→v2.0.0, required wrapper script):**
```bash
#!/bin/bash
/path/to/prerun.sh
tngbackup backup --config /etc/tngbackup.conf
/path/to/postrun.sh
```

**After (v2.0.1, native support):**
```bash
# In config file:
PRERUN="/path/to/prerun.sh"
POSTRUN="/path/to/postrun.sh"

# Command:
tngbackup backup --config /etc/tngbackup.conf
```

### From v0.8.8 to v2.0.0+

Requires config file conversion. See `docs/MIGRATION_it.md` or `docs/MIGRATION_en.md`.

---

**Last Updated:** September 2026  
**Maintainer:** RedFoxy Darrest
