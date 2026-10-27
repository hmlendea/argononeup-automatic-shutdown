# Contributing to argononeup-automatic-shutdown

This document covers the guidelines and processes for contributing to this project, including how to report issues, suggest enhancements, submit code changes, and follow project standards.

## 📑 Table of Contents

- [How to Contribute](#-how-to-contribute)
  - [Reporting Issues](#reporting-issues)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Code Contributions](#code-contributions)
    - [Prerequisites](#prerequisites)
    - [Development Setup](#development-setup)
    - [Making Changes](#making-changes)
    - [Pull Request Guidelines](#pull-request-guidelines)
- [Code Style](#code-style)
- [Testing](#testing)
- [Documentation](#documentation)
- [License](#-license)

## 🤝 How to Contribute

### Reporting Issues

- Search existing issues first.
- Use the issue templates if available.
- Provide clear reproduction steps.
- Include environment details.

### Suggesting Enhancements

- Check the roadmap and existing discussions.
- Explain the use case and expected behaviour.
- Consider implementation complexity.

### Code Contributions

#### Prerequisites

- Linux with `systemd` (user-level systemd service support)
- GNOME session (uses Mutter idle monitor over D-Bus)
- `bash`, `gdbus`, `sed`, `grep`, `who`, `gpioget`
- Standard Unix utilities (`install`, `mkdir`)

#### Development Setup

```bash
# Clone the repository
git clone https://github.com/hmlendea/argononeup-automatic-shutdown.git
cd argononeup-automatic-shutdown

# Make scripts executable
chmod +x install uninstall argononeup-automatic-shutdown.sh

# Install for testing
./install
```

#### Making Changes

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes.
4. Test manually by running the script directly:
   ```bash
   ./argononeup-automatic-shutdown.sh
   ```
5. Run the install script to verify installation works:
   ```bash
   ./install
   ```
6. Commit with clear and descriptive messages.
7. Push to your fork.
8. Open a Pull Request.

#### Pull Request Guidelines

- Target the `master` branch.
- Keep PRs focused and atomic.
- Revise documentation if applicable.
- Ensure the CI checks pass.

### Code Style

Follow the project's shell coding standards:
- Use `set -euo pipefail` at the top of every non-interactive script
- Use `[[ ]]` over `[ ]` for conditional tests
- Use `$(command)` for command substitution (not backticks)
- Constant strings use single quotes; variable strings use double quotes
- Variables inside functions declared with `local` when possible
- Function names: lowercase with underscores (`my_function`)
- Variable names: uppercase with curly braces (`${VAR_NAME}`)
- Use environment variables for paths (`${HOME}`, `${XDG_CONFIG_HOME}`)
- Run `shellcheck` on modified scripts before committing

### Testing

No automated test suite exists. Test manually:

```bash
# Run the script directly to verify logic
./argononeup-automatic-shutdown.sh

# Test installation
./install

# Verify service status
systemctl --user status argononeup-automatic-shutdown.service

# View logs
journalctl --user -u argononeup-automatic-shutdown.service -n 50

# Test uninstall
./uninstall
```

### Documentation

- Revise relevant docs for changes (`README.md`, `docs/` files)
- Follow the documentation style guide
- Preview changes locally if possible

## 📄 License

By contributing, you agree that your contributions will be licensed under the GNU General Public License v3.0.

## 🔒 Security

Report security vulnerabilities per the [Security Policy](./SECURITY.md).