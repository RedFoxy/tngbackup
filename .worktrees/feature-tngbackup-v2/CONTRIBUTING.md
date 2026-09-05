# Contributing to TNGBackup

Thank you for your interest in contributing to TNGBackup! This document provides guidelines and instructions for contributing to the project.

## Getting Started

### Prerequisites
- Bash 4.0+ (MacOS 10.15+ ships with Bash 3.2; use Homebrew to install Bash 5+)
- Borg Backup 1.3.0+
- Git
- SSH (for remote repository testing)

### Setup
1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/tngbackup.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Configure git with your identity: 
   ```bash
   git config user.name "Your Name"
   git config user.email "your.email@example.com"
   ```

## Development Workflow

### Code Style
- Use 2-space indentation (no tabs)
- Follow Bash best practices from [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use meaningful variable names (UPPERCASE for constants, lowercase for local variables)
- Add comments for complex logic
- Quote all variables: `"${VAR}"` not `$VAR`
- Prefer explicit conditions: `[[ -n "${VAR}" ]]` over shorthand

### Testing
All contributions must pass existing tests before submission:

```bash
# Run syntax validation
bash -n tngbackup.sh
bash -n v2/tngbackup2.sh
bash -n v2/classi/*.sh

# Run integration tests
bash tests/dispatch-test.sh
```

### Adding New Operations
When adding new Borg operations to v2:

1. Create `v2/classi/borg_OPERATION.sh` with function `borg_OPERATION()`
2. Function receives one argument: "local" or "remote"
3. Use shared functions from `v2/classi/functions.sh`:
   - `error()` for errors
   - `debug()` for debug output (controlled by DEBUG variable)
   - `runCMD()` for executing commands with error tracking
4. Set error flags: `Local_SKIP=1` or `Remote_SKIP=1` on failure
5. Source the file in `v2/tngbackup2.sh` main entry point
6. Add corresponding menu option if interactive
7. Update README.md with operation documentation

### Debugging
Enable debug output to trace execution:
```bash
DEBUG=y bash v2/tngbackup2.sh
```

For dry-run (show commands without executing):
```bash
DEBUG=y DRYRUN=y bash v2/tngbackup2.sh
```

## Commit Guidelines

### Message Format
- First line: concise subject (50 characters max), imperative mood
- Blank line
- Body: explain what and why (not how), wrapped at 72 characters
- Reference related issues: "Fixes #123" or "See #456"
- Sign all commits as RedFoxy Darrest <redfoxy@redfoxy.it>

### Examples
```
Fix SSH timeout handling on slow connections

Previously, remote operations would hang indefinitely if the
connection was slow. Now we apply the SSH_OPT timeout setting
consistently across all Borg remote calls.

Fixes #42
```

```
Add borg_extract operation for v2

Implement archive extraction with file filtering and dry-run
support. Follows the same pattern as other v2 operations.
```

### No AI Markers
Commits must **never** contain:
- References to Claude, Anthropic, or AI assistants
- Generated content markers ("I added", "created by")
- Co-Authored-By trailers with AI names
- Any indication of code generation tools

All commits will be authored as RedFoxy Darrest <redfoxy@redfoxy.it>.

## Pull Request Process

1. **Before submitting:**
   - Run all tests: `bash tests/dispatch-test.sh`
   - Run syntax checks on all modified scripts
   - Update README.md if behavior changes
   - Add entry to CHANGELOG.md under "Unreleased" section

2. **Create the PR:**
   - Clear title: "Add feature X" or "Fix issue Y"
   - Description: explain what, why, and how to test
   - Link related issues: "Fixes #123"
   - Request review from maintainers

3. **Review process:**
   - Maintainers will review for correctness and style
   - Address feedback promptly
   - Maintainers will merge once approved

## Reporting Bugs

Use the [Bug Report Template](.github/ISSUE_TEMPLATE/bug_report.md):
- Describe the bug clearly
- Steps to reproduce
- Expected vs actual behavior
- Include environment info (OS, Bash version, Borg version)
- Attach logs if helpful

## Suggesting Features

Use the [Feature Request Template](.github/ISSUE_TEMPLATE/feature_request.md):
- Clear description of the feature
- Use case and motivation
- Proposed implementation (optional)
- Alternative approaches considered

## Documentation

### README Updates
When adding features or operations:
1. Update the feature list in README.md
2. Add examples if user-facing
3. Document any new configuration variables

### Code Comments
- Explain the "why", not the "what"
- Use descriptive variable names to reduce comment need
- Comment complex logic (loops, conditionals)
- Document function parameters in comments

## Questions or Need Help?

- Check existing [Issues](../../issues)
- Review README.md and CLAUDE.md
- Open a discussion or issue for questions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to TNGBackup!
