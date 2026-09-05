---
name: Bug Report
about: Report a bug or unexpected behavior
title: "[BUG] "
labels: bug
assignees: ''

---

## Describe the Bug
A clear and concise description of what the bug is. What did you expect to happen? What actually happened?

## Steps to Reproduce
Steps to reproduce the behavior:
1. Run command: `...`
2. With configuration: `...`
3. Expected result: `...`
4. Actual result: `...`

## Environment
- **OS**: (e.g., Ubuntu 22.04, macOS 13.x, Windows 11 with WSL)
- **Bash version**: (output of `bash --version`)
- **Borg version**: (output of `borg --version`)
- **TNGBackup version**: (commit hash or version tag)

## Configuration
If relevant, please include your configuration (with sensitive data redacted):
```bash
# Redact passphrases and sensitive paths
DEBUG=y
LOCAL=y
REMOTE=n
BACKUP_PATH="/path/to/backup"
```

## Logs
Please include relevant debug output:
```
Run with DEBUG=y to capture detailed logs
$ DEBUG=y bash tngbackup.sh config.conf
[paste output here]
```

## Additional Context
Add any other context about the problem here. For example:
- Network conditions (if remote repository)
- Disk space situation
- Any recent changes to configuration or environment
