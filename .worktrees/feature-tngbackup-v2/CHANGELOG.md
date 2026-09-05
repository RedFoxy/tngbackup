# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-09-05

### Added
- **Complete v2 modular architecture** with 10 Borg operations:
  - `borg_init` - Initialize new repository
  - `borg_create` - Create backup archive
  - `borg_list` - List existing archives
  - `borg_mount` - Mount archive for access
  - `borg_check` - Repository integrity verification
  - `borg_compact` - Reclaim repository space
  - `borg_prune` - Remove old archives per retention policy
  - `borg_info` - Get repository/archive information
  - `borg_delete` - Delete specific archives
  - `borg_extract` - Extract files from archive
- **Interactive menu system** with command dispatch
- **Batch mode** for automation and scripting
- **Security enhancements**:
  - Remote configuration file support with validation
  - Automatic lock detection and resolution
  - Cache validation on startup
  - Passphrase from environment or secure input
- **Audit logging system**:
  - ISO-8601 timestamps
  - Operation start/end markers
  - Success/failure tracking
  - Elapsed time reporting
- **Comprehensive documentation**:
  - README.md with full feature overview
  - CLAUDE.md with architecture guidance
  - Inline function documentation
- **Installation and deployment**:
  - `install.sh` for automated setup
  - Systemd service template (`tngbackup.service`)
  - Cron integration ready
- **Testing framework**:
  - `test.sh` example script
  - Syntax validation for modules
  - Configuration file examples
- **Error handling and validation**:
  - Repository existence checks
  - Passphrase validation
  - SSH connectivity verification
  - Disk space monitoring

### Changed
- Refactored from monolithic v1 to modular v2 architecture
- Improved code organization with dedicated operation modules
- Enhanced configuration management with variable validation
- Better error messages and debug output

### Deprecated
- v1 single-operation approach (tngbackup.sh v0.8.8 deprecated in favor of v2)

### Fixed
- Repository initialization race conditions
- SSH timeout handling on slow connections
- Borg interactive prompt hang on remote operations
- Path handling with special characters

### Security
- Enhanced SSH options (BatchMode, relaxed host key checking, connection timeout)
- Repository encryption with blake2 hash verification
- Lock file protection and automatic cleanup
- Secure passphrase input without shell escaping

## [0.8.8] - 2025-11-15

### Added
- Initial stable release of v1 monolithic backup script
- Local repository support
- Remote SSH repository support
- Basic retention policy configuration
- Dry-run mode for testing

### Features
- Borg Backup integration
- Configuration file-based deployment
- Basic logging and error reporting

---

[2.0.0]: https://github.com/RedFoxy/tngbackup/compare/v0.8.8...v2.0.0
[0.8.8]: https://github.com/RedFoxy/tngbackup/releases/tag/v0.8.8
