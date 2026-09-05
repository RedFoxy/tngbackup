# Contributing to TNGBackup

Thank you for your interest in contributing to TNGBackup! This document outlines guidelines and expectations for contributors.

## Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test your changes (see Testing section)
5. Submit a pull request

## Code Style

- **Bash:** Follows POSIX-compatible conventions used in the main script
- **Naming:** Use descriptive variable and function names (snake_case)
- **Comments:** Document complex logic and non-obvious decisions
- **Indentation:** Use 2 spaces (tabs are converted to spaces)

## Testing

Before submitting a PR, ensure your changes:

- Do not break existing functionality
- Are tested with both `DEBUG=n` and `DEBUG=y`
- Handle edge cases (missing files, SSH errors, permissions issues)
- Work with both local and remote repositories (if applicable)

Run tests:
```bash
bash test.sh
```

For v2 development:
```bash
DEBUG=y bash v2/tngbackup2.sh --help
```

## Reporting Issues

When reporting bugs or suggesting improvements:

1. Check if the issue already exists
2. Provide clear reproduction steps
3. Include relevant configuration (with secrets redacted)
4. Specify OS, Bash version, and Borg version
5. Attach debug output: `DEBUG=y bash tngbackup.sh ...`

## Licensing

TNGBackup uses dual licensing:

### Non-Commercial (CC BY-NC 4.0)
- Free to use, modify, and distribute for non-commercial projects
- Requires attribution to RedFoxy Darrest
- Commercial use prohibited without explicit permission

### Commercial License
- Available on negotiated terms
- Contact: redfoxy@redfoxy.it
- No commercial deployment without separate agreement

**By contributing to this project, you agree that your contributions will be licensed under the same dual-license terms as TNGBackup.** This means:

- Your code can be used under CC BY-NC for non-commercial purposes
- Your code may be used under a commercial license (with your proper attribution)
- You retain copyright ownership of your contributions
- You grant TNGBackup and RedFoxy Darrest a non-exclusive, perpetual license to use your contributions

See the LICENSE file for complete licensing details.

## Pull Request Process

1. Update documentation to match your changes
2. Add tests for new functionality
3. Ensure all tests pass
4. Provide a clear description of what your PR does and why
5. Reference any related issues

## Communication

- **Issues:** Use GitHub Issues for bug reports and feature requests
- **Discussions:** Start a discussion for design questions or RFCs
- **Security:** For security issues, email redfoxy@redfoxy.it (do not open public issues)

---

Thank you for contributing to TNGBackup!
